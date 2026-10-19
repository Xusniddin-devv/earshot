import Foundation

/// User settings, stored in `~/.config/earshot/config.json`. Missing keys take defaults.
public struct Config: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable { case whole, summary }
    /// `auto`: Apple Terminal, plus iTerm2 while it is running.
    public enum Terminal: String, Codable, Sendable { case auto, terminal, iterm }
    public enum Hotkey: String, Codable, Sendable {
        case rightOption, rightCommand, rightControl, shift, control

        public var label: String {
            switch self {
            case .rightOption: "Right Option"
            case .rightCommand: "Right Command"
            case .rightControl: "Right Control"
            case .shift: "Shift (on its own)"
            case .control: "Ctrl (on its own)"
            }
        }
    }

    public var mode: Mode = .whole
    public var voice = "af_heart"
    public var speed = 1.0
    public var finishSound = true
    public var autoSend = true
    public var hotkey: Hotkey = .rightOption
    /// When set, this ordinary key (macOS key code) is the talk key instead of `hotkey`.
    public var hotkeyKeycode: Int?
    public var terminal: Terminal = .auto

    public var hotkeyLabel: String {
        hotkeyKeycode.map { Config.fKeys[$0] ?? "the talk key (code \($0))" } ?? hotkey.label
    }

    static let fKeys = [122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
                        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15"]

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        mode = (try? c.decodeIfPresent(Mode.self, forKey: .mode)) ?? d.mode
        voice = (try? c.decodeIfPresent(String.self, forKey: .voice)) ?? d.voice
        speed = (try? c.decodeIfPresent(Double.self, forKey: .speed)) ?? d.speed
        finishSound = (try? c.decodeIfPresent(Bool.self, forKey: .finishSound)) ?? d.finishSound
        autoSend = (try? c.decodeIfPresent(Bool.self, forKey: .autoSend)) ?? d.autoSend
        hotkey = (try? c.decodeIfPresent(Hotkey.self, forKey: .hotkey)) ?? d.hotkey
        hotkeyKeycode = try? c.decodeIfPresent(Int.self, forKey: .hotkeyKeycode)
        terminal = (try? c.decodeIfPresent(Terminal.self, forKey: .terminal)) ?? d.terminal
    }

    public static func load(_ url: URL) -> Config {
        guard let data = try? Data(contentsOf: url),
              let c = try? JSONDecoder().decode(Config.self, from: data) else { return Config() }
        return c
    }

    public func save(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(self).write(to: url, options: .atomic)
    }
}
