import Foundation

/// One Terminal tab, identified by its TTY.
public struct TabRef: Equatable, Sendable {
    public let window: Int
    public let tab: Int
    public let tty: String
    public let title: String

    public init(window: Int, tab: Int, tty: String, title: String) {
        self.window = window
        self.tab = tab
        self.tty = tty
        self.title = title
    }
}

public enum TerminalParse {
    /// Parses `window<TAB>tab<TAB>tty<TAB>title` lines from the tab-listing AppleScript.
    public static func tabs(_ output: String) -> [TabRef] {
        output.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 3, let w = Int(f[0]), let t = Int(f[1]), f[2].hasPrefix("/dev/") else { return nil }
            return TabRef(window: w, tab: t, tty: f[2], title: f.count > 3 ? f[3] : "")
        }
    }

    /// Parses `window<TAB>tab<TAB>tty<TAB>name` lines, one per iTerm2 session (split panes are
    /// separate sessions with their own TTY). Names may contain tabs; a TTY is kept once.
    public static func iTermSessions(_ output: String) -> [TabRef] {
        var seen = Set<String>()
        return output.split(whereSeparator: \.isNewline).compactMap { line in
            let f = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 3, let w = Int(f[0]), let t = Int(f[1]), f[2].hasPrefix("/dev/"),
                  seen.insert(f[2]).inserted else { return nil }
            return TabRef(window: w, tab: t, tty: f[2], title: f.count > 3 ? f[3] : "")
        }
    }
}
