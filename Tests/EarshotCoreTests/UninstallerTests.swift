import Foundation
import Testing
@testable import EarshotCore

private let fm = FileManager.default
private let now = Date(timeIntervalSince1970: 1_800_000_000)

/// A fake home with Earshot hooks next to someone else's, plus Earshot's files and the model cache.
private func populatedHome() throws -> URL {
    let home = tmpDir()
    let paths = Paths(home: home)
    let settings = Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]},"env":{"A":"1"}}"#.utf8)
    try fm.createDirectory(at: paths.claudeSettings.deletingLastPathComponent(), withIntermediateDirectories: true)
    try HookInstaller.install(settings: settings, binary: "/opt/bin/earshot").write(to: paths.claudeSettings)
    try fm.createDirectory(at: paths.supportDir, withIntermediateDirectories: true)
    try Data("{}\n".utf8).write(to: paths.eventLog)
    try fm.createDirectory(at: paths.configDir, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: paths.configFile)
    for dir in paths.modelCaches { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
    return home
}

@Test func uninstallRemovesHooksAndFilesButKeepsModelCache() throws {
    let home = try populatedHome()
    let paths = Paths(home: home)
    let before = try Data(contentsOf: paths.claudeSettings)

    let lines = try Uninstaller.run(home: home, now: now)

    let after = try Data(contentsOf: paths.claudeSettings)
    #expect(!HookInstaller.hasOurs(settings: after))
    let root = try JSONSerialization.jsonObject(with: after) as! NSDictionary
    #expect((root["env"] as? NSDictionary)?["A"] as? String == "1")
    #expect(String(decoding: after, as: UTF8.self).contains("say done"))
    let backup = paths.claudeSettings.path + HookInstaller.backupSuffix(for: now)
    #expect(try Data(contentsOf: URL(fileURLWithPath: backup)) == before)

    #expect(!fm.fileExists(atPath: paths.supportDir.path))
    #expect(!fm.fileExists(atPath: paths.configDir.path))
    for dir in paths.modelCaches { #expect(fm.fileExists(atPath: dir.path)) }

    let text = lines.joined(separator: "\n")
    #expect(text.contains("Removed Earshot hooks from \(paths.claudeSettings.path)"))
    #expect(text.contains(backup))
    #expect(text.contains("Deleted \(paths.supportDir.path)"))
    #expect(text.contains("Deleted \(paths.configDir.path)"))
    let rm = lines.first { $0.hasPrefix("To delete them anyway: rm -rf ") } ?? ""
    for dir in paths.modelCaches { #expect(rm.contains("'\(dir.path)'")) }
}

@Test func uninstallOnCleanHomeTouchesNothing() throws {
    let home = tmpDir()
    let paths = Paths(home: home)
    let lines = try Uninstaller.run(home: home, now: now)
    #expect(!fm.fileExists(atPath: paths.claudeSettings.path))
    #expect(try fm.contentsOfDirectory(atPath: home.path).isEmpty)
    #expect(lines.joined().contains("No Earshot hooks"))
}

@Test func uninstallLeavesSettingsWithoutOurHooksAlone() throws {
    let home = tmpDir()
    let paths = Paths(home: home)
    try fm.createDirectory(at: paths.claudeSettings.deletingLastPathComponent(), withIntermediateDirectories: true)
    let settings = Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#.utf8)
    try settings.write(to: paths.claudeSettings)

    _ = try Uninstaller.run(home: home, now: now)

    #expect(try Data(contentsOf: paths.claudeSettings) == settings)
    #expect(try fm.contentsOfDirectory(atPath: paths.claudeSettings.deletingLastPathComponent().path) == ["settings.json"])
}

@Test func hasOursDetectsAnyEarshotBinary() throws {
    #expect(!HookInstaller.hasOurs(settings: nil))
    #expect(HookInstaller.hasOurs(settings: try HookInstaller.install(settings: nil, binary: "/elsewhere/earshot")))
}

@Test func uninstallWritesThroughASymlinkedSettingsFile() throws {
    // Dotfile managers often symlink ~/.claude/settings.json; an atomic write would replace the link.
    let home = try populatedHome()
    let paths = Paths(home: home)
    let real = home.appendingPathComponent("dotfiles/claude-settings.json")
    try fm.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fm.moveItem(at: paths.claudeSettings, to: real)
    try fm.createSymbolicLink(at: paths.claudeSettings, withDestinationURL: real)

    _ = try Uninstaller.run(home: home, now: now)

    #expect(try fm.destinationOfSymbolicLink(atPath: paths.claudeSettings.path) == real.path)
    #expect(!HookInstaller.hasOurs(settings: try Data(contentsOf: real)))
}

@Test func writeSettingsCreatesAPlainFileWhenThereIsNone() throws {
    let url = tmpDir().appendingPathComponent("settings.json")
    try HookInstaller.writeSettings(Data("{}".utf8), to: url)
    #expect(try Data(contentsOf: url) == Data("{}".utf8))
}

@Test func modelCachesAreWhereFluidAudioPutsThem() {
    let home = URL(fileURLWithPath: "/Users/someone")
    #expect(Paths(home: home).modelCaches.map(\.path) == [
        "/Users/someone/Library/Application Support/FluidAudio/Models", // Parakeet (speech recognition)
        "/Users/someone/.cache/fluidaudio", // Kokoro (voice)
    ])
}
