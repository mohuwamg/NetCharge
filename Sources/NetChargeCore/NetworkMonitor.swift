import Darwin
import Foundation
import SystemConfiguration

public struct NetworkRates {
    public let interface: String
    public let downloadBytesPerSecond: Double
    public let uploadBytesPerSecond: Double

    public init(interface: String, downloadBytesPerSecond: Double, uploadBytesPerSecond: Double) {
        self.interface = interface
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
    }
}

public final class NetworkMonitor {
    private var previous: (interface: String, received: UInt64, sent: UInt64, uptime: TimeInterval)?

    public init() {}

    public func sample() -> NetworkRates? {
        guard let name = Self.primaryInterface(), let counters = Self.counters(for: name) else {
            previous = nil
            return nil
        }
        let now = ProcessInfo.processInfo.systemUptime
        defer { previous = (name, counters.received, counters.sent, now) }
        guard let prior = previous, prior.interface == name,
              counters.received >= prior.received, counters.sent >= prior.sent,
              now > prior.uptime else {
            return NetworkRates(interface: name, downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)
        }
        let elapsed = now - prior.uptime
        let download = Double(counters.received - prior.received) / elapsed
        let upload = Double(counters.sent - prior.sent) / elapsed
        // Discard one-off counter jumps during reconnects.
        let plausibleMaximum = 12_500_000_000.0 // 100 Gbit/s
        return NetworkRates(
            interface: name,
            downloadBytesPerSecond: download <= plausibleMaximum ? download : 0,
            uploadBytesPerSecond: upload <= plausibleMaximum ? upload : 0
        )
    }

    private static func primaryInterface() -> String? {
        if let state = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
           let name = state["PrimaryInterface"] as? String, !name.isEmpty {
            if !isVirtual(name) { return name }
            if let physical = serviceOrderedPhysicalInterface() { return physical }
        }
        return firstActivePhysicalInterface()
    }

    private static func isVirtual(_ name: String) -> Bool {
        ["utun", "ipsec", "ppp", "tun", "tap", "gif", "stf", "wg"].contains { name.hasPrefix($0) }
    }

    private static func serviceOrderedPhysicalInterface() -> String? {
        guard let setup = SCDynamicStoreCopyValue(nil, "Setup:/Network/Global/IPv4" as CFString) as? [String: Any],
              let order = setup["ServiceOrder"] as? [String] else { return nil }
        for service in order {
            let key = "State:/Network/Service/\(service)/IPv4"
            guard let state = SCDynamicStoreCopyValue(nil, key as CFString) as? [String: Any],
                  state["Router"] != nil,
                  let name = state["InterfaceName"] as? String,
                  !isVirtual(name) else { continue }
            return name
        }
        return nil
    }

    private static func firstActivePhysicalInterface() -> String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return nil }
        defer { freeifaddrs(addresses) }
        var node = addresses
        while let current = node {
            defer { node = current.pointee.ifa_next }
            let flags = Int32(current.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0,
                  flags & IFF_LOOPBACK == 0,
                  let address = current.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: current.pointee.ifa_name)
            if !isVirtual(name) { return name }
        }
        return nil
    }

    private static func counters(for name: String) -> (received: UInt64, sent: UInt64)? {
        let index = if_nametoindex(name)
        guard index != 0 else { return nil }
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, Int32(index)]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, u_int(mib.count), &buffer, &size, nil, 0) == 0 else { return nil }
        var offset = 0
        while offset + MemoryLayout<if_msghdr>.size <= size {
            let header: if_msghdr = buffer.withUnsafeBytes { source in
                source.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
            }
            let messageLength = Int(header.ifm_msglen)
            guard messageLength > 0, offset + messageLength <= size else { return nil }
            if Int32(header.ifm_type) == RTM_IFINFO2,
               offset + MemoryLayout<if_msghdr2>.size <= size {
                let detail: if_msghdr2 = buffer.withUnsafeBytes { source in
                    source.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                }
                if UInt32(detail.ifm_index) == index {
                    return (UInt64(detail.ifm_data.ifi_ibytes), UInt64(detail.ifm_data.ifi_obytes))
                }
            }
            offset += messageLength
        }
        return nil
    }
}

public enum SpeedFormat {
    public static func string(_ bytesPerSecond: Double) -> String {
        let value = max(0, bytesPerSecond)
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var scaled = value
        var unit = 0
        while scaled >= 1000 && unit < units.count - 1 {
            scaled /= 1000
            unit += 1
        }
        return String(format: scaled < 10 && unit > 0 ? "%.1f %@" : "%.0f %@", scaled, units[unit])
    }
}
