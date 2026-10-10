import Foundation
import IOKit.ps

public struct BatteryReading {
    public let percent: Int
    public let isCharging: Bool
    public let isPluggedIn: Bool
}

public enum BatteryMonitor {
    public static func read() -> BatteryReading? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in sources {
            guard let values = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let current = values[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = values[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0 else { continue }
            let percent = Int((Double(current) / Double(maximum) * 100).rounded())
            let charging = values[kIOPSIsChargingKey] as? Bool ?? false
            let state = values[kIOPSPowerSourceStateKey] as? String
            return BatteryReading(percent: percent, isCharging: charging, isPluggedIn: state == kIOPSACPowerValue)
        }
        return nil
    }
}
