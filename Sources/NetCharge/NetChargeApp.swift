import AppKit
import Foundation
import NetChargeCore
import SwiftUI

private struct HelperReport: Decodable {
    let state: ChargeState
    let updatedAt: Date
}

@MainActor
final class DashboardModel: ObservableObject {
    @Published var rates = NetworkRates(interface: "—", downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)
    @Published var battery: BatteryReading?
    @Published var chargeState: ChargeState?
    @Published var selectedLimit = 80.0
    @Published var busy = false
    @Published var message: String?

    private let network = NetworkMonitor()
    private var ticks = 0
    private var timer: Timer?
    var onRatesChanged: ((NetworkRates) -> Void)?
    private let statusPath = "/Library/Application Support/NetCharge/status.json"
    private let installedHelper = "/Library/PrivilegedHelperTools/com.netcharge.helper"

    var helperInstalled: Bool { FileManager.default.isExecutableFile(atPath: installedHelper) }

    init() {
        refresh()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        if let sample = network.sample() {
            rates = sample
            onRatesChanged?(sample)
        }
        ticks += 1
        guard ticks == 1 || ticks.isMultiple(of: 5) else { return }
        battery = BatteryMonitor.read()
        if let data = try? Data(contentsOf: URL(fileURLWithPath: statusPath)),
           let report = try? JSONDecoder().decode(HelperReport.self, from: data),
           Date().timeIntervalSince(report.updatedAt) < 180 {
            chargeState = report.state
            if !busy, let upper = report.state.upperLimit, report.state.active {
                selectedLimit = Double(upper)
            }
        } else {
            chargeState = nil
        }
    }

    func installHelper() {
        guard let script = Bundle.main.resourceURL?.appendingPathComponent("install-helper.sh"),
              FileManager.default.fileExists(atPath: script.path) else {
            message = "安装脚本未包含在应用中，请使用 scripts/build-app.sh 构建。"
            return
        }
        runPrivileged("/bin/bash \(Self.shellQuote(script.path))")
    }

    func applyLimit() {
        let limit = Int(selectedLimit)
        guard (10...100).contains(limit), helperInstalled else {
            message = "请先安装充电控制服务。"
            return
        }
        runPrivileged("\(installedHelper) set-limit \(limit)")
    }

    private func runPrivileged(_ command: String) {
        busy = true
        message = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.executeAppleScript(command)
            }.value
            busy = false
            message = result
            ticks = 0
            refresh()
        }
    }

    nonisolated private static func executeAppleScript(_ command: String) -> String {
        let source = "do shell script \(appleScriptQuote(command)) with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let errors = Pipe()
        process.standardError = errors
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 { return "操作完成" }
            let output = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch { return error.localizedDescription }
    }

    nonisolated private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated private static func appleScriptQuote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

private final class SpeedStatusView: NSView {
    private var upload = "0 B/s"
    private var download = "0 B/s"
    private let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

    var requiredWidth: CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textWidth = max(
            (upload as NSString).size(withAttributes: attributes).width,
            (download as NSString).size(withAttributes: attributes).width
        )
        return max(76, ceil(textWidth) + 22)
    }

    func update(_ rates: NetworkRates) {
        upload = SpeedFormat.string(rates.uploadBytesPerSecond)
        download = SpeedFormat.string(rates.downloadBytesPerSecond)
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let lowerY = (bounds.height - 24) / 2 + 1
        (upload as NSString).draw(at: NSPoint(x: 17, y: lowerY + 11), withAttributes: attributes)
        (download as NSString).draw(at: NSPoint(x: 17, y: lowerY), withAttributes: attributes)

        NSColor(red: 1, green: 0.28, blue: 0.26, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 5, y: lowerY + 15, width: 7, height: 7)).fill()
        NSColor(red: 0.14, green: 0.60, blue: 1, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 5, y: lowerY + 4, width: 7, height: 7)).fill()
    }
}

@MainActor
private final class NetChargeDelegate: NSObject, NSApplicationDelegate {
    private let model = DashboardModel()
    private let popover = NSPopover()
    private let statusView = SpeedStatusView()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: statusView.requiredWidth)
        guard let button = item.button else { return }
        statusItem = item
        statusView.frame = button.bounds
        statusView.autoresizingMask = [.width, .height]
        button.addSubview(statusView)
        button.target = self
        button.action = #selector(togglePopover)
        button.setAccessibilityLabel("上传 0 B/s，下载 0 B/s")

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: DashboardView(model: model))
        popover.contentSize = NSSize(width: 368, height: 360)

        model.onRatesChanged = { [weak self] rates in
            guard let self, let item = self.statusItem else { return }
            self.statusView.update(rates)
            item.length = self.statusView.requiredWidth
            item.button?.setAccessibilityLabel(
                "上传 \(SpeedFormat.string(rates.uploadBytesPerSecond))，下载 \(SpeedFormat.string(rates.downloadBytesPerSecond))"
            )
        }
        statusView.update(model.rates)
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

private struct DashboardView: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("网络 · \(model.rates.interface)").font(.headline)
                HStack {
                    Label("下载 \(SpeedFormat.string(model.rates.downloadBytesPerSecond))", systemImage: "arrow.down")
                    Spacer()
                    Label("上传 \(SpeedFormat.string(model.rates.uploadBytesPerSecond))", systemImage: "arrow.up")
                }
                Divider()
                Text("电池").font(.headline)
                if let battery = model.battery {
                    Text("电量 \(battery.percent)% · \(battery.isCharging ? "充电中" : battery.isPluggedIn ? "已接电源" : "使用电池")")
                } else {
                    Text("未读取到电池").foregroundStyle(.secondary)
                }
                if let state = model.chargeState {
                    Text(state.active ? "充电上限 \(state.upperLimit ?? 0)%" : "充电上限已关闭")
                } else {
                    Text("控制服务未运行或状态不可用").foregroundStyle(.secondary)
                }
                if model.helperInstalled {
                    HStack {
                        Slider(value: $model.selectedLimit, in: 10...100, step: 5)
                        Text("\(Int(model.selectedLimit))%")
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }
                    Button(model.busy ? "正在处理…" : "设置充电上限") { model.applyLimit() }
                        .disabled(model.busy || model.chargeState == nil)
                    Text("100% 表示关闭上限。修改时需要管理员授权。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button(model.busy ? "正在安装…" : "安装充电控制服务") { model.installHelper() }
                        .disabled(model.busy)
                    Text("安装会停用现有 batt 服务并接管当前上限。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let message = model.message, !message.isEmpty {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Button("退出 NetCharge") { NSApplication.shared.terminate(nil) }
            }
            .padding(14)
            .frame(width: 340)
            .onAppear { model.refresh() }
    }
}

@main
struct NetChargeApp: App {
    @NSApplicationDelegateAdaptor(NetChargeDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
