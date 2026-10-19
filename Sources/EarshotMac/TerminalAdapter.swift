import AppKit
import EarshotCore

/// Apple Terminal via AppleScript. Like iTerm2, it is only asked while running: AppleScript
/// would otherwise launch it (for iTerm2-only users, on every refresh). Call from the main thread.
public final class AppleTerminalAdapter: TerminalAdapter {
    public static let bundleID = "com.apple.Terminal"
    public let name = "Terminal"
    public private(set) var lastError: String?

    public init() {}

    public static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    public func tabs() -> [TabRef] {
        guard AppleTerminalAdapter.isRunning else {
            lastError = nil
            return []
        }
        let out = run("""
        tell application "Terminal"
            set sep to character id 9
            set out to ""
            set wi to 0
            repeat with w in windows
                set wi to wi + 1
                set ti to 0
                repeat with t in tabs of w
                    set ti to ti + 1
                    set out to out & wi & sep & ti & sep & (tty of t) & sep & (custom title of t) & linefeed
                end repeat
            end repeat
            return out
        end tell
        """)
        return TerminalParse.tabs(out ?? "")
    }

    public func focusedTTY() -> String? {
        guard AppleTerminalAdapter.isRunning else { return nil }
        let out = run("""
        tell application "Terminal"
            if frontmost and (count of windows) > 0 then return tty of selected tab of front window
            return ""
        end tell
        """)
        guard let out, out.hasPrefix("/dev/") else { return nil }
        return out
    }

    public func focus(tty: String) -> Bool {
        guard AppleTerminalAdapter.isRunning else { return false }
        let safe = tty.replacingOccurrences(of: "\"", with: "")
        let out = run("""
        tell application "Terminal"
            set wid to missing value
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(safe)" then
                        set wid to id of w
                        set selected of t to true
                    end if
                end repeat
            end repeat
            if wid is missing value then return ""
            -- Reorder by id: `w` is a positional reference that shifts as windows reorder.
            set index of window id wid to 1
            activate
            return "ok"
        end tell
        """)
        return out == "ok"
    }

    private func run(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            lastError = error[NSAppleScript.errorMessage] as? String ?? "\(error)"
            return nil
        }
        lastError = nil
        return result?.stringValue
    }
}

/// iTerm2 via AppleScript (experimental: written against iTerm2's scripting dictionary, not yet
/// run against a real iTerm2). Every call first checks that iTerm2 is running, because talking to
/// it over AppleScript would otherwise launch it. Call from the main thread.
public final class ITermAdapter: TerminalAdapter {
    public static let bundleID = "com.googlecode.iterm2"
    public let name = "iTerm2"
    public private(set) var lastError: String?

    public init() {}

    public static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    public func tabs() -> [TabRef] {
        guard ITermAdapter.isRunning else {
            lastError = nil
            return []
        }
        let out = run("""
        tell application id "\(ITermAdapter.bundleID)"
            set sep to character id 9
            set out to ""
            set wi to 0
            repeat with w in windows
                set wi to wi + 1
                set ti to 0
                repeat with t in tabs of w
                    set ti to ti + 1
                    repeat with s in sessions of t
                        set out to out & wi & sep & ti & sep & (tty of s) & sep & (name of s) & linefeed
                    end repeat
                end repeat
            end repeat
            return out
        end tell
        """)
        return TerminalParse.iTermSessions(out ?? "")
    }

    public func focusedTTY() -> String? {
        guard ITermAdapter.isRunning else { return nil }
        let out = run("""
        tell application id "\(ITermAdapter.bundleID)"
            if frontmost and (count of windows) > 0 then return tty of current session of current tab of current window
            return ""
        end tell
        """, recordError: false)
        guard let out, out.hasPrefix("/dev/") else { return nil }
        return out
    }

    public func focus(tty: String) -> Bool {
        guard ITermAdapter.isRunning else { return false }
        let safe = tty.replacingOccurrences(of: "\"", with: "")
        // Session and tab first, window last: selecting the window reorders `windows`,
        // which would shift the positional references `w` and `t`.
        let out = run("""
        tell application id "\(ITermAdapter.bundleID)"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(safe)" then
                            select s
                            select t
                            select w
                            activate
                            return "ok"
                        end if
                    end repeat
                end repeat
            end repeat
            return ""
        end tell
        """, recordError: false)
        return out == "ok"
    }

    private func run(_ source: String, recordError: Bool = true) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            if recordError { lastError = error[NSAppleScript.errorMessage] as? String ?? "\(error)" }
            return nil
        }
        if recordError { lastError = nil }
        return result?.stringValue
    }
}
