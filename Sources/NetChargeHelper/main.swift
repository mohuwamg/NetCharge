import Darwin
import Foundation
import NetChargeCore

private let supportDirectory = "/Library/Application Support/NetCharge"
private let configPath = "\(supportDirectory)/config.json"
private let statusPath = "\(supportDirectory)/status.json"
private let lockPath = "\(supportDirectory)/control.lock"

private struct Configuration: Codable {
    let upperLimit: Int
}

private struct Report: Codable {
    let state: ChargeState
    let updatedAt: Date
}

private func prepareDirectory() throws {
    try FileManager.default.createDirectory(
        atPath: supportDirectory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o755]
    )
}

private func withExclusiveLock<T>(_ body: () throws -> T) throws -> T {
    try prepareDirectory()
    let descriptor = open(lockPath, O_CREAT | O_RDWR, 0o600)
    guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    defer { flock(descriptor, LOCK_UN) }
    return try body()
}

private func readConfiguration() throws -> Configuration? {
    guard FileManager.default.fileExists(atPath: configPath) else { return nil }
    return try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: URL(fileURLWithPath: configPath)))
}

private func writeJSON<T: Encodable>(_ value: T, path: String) throws {
    let data = try JSONEncoder().encode(value)
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    guard chmod(path, 0o644) == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}

private func controller() throws -> any ChargeControlling {
    do {
        let service = ChargeController(smc: try SMCClient())
        _ = try service.readState()
        return service
    } catch {
        if let native = NativeChargeController() { return native }
        throw error
    }
}

private func recordFailure(_ error: Error) {
    let current = try? controller().readState()
    let state = ChargeState(
        supported: current?.supported ?? false,
        active: current?.active ?? false,
        lowerLimit: current?.lowerLimit,
        upperLimit: current?.upperLimit,
        error: error.localizedDescription,
        backend: current?.backend
    )
    try? writeJSON(Report(state: state, updatedAt: Date()), path: statusPath)
}

private func probe() throws {
    let report = Report(state: try controller().readState(), updatedAt: Date())
    let data = try JSONEncoder().encode(report)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

private func setLimit(_ value: Int) throws {
    guard geteuid() == 0 else { throw NSError(domain: "NetCharge", code: 1, userInfo: [NSLocalizedDescriptionKey: "设置充电上限需要管理员授权"]) }
    guard (10...100).contains(value) else { throw ChargeError.invalidLimit }
    try withExclusiveLock {
        do {
            let service = try controller()
            let state = try service.setLimit(value)
            try writeJSON(Configuration(upperLimit: value), path: configPath)
            try writeJSON(Report(state: state, updatedAt: Date()), path: statusPath)
        } catch {
            recordFailure(error)
            throw error
        }
    }
}

private func adoptCurrentLimit() throws {
    guard geteuid() == 0 else { throw NSError(domain: "NetCharge", code: 1, userInfo: [NSLocalizedDescriptionKey: "接管充电设置需要管理员权限"]) }
    try withExclusiveLock {
        guard !FileManager.default.fileExists(atPath: configPath) else { return }
        let state = try controller().readState()
        let limit = state.active ? (state.upperLimit ?? 100) : 100
        guard (10...100).contains(limit) else { throw ChargeError.invalidLimit }
        try writeJSON(Configuration(upperLimit: limit), path: configPath)
        try writeJSON(Report(state: state, updatedAt: Date()), path: statusPath)
    }
}

private func maintainOnce() throws {
    try withExclusiveLock {
        do {
            let service = try controller()
            let state: ChargeState
            if let configuration = try readConfiguration() {
                state = try service.setLimit(configuration.upperLimit)
            } else {
                state = try service.readState()
            }
            try writeJSON(Report(state: state, updatedAt: Date()), path: statusPath)
        } catch {
            recordFailure(error)
            throw error
        }
    }
}

private func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    switch args.first {
    case "probe":
        try probe()
    case "set-limit":
        guard args.count == 2, let value = Int(args[1]) else { throw ChargeError.invalidLimit }
        try setLimit(value)
    case "adopt-current":
        try adoptCurrentLimit()
    case "apply-config":
        guard geteuid() == 0 else { throw NSError(domain: "NetCharge", code: 1, userInfo: [NSLocalizedDescriptionKey: "应用充电设置需要管理员权限"]) }
        try maintainOnce()
    case "maintain":
        guard geteuid() == 0 else { throw NSError(domain: "NetCharge", code: 1, userInfo: [NSLocalizedDescriptionKey: "维护服务需要管理员权限"]) }
        while true {
            do { try maintainOnce() }
            catch { NSLog("NetCharge: %@", error.localizedDescription) }
            sleep(60)
        }
    default:
        FileHandle.standardError.write(Data("用法: netcharge-helper probe | set-limit <10...100> | maintain\n".utf8))
        exit(2)
    }
}

do { try run() }
catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
