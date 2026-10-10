import Foundation

public protocol SMCTransport {
    func read(_ key: String) throws -> [UInt8]
    func write(_ key: String, bytes: [UInt8]) throws
}

public struct ChargeState: Codable, Equatable {
    public let supported: Bool
    public let active: Bool
    public let lowerLimit: Int?
    public let upperLimit: Int?
    public let error: String?

    public init(supported: Bool, active: Bool, lowerLimit: Int?, upperLimit: Int?, error: String? = nil) {
        self.supported = supported
        self.active = active
        self.lowerLimit = lowerLimit
        self.upperLimit = upperLimit
        self.error = error
    }
}

public enum ChargeError: LocalizedError {
    case unsupported
    case invalidLimit
    case invalidData(String)
    case verificationFailed

    public var errorDescription: String? {
        switch self {
        case .unsupported: return "当前固件不支持此充电上限控制方式"
        case .invalidLimit: return "上限必须在 10% 至 100% 之间"
        case .invalidData(let key): return "SMC 键 \(key) 返回的数据无效"
        case .verificationFailed: return "写入后读回的上限与请求值不一致"
        }
    }
}

/// The firmware-managed keys are available on some Apple Silicon MacBooks.
/// The values are probed at runtime; a matching model number alone is insufficient.
public final class ChargeController {
    private let smc: SMCTransport
    private let activation = "bfF0"
    private let upper = "bfD0"
    private let lower = "bfE0"

    public init(smc: SMCTransport) { self.smc = smc }

    public func readState() throws -> ChargeState {
        let enabled = try smc.read(activation)
        let upperBytes = try smc.read(upper)
        let lowerBytes = try smc.read(lower)
        guard enabled.count == 1 else { throw ChargeError.invalidData(activation) }
        guard upperBytes.count == 4 else { throw ChargeError.invalidData(upper) }
        guard lowerBytes.count == 4 else { throw ChargeError.invalidData(lower) }
        let upperValue = Self.decodePercent(upperBytes)
        let lowerValue = Self.decodePercent(lowerBytes)
        guard (enabled[0] == 0 || enabled[0] == 2),
              upperValue <= 100, lowerValue <= 100,
              (enabled[0] == 0 || lowerValue < upperValue) else {
            throw ChargeError.invalidData("bfF0/bfD0/bfE0")
        }
        return ChargeState(
            supported: true,
            active: enabled[0] == 2,
            lowerLimit: Int(lowerValue),
            upperLimit: Int(upperValue)
        )
    }

    @discardableResult
    public func setLimit(_ limit: Int) throws -> ChargeState {
        guard (10...100).contains(limit) else { throw ChargeError.invalidLimit }
        let previous = try readState()
        if limit == 100 {
            if previous.active { try smc.write(activation, bytes: [0]) }
        } else {
            let lowerLimit = max(0, limit - 2)
            if !previous.active || previous.upperLimit != limit || previous.lowerLimit != lowerLimit {
                // Firmware requires deactivation before changing either bound.
                do {
                    try smc.write(activation, bytes: [0])
                    try smc.write(upper, bytes: Self.encodePercent(limit))
                    try smc.write(lower, bytes: Self.encodePercent(lowerLimit))
                    try smc.write(activation, bytes: [2])
                } catch {
                    // Keep the limit inactive after a partial update. Never report success.
                    try? smc.write(activation, bytes: [0])
                    throw error
                }
            }
        }
        let current = try readState()
        guard (limit == 100 && !current.active) ||
              (current.active && current.upperLimit == limit && current.lowerLimit == max(0, limit - 2)) else {
            throw ChargeError.verificationFailed
        }
        return current
    }

    private static func decodePercent(_ bytes: [UInt8]) -> UInt32 {
        UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
    }

    private static func encodePercent(_ value: Int) -> [UInt8] {
        let value = UInt32(value)
        return [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8),
                UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 24)]
    }
}
