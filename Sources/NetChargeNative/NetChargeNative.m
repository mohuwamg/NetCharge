#import "NetChargeNative.h"
#import <dlfcn.h>
#import <dispatch/dispatch.h>

// Runtime bridge for macOS's charge-limit client. No private headers or
// third-party battery-control binaries are linked into NetCharge.
@protocol NCPowerUISmartChargeClient
- (instancetype)initWithClientName:(NSString *)name;
- (BOOL)isMCLSupported;
- (NSArray<NSNumber *> *)availableChargeLimitsWithError:(NSError **)error;
- (NSUInteger)isMCLCurrentlyEnabled:(NSError **)error;
- (unsigned char)getMCLLimitWithError:(NSError **)error;
- (BOOL)setMCLLimit:(unsigned char)limit error:(NSError **)error;
- (BOOL)disableMCL:(NSError **)error;
@end

static NSString *const NCErrorDomain = @"com.netcharge.native";

static void *NCLoadPowerUI(void) {
    static void *handle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        handle = dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW);
    });
    return handle;
}

static NSError *NCError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:NCErrorDomain code:code
                          userInfo:@{NSLocalizedDescriptionKey: message}];
}

@interface NCNativeChargeClient ()
@property(nonatomic, strong) id<NCPowerUISmartChargeClient> client;
@end

@implementation NCNativeChargeClient

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    if (!NCLoadPowerUI()) return self;
    Class cls = NSClassFromString(@"PowerUISmartChargeClient");
    SEL required[] = {
        @selector(initWithClientName:), @selector(isMCLSupported),
        @selector(availableChargeLimitsWithError:), @selector(isMCLCurrentlyEnabled:),
        @selector(getMCLLimitWithError:), @selector(setMCLLimit:error:),
        @selector(disableMCL:)
    };
    if (!cls) return self;
    for (NSUInteger i = 0; i < sizeof(required) / sizeof(required[0]); i++) {
        if (![cls instancesRespondToSelector:required[i]]) return self;
    }
    self.client = [[(id)cls alloc] initWithClientName:@"NetCharge"];
    return self;
}

- (BOOL)isSupported {
    return self.client && [self.client isMCLSupported];
}

- (nullable NSDictionary<NSString *, NSNumber *> *)readStateAndReturnError:(NSError **)error {
    if (![self isSupported]) {
        if (error) *error = NCError(1, @"当前系统不支持系统充电上限");
        return nil;
    }
    NSError *failure = nil;
    NSUInteger enabled = [self.client isMCLCurrentlyEnabled:&failure];
    if (failure) {
        if (error) *error = failure;
        return nil;
    }
    unsigned char limit = [self.client getMCLLimitWithError:&failure];
    if (failure) {
        if (error) *error = failure;
        return nil;
    }
    return @{@"active": @(enabled != 0), @"limit": @(enabled ? limit : 100)};
}

- (BOOL)setLimit:(NSInteger)limit error:(NSError **)error {
    if (![self isSupported]) {
        if (error) *error = NCError(1, @"当前系统不支持系统充电上限");
        return NO;
    }
    if (limit < 80 || limit > 100) {
        if (error) *error = NCError(2, @"当前固件仅支持 80% 至 100% 的系统充电上限");
        return NO;
    }
    NSError *failure = nil;
    NSArray<NSNumber *> *available = [self.client availableChargeLimitsWithError:&failure];
    if (failure || ![available containsObject:@(limit)]) {
        if (error) *error = failure ?: NCError(3, @"当前系统不支持所选充电上限");
        return NO;
    }
    NSDictionary<NSString *, NSNumber *> *before = [self readStateAndReturnError:&failure];
    if (!before) {
        if (error) *error = failure;
        return NO;
    }
    BOOL alreadySet = limit == 100 ? !before[@"active"].boolValue :
        before[@"active"].boolValue && before[@"limit"].integerValue == limit;
    if (alreadySet) return YES;

    BOOL success;
    if (limit == 100) {
        success = [self.client disableMCL:&failure];
    } else {
        success = [self.client setMCLLimit:(unsigned char)limit error:&failure];
    }
    if (!success || failure) {
        if (error) *error = failure ?: NCError(4, @"系统拒绝设置充电上限");
        return NO;
    }
    NSDictionary<NSString *, NSNumber *> *after = [self readStateAndReturnError:&failure];
    if (!after) {
        if (error) *error = failure;
        return NO;
    }
    BOOL verified = limit == 100 ? !after[@"active"].boolValue :
        after[@"active"].boolValue && after[@"limit"].integerValue == limit;
    if (!verified && error) *error = NCError(5, @"系统充电上限读回值与请求值不一致");
    return verified;
}

@end
