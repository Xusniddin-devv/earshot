import Foundation

/// Where Earshot keeps its files.
public struct Paths: Sendable {
    public var supportDir: URL
    public var eventLog: URL
    public var configDir: URL
    public var configFile: URL
    public var claudeSettings: URL
    /// FluidAudio's model caches: Parakeet (speech recognition) and Kokoro (voice) live in
    /// different places. Shared with other FluidAudio apps, so Earshot never deletes them.
    public var modelCaches: [URL]

    public init(home: URL) {
        supportDir = home.appendingPathComponent("Library/Application Support/Earshot")
        eventLog = supportDir.appendingPathComponent("events.jsonl")
        configDir = home.appendingPathComponent(".config/earshot")
        configFile = configDir.appendingPathComponent("config.json")
        claudeSettings = home.appendingPathComponent(".claude/settings.json")
        modelCaches = [home.appendingPathComponent("Library/Application Support/FluidAudio/Models"),
                       home.appendingPathComponent(".cache/fluidaudio")]
    }

    public static var live: Paths {
        Paths(home: FileManager.default.homeDirectoryForCurrentUser)
    }
}
