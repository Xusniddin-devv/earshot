import Foundation

/// Everything Earshot needs from a terminal app (Apple Terminal, iTerm2).
public protocol TerminalAdapter: AnyObject {
    /// Short app name for messages, e.g. "Terminal".
    var name: String { get }
    /// Set when the last AppleScript call failed (usually Automation permission); nil after a success.
    /// For several apps at once: set only when every one of them failed.
    var lastError: String? { get }
    /// Names of the apps whose last `tabs()` failed.
    var failedApps: [String] { get }
    func tabs() -> [TabRef]
    /// TTY of the tab the user is in, or nil unless this terminal app is frontmost.
    func focusedTTY() -> String?
    /// Brings the terminal forward on the tab with this TTY.
    func focus(tty: String) -> Bool
}

extension TerminalAdapter {
    public var failedApps: [String] { lastError == nil ? [] : [name] }
}

/// What one refresh may conclude from a tab scan.
public enum TabScan {
    public struct Result: Equatable, Sendable {
        /// Sessions on other TTYs are pruned.
        public var live: Set<String>
        public var titles: [String: String]
    }

    /// nil when every app failed: nothing is known, so nothing is pruned or retitled.
    /// When only some failed, their tabs are unknown: any TTY running claude is kept and their old
    /// titles stay; tabs from the apps that answered still prune and retitle.
    public static func result(tabs: [TabRef], failedApps: [String], allFailed: Bool, claudeTTYs: Set<String>,
                              ownTTY: String?, oldTitles: [String: String]) -> Result? {
        if allFailed { return nil }
        // No tabs at all while claude runs somewhere is a glitch, not "every tab closed": keep everything.
        if tabs.isEmpty, failedApps.isEmpty, !claudeTTYs.isEmpty { return nil }
        let own: Set<String> = ownTTY.map { [$0] } ?? []
        let fresh = Dictionary(tabs.map { ($0.tty, $0.title) }, uniquingKeysWith: { a, _ in a })
        // A tab only counts if claude is actually running in it (TTY names get reused).
        if failedApps.isEmpty {
            return Result(live: Set(fresh.keys).intersection(claudeTTYs).subtracting(own), titles: fresh)
        }
        return Result(live: claudeTTYs.subtracting(own), titles: oldTitles.merging(fresh) { _, new in new })
    }
}

/// Several terminal apps seen as one: tab lists are merged, focus goes to the app that owns the tab.
public final class CompositeTerminal: TerminalAdapter {
    public let members: [TerminalAdapter]
    public private(set) var lastError: String?
    public private(set) var failedApps: [String] = []
    private var owner: [String: Int] = [:]

    public init(_ members: [TerminalAdapter]) {
        self.members = members
    }

    public var name: String { members.map(\.name).joined(separator: " + ") }

    public func tabs() -> [TabRef] {
        var all: [TabRef] = []
        var errors: [String] = []
        failedApps = []
        owner = [:]
        for (i, m) in members.enumerated() {
            let tabs = m.tabs()
            if let error = m.lastError {
                errors.append("\(m.name): \(error)")
                failedApps.append(m.name)
            }
            for t in tabs where owner[t.tty] == nil {
                owner[t.tty] = i
                all.append(t)
            }
        }
        lastError = !members.isEmpty && errors.count == members.count ? errors.joined(separator: "; ") : nil
        return all
    }

    /// Each member answers only when its app is frontmost, so the first answer is the right one.
    public func focusedTTY() -> String? {
        for m in members {
            if let tty = m.focusedTTY() { return tty }
        }
        return nil
    }

    public func focus(tty: String) -> Bool {
        if let i = owner[tty] { return members[i].focus(tty: tty) }
        return members.contains { $0.focus(tty: tty) }
    }
}
