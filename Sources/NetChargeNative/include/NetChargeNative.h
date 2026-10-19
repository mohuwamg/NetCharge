#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NCNativeChargeClient : NSObject
- (BOOL)isSupported;
- (nullable NSDictionary<NSString *, NSNumber *> *)readStateAndReturnError:(NSError **)error;
- (BOOL)setLimit:(NSInteger)limit error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
