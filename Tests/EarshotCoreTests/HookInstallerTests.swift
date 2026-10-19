import Foundation
import Testing
@testable import EarshotCore

private let bin = "/Users/x/.local/bin/earshot"

private func json(_ data: Data) -> NSDictionary {
    try! JSONSerialization.jsonObject(with: data) as! NSDictionary
}

private func ourCommands(_ data: Data, _ event: String) -> [String] {
    let hooks = json(data)["hooks"] as? [String: Any] ?? [:]
    let groups = hooks[event] as? [[String: Any]] ?? []
    return groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
        .filter { $0.hasSuffix("earshot hook") }
}

private let fixture = Data(#"""
{"env":{"A":"1"},"permissions":{"allow":["Bash(ls)"]},"statusLine":{"type":"command","command":"x"},
 "enabledPlugins":{"p@m":true},
 "hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}
"""#.utf8)

@Test func installIntoMissingFile() throws {
    let out = try HookInstaller.install(settings: nil, binary: bin)
    for e in HookInstaller.events { #expect(ourCommands(out, e) == ["\(bin) hook"]) }
    let stop = ((json(out)["hooks"] as! [String: Any])["Stop"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]]
    #expect(stop[0]["async"] as? Bool == true && stop[0]["timeout"] as? Int == 5 && stop[0]["type"] as? String == "command")
}

@Test func installIsIdempotent() throws {
    let once = try HookInstaller.install(settings: fixture, binary: bin)
    let twice = try HookInstaller.install(settings: once, binary: bin)
    #expect(json(once) == json(twice))
}

@Test func installUpdatesBinaryPath() throws {
    let old = try HookInstaller.install(settings: fixture, binary: "/old/earshot")
    let new = try HookInstaller.install(settings: old, binary: bin)
    for e in HookInstaller.events { #expect(ourCommands(new, e) == ["\(bin) hook"]) }
}

@Test func preservesForeignHooksAndKeys() throws {
    let installed = try HookInstaller.install(settings: fixture, binary: bin)
    let d = json(installed)
    for key in ["env", "permissions", "statusLine", "enabledPlugins"] {
        #expect(d[key] as? NSDictionary == json(fixture)[key] as? NSDictionary)
    }
    let stop = (d["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
    #expect((stop[0]["hooks"] as! [[String: Any]])[0]["command"] as? String == "say done")
    let removed = try HookInstaller.uninstall(settings: installed)
    #expect(json(removed) == json(fixture))
}

@Test func uninstallRemovesOnlyOurs() throws {
    let installed = try HookInstaller.install(settings: nil, binary: bin)
    let removed = try HookInstaller.uninstall(settings: installed)
    #expect(json(removed)["hooks"] == nil)
    #expect(HookInstaller.isInstalled(settings: removed, binary: bin) == false)
    #expect(HookInstaller.isInstalled(settings: installed, binary: bin) == true)
    #expect(HookInstaller.isInstalled(settings: installed, binary: "/other/earshot") == false)
}

@Test func rejectsInvalidJSON() {
    #expect(throws: (any Error).self) { try HookInstaller.install(settings: Data("{nope".utf8), binary: bin) }
    #expect(throws: (any Error).self) { try HookInstaller.uninstall(settings: Data("[1]".utf8)) }
}

@Test func backupSuffixIsLocaleIndependent() {
    let d = Date(timeIntervalSince1970: 1_792_449_000) // 2026-10-19 22:30:00 UTC
    #expect(HookInstaller.backupSuffix(for: d, timeZone: TimeZone(identifier: "UTC")!) == ".earshot-backup-20261019-223000")
}

@Test func installsStatusEvents() throws {
    let out = try HookInstaller.install(settings: nil, binary: bin)
    for e in ["PermissionRequest", "PostToolUse", "StopFailure"] {
        #expect(ourCommands(out, e) == ["\(bin) hook"])
        let handler = ((json(out)["hooks"] as! [String: Any])[e] as! [[String: Any]])[0]["hooks"] as! [[String: Any]]
        #expect(handler[0]["async"] as? Bool == true)
    }
}

/// A v1 install had only these five events.
private let v1Events = ["SessionStart", "UserPromptSubmit", "Stop", "Notification", "SessionEnd"]

private func v1Install(_ binary: String) -> Data {
    var hooks: [String: Any] = ["Stop": [["hooks": [["type": "command", "command": "say done"]]]]]
    for e in v1Events {
        var groups = hooks[e] as? [[String: Any]] ?? []
        groups.append(["hooks": [["type": "command", "command": "\(binary) hook", "async": true, "timeout": 5]]])
        hooks[e] = groups
    }
    return try! JSONSerialization.data(withJSONObject: ["hooks": hooks])
}

@Test func reinstallUpgradesAnOldInstall() throws {
    let old = v1Install(bin)
    #expect(HookInstaller.status(settings: old, binary: bin) == .outdated(missing: ["StopFailure", "PermissionRequest", "PostToolUse"]))
    let new = try HookInstaller.install(settings: old, binary: bin)
    for e in HookInstaller.events { #expect(ourCommands(new, e) == ["\(bin) hook"]) }
    #expect(ourCommands(new, "Stop").count == 1)
    let stop = (json(new)["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
    #expect((stop[0]["hooks"] as! [[String: Any]])[0]["command"] as? String == "say done")
    #expect(HookInstaller.status(settings: new, binary: bin) == .installed)
}

@Test func hookStatus() throws {
    #expect(HookInstaller.status(settings: nil, binary: bin) == .missing)
    #expect(HookInstaller.status(settings: fixture, binary: bin) == .missing)
    #expect(HookInstaller.status(settings: Data("{nope".utf8), binary: bin) == .missing)
    let installed = try HookInstaller.install(settings: fixture, binary: bin)
    #expect(HookInstaller.status(settings: installed, binary: bin) == .installed)
    // Installed from another binary path: re-running install-hooks fixes it, same as missing.
    #expect(HookInstaller.status(settings: installed, binary: "/other/earshot") == .missing)
    #expect(HookInstaller.status(settings: v1Install(bin), binary: bin).fix == "run: earshot install-hooks")
}
