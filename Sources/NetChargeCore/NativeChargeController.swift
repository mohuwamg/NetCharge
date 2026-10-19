import Foundation
import NetChargeNative

/// Uses the system charge limit when firmware blocks direct SMC access.
public final class NativeChargeController: ChargeControlling {
    private let client: NCNativeChargeClient

    public init?() {
        let client = NCNativeChargeClient()
        guard client.isSupported() else { return nil }
        self.client = client
    }

    public func readState() throws -> ChargeState {
        let values = try client.readState()
        guard let active = values["active"]?.boolValue,
              let limit = values["limit"]?.intValue else {
            throw ChargeError.invalidData("系统充电上限")
        }
        return ChargeState(
            supported: true,
            active: active,
            lowerLimit: nil,
            upperLimit: limit,
            backend: .native
        )
    }

    @discardableResult
    public func setLimit(_ limit: Int) throws -> ChargeState {
        try client.setLimit(limit)
        return try readState()
    }
}
