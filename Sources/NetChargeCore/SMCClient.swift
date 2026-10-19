import Foundation
import IOKit

public enum SMCError: LocalizedError {
    case unavailable(Int32)
    case missingKey(String)
    case invalidKey(String)
    case invalidSize(String, Int)
    case firmwareError(String, UInt8)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let code):
            if code == kIOReturnNotPrivileged {
                return "macOS 已拒绝 SMC 访问，且此设备没有可用的系统充电上限"
            }
            return "无法访问 AppleSMC（错误 \(code)）"
        case .missingKey(let key): return "当前固件没有可用的 SMC 键 \(key)"
        case .invalidKey(let key): return "无效的 SMC 键 \(key)"
        case .invalidSize(let key, let size): return "SMC 键 \(key) 的数据长度不符：\(size)"
        case .firmwareError(let key, let code): return "固件拒绝 SMC 键 \(key) 的操作（\(code)）"
        }
    }
}

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPowerLimit {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpu: UInt32 = 0
    var gpu: UInt32 = 0
    var memory: UInt32 = 0
}

private struct SMCKeyInfo {
    var size: UInt32 = 0
    var type: UInt32 = 0
    var attributes: UInt8 = 0
}

// Matches the AppleSMC user-client request layout. Only key info, read and
// write commands are used; the remaining fields preserve the ABI layout.
private struct SMCRequest {
    typealias Payload = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                         UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                         UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                         UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    var key: UInt32 = 0
    var version = SMCVersion()
    var powerLimit = SMCPowerLimit()
    var keyInfo = SMCKeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var command: UInt8 = 0
    var data32: UInt32 = 0
    var payload: Payload = (0, 0, 0, 0, 0, 0, 0, 0,
                            0, 0, 0, 0, 0, 0, 0, 0,
                            0, 0, 0, 0, 0, 0, 0, 0,
                            0, 0, 0, 0, 0, 0, 0, 0)
}

public final class SMCClient: SMCTransport {
    private let connection: io_connect_t

    public init() throws {
        guard let matching = IOServiceMatching("AppleSMC") else { throw SMCError.unavailable(-1) }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { throw SMCError.unavailable(-1) }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else { throw SMCError.unavailable(result) }
        self.connection = connection
    }

    deinit { IOServiceClose(connection) }

    public func read(_ key: String) throws -> [UInt8] {
        let keyCode = try Self.keyCode(key)
        let info = try keyInfo(key, code: keyCode)
        guard info.size > 0, info.size <= 32 else { throw SMCError.invalidSize(key, Int(info.size)) }
        var request = SMCRequest()
        request.key = keyCode
        request.keyInfo = info
        request.command = 5
        let response = try call(request, key: key)
        return withUnsafeBytes(of: response.payload) { Array($0.prefix(Int(info.size))) }
    }

    public func write(_ key: String, bytes: [UInt8]) throws {
        let keyCode = try Self.keyCode(key)
        let info = try keyInfo(key, code: keyCode)
        guard info.size > 0, info.size <= 32, bytes.count == Int(info.size) else {
            throw SMCError.invalidSize(key, bytes.count)
        }
        var request = SMCRequest()
        request.key = keyCode
        request.keyInfo = info
        request.command = 6
        withUnsafeMutableBytes(of: &request.payload) { destination in
            destination.copyBytes(from: bytes)
        }
        _ = try call(request, key: key)
    }

    private func keyInfo(_ key: String, code: UInt32) throws -> SMCKeyInfo {
        var request = SMCRequest()
        request.key = code
        request.command = 9
        let response = try call(request, key: key)
        guard response.keyInfo.size > 0 else { throw SMCError.missingKey(key) }
        return response.keyInfo
    }

    private func call(_ request: SMCRequest, key: String) throws -> SMCRequest {
        var input = request
        var output = SMCRequest()
        var size = MemoryLayout<SMCRequest>.stride
        let result = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<SMCRequest>.stride, &output, &size)
        guard result == kIOReturnSuccess else { throw SMCError.unavailable(result) }
        guard output.result == 0 else {
            if output.result == 0x84 { throw SMCError.missingKey(key) }
            throw SMCError.firmwareError(key, output.result)
        }
        return output
    }

    private static func keyCode(_ key: String) throws -> UInt32 {
        let bytes = Array(key.utf8)
        guard bytes.count == 4 else { throw SMCError.invalidKey(key) }
        return bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
