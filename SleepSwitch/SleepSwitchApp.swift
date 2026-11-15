import AppKit
import SwiftUI

private let appName = "CoffeeRefill"

@main
struct SleepSwitchApp: App {
    @State private var control = SleepControl()

    var body: some Scene {
        MenuBarExtra {
            SleepPanel(control: control)
        } label: {
            Label(appName, systemImage: control.sleepDisabled == true ? "bolt.fill" : "moon.zzz")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
@Observable
private final class SleepControl {
    private(set) var sleepDisabled: Bool?
    private(set) var isChanging = false
    private(set) var message: String?
    private(set) var displayMessage: String?
    @ObservationIgnored private var lidMonitor: Task<Void, Never>?

    init() {
        refresh()
    }

    var statusText: String {
        if isChanging { return "正在应用设置…" }
        switch sleepDisabled {
        case true?: return "已开启 · 全局禁睡"
        case false?: return "已关闭 · 正常睡眠"
        case nil: return "无法读取系统状态"
        }
    }

    func refresh() {
        guard !isChanging else { return }
        updateSleepState(PowerManagement.sleepDisabled())
    }

    private func updateSleepState(_ disabled: Bool?) {
        sleepDisabled = disabled
        if disabled == true {
            startLidMonitor()
        } else {
            lidMonitor?.cancel()
            lidMonitor = nil
            displayMessage = nil
        }
    }

    private func startLidMonitor() {
        guard lidMonitor == nil else { return }
        lidMonitor = Task { [weak self] in
            var lastLidClosed: Bool?

            while !Task.isCancelled {
                guard let self else { return }
                let state = PowerManagement.lidMonitorState()
                if state.sleepDisabled == false {
                    updateSleepState(false)
                    return
                }

                if let closed = state.lidClosed, closed != lastLidClosed {
                    let needsDisplayCommand = closed || lastLidClosed == true
                    lastLidClosed = closed
                    if needsDisplayCommand {
                        await applyLidState(closed)
                    }
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func applyLidState(_ closed: Bool) async {
        guard !Task.isCancelled, PowerManagement.sleepDisabled() == true else { return }
        displayMessage = nil
        do {
            try await PowerManagement.setDisplayAwake(!closed)
        } catch {
            guard !Task.isCancelled else { return }
            let message = closed ? "合盖熄屏失败" : "开盖唤醒显示器失败"
            displayMessage = "\(message)。\n\(error.localizedDescription)"
        }
    }

    func setSleepDisabled(_ disabled: Bool, quitWhenDone: Bool = false) {
        guard !isChanging else { return }
        let wasDisabled = sleepDisabled == true
        refresh()
        guard let sleepDisabled else {
            if quitWhenDone, !wasDisabled { NSApp.terminate(nil) }
            return
        }
        if sleepDisabled == disabled {
            if quitWhenDone { NSApp.terminate(nil) }
            return
        }

        isChanging = true
        message = nil
        Task {
            defer {
                isChanging = false
                refresh()
            }

            do {
                try await PowerManagement.setSleepDisabled(disabled)
                if quitWhenDone { NSApp.terminate(nil) }
            } catch PowerManagement.ChangeError.cancelled {
                message = "已取消管理员授权。"
            } catch PowerManagement.ChangeError.stateMismatch {
                message = "系统未确认更改，请查看当前状态后重试。"
            } catch PowerManagement.ChangeError.authorizationFailed(let detail) {
                message = detail.isEmpty ? "无法执行电源设置命令。" : "无法执行电源设置命令。\n\(detail)"
            } catch {
                message = "无法执行电源设置命令。\n\(error.localizedDescription)"
            }
        }
    }
}

private struct SleepPanel: View {
    let control: SleepControl

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(appName, systemImage: "laptopcomputer")
                .font(.headline)

            Toggle(
                isOn: Binding(
                    get: { control.sleepDisabled == true },
                    set: { control.setSleepDisabled($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("全局禁睡")
                        .font(.headline)
                    Text(control.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 38, alignment: .leading)
            }
            .toggleStyle(.switch)
            .controlSize(.large)
            .disabled(control.isChanging || control.sleepDisabled == nil)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

            if let message = control.message ?? control.displayMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            Text("开启后，合盖熄屏，开盖亮屏。全局禁睡也会影响主动睡眠。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Spacer()
                Button(control.sleepDisabled == true ? "关闭并退出" : "退出应用") {
                    control.setSleepDisabled(false, quitWhenDone: true)
                }
                .disabled(control.isChanging)
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { control.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            control.refresh()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            control.refresh()
        }
    }
}
