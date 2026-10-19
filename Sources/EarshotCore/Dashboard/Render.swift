import Foundation

/// Everything the dashboard shows, as plain values.
public struct ViewState {
    public var sessions: [Session]
    /// Terminal tab titles by TTY.
    public var titles: [String: String]
    public var selected: Int
    public var focusedTTY: String?
    public var playingId: String?
    public var listening: Bool
    public var mode: Config.Mode
    public var status: String
    public var now: Date

    public init(sessions: [Session], titles: [String: String], selected: Int, focusedTTY: String?,
                playingId: String?, listening: Bool, mode: Config.Mode, status: String, now: Date) {
        self.sessions = sessions
        self.titles = titles
        self.selected = selected
        self.focusedTTY = focusedTTY
        self.playingId = playingId
        self.listening = listening
        self.mode = mode
        self.status = status
        self.now = now
    }
}

/// Pure layout of the dashboard. The App adds color (inverse video on the selected row).
public enum Render {
    public static let footer = "↑↓ select  enter jump  p play  s mode  c copy  q quit"
    public static let emptyMessage = "No Claude sessions yet. Start claude in a Terminal tab."

    /// Index of the first session row in `lines`.
    public static let firstRow = 2

    public static func lines(_ s: ViewState, width: Int) -> [String] {
        let n = s.sessions.count
        var header = "Earshot  ·  \(n) \(n == 1 ? "session" : "sessions")  ·  mode: \(s.mode.rawValue)"
        if s.listening { header += "  ·  listening…" }
        var out = [header, ""]
        if s.sessions.isEmpty {
            out.append(emptyMessage)
        }
        for (i, session) in s.sessions.enumerated() {
            out.append(row(session, state: s, selected: i == s.selected))
        }
        out += ["", footer, s.status]
        return out.map { String($0.prefix(max(width, 0))) }
    }

    static func row(_ x: Session, state s: ViewState, selected: Bool) -> String {
        let sel = selected ? ">" : " "
        let mark = x.unread ? "*" : (x.tty != nil && x.tty == s.focusedTTY ? "@" : " ")
        let status = s.playingId == x.id ? "playing" : word(x.status)
        let title = x.tty.flatMap { s.titles[$0] }.map(cleanTitle) ?? ""
        let line = "\(sel) \(mark) \(pad(x.project, 16)) \(pad(status, 15)) \(leftPad(age(s.now.timeIntervalSince(x.changedAt)), 4))  \(title)"
        return line.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
    }

    static func word(_ status: SessionStatus) -> String {
        switch status {
        case .idle: "idle"
        case .working: "working"
        case .finished: "finished"
        case .waiting: "waiting on you"
        case .error: "error"
        }
    }

    /// Row index for the session the user had selected, after the list changed.
    /// Falls back to the old index (clamped) when that session is gone.
    public static func reselect(id: String?, fallback: Int, in sessions: [Session]) -> Int {
        if let id, let i = sessions.firstIndex(where: { $0.id == id }) { return i }
        return min(max(fallback, 0), max(sessions.count - 1, 0))
    }

    public static func age(_ seconds: TimeInterval) -> String {
        let s = max(Int(seconds), 0)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h"
    }

    /// Claude Code prefixes tab titles with a spinner glyph ("✳ ", "◐ ").
    public static func cleanTitle(_ title: String) -> String {
        guard let first = title.unicodeScalars.first, !CharacterSet.alphanumerics.contains(first),
              title.dropFirst().hasPrefix(" ") else { return title }
        return String(title.dropFirst(2))
    }

    private static func pad(_ s: String, _ n: Int) -> String {
        s.count >= n ? String(s.prefix(n)) : s + String(repeating: " ", count: n - s.count)
    }

    private static func leftPad(_ s: String, _ n: Int) -> String {
        s.count >= n ? s : String(repeating: " ", count: n - s.count) + s
    }
}
