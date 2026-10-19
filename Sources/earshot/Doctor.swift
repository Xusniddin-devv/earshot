import Foundation
import EarshotCore
import EarshotMac

/// `earshot doctor`: one line per requirement, with the fix for anything missing.
func runDoctor() {
    var ok = true
    let host = HostApp.name(env: ProcessInfo.processInfo.environment)
    func line(_ pass: Bool, _ name: String, _ fix: String) {
        ok = ok && pass
        print(pass ? "  ok    \(name)" : "  FIX   \(name) — \(fix)")
    }

    let settings = try? Data(contentsOf: claudeSettings)
    let hooks = HookInstaller.status(settings: settings, binary: binaryPath)
    switch hooks {
    case .installed, .missing:
        line(hooks == .installed, "Claude Code hooks", hooks.fix)
    case .outdated(let missing):
        line(false, "Claude Code hooks (outdated, missing \(missing.joined(separator: ", ")))", hooks.fix)
    }

    let choice = Config.load(Paths.live.configFile).terminal
    // Only when running (or chosen explicitly): asking Terminal anything over AppleScript would launch it.
    if choice == .terminal || (choice == .auto && AppleTerminalAdapter.isRunning) {
        let terminal = AppleTerminalAdapter()
        _ = terminal.tabs()
        line(terminal.lastError == nil, "Automation (\(host) → Terminal)",
             "System Settings › Privacy & Security › Automation: under \(host), allow Terminal (\(terminal.lastError ?? ""))")
    }
    // Only when running: asking iTerm2 anything over AppleScript would launch it.
    if choice != .terminal, ITermAdapter.isRunning {
        let iterm = ITermAdapter()
        _ = iterm.tabs()
        line(iterm.lastError == nil, "Automation (\(host) → iTerm2, experimental)",
             "System Settings › Privacy & Security › Automation: under \(host), allow iTerm2 (\(iterm.lastError ?? ""))")
    }
    line(Permissions.accessibility, "Accessibility (typing into tabs)",
         "System Settings › Privacy & Security › Accessibility: turn on \(host)")
    line(Permissions.inputMonitoring, "Input Monitoring (push-to-talk key)",
         "System Settings › Privacy & Security › Input Monitoring: turn on \(host)")
    line(Permissions.microphone == .authorized, "Microphone",
         "System Settings › Privacy & Security › Microphone: turn on \(host)")

    print(ok ? "All good." : "Fix the lines marked FIX, then restart \(host).")
}
