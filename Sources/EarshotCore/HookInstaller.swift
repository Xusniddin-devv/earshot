import Foundation

/// Adds and removes Earshot's hook entries in Claude Code's `settings.json`,
/// leaving every other key and hook untouched.
public enum HookInstaller {
    public static let events = ["SessionStart", "UserPromptSubmit", "Stop", "StopFailure", "Notification",
                                "PermissionRequest", "PostToolUse", "SessionEnd"]

    public enum Status: Equatable, Sendable {
        case missing
        case installed
        /// Installed by an older Earshot that did not listen to these events yet.
        case outdated(missing: [String])

        public var fix: String { "run: earshot install-hooks" }
    }

    public enum Failure: Error {
        case notAnObject
    }

    public static func install(settings: Data?, binary: String) throws -> Data {
        var root = try parse(settings)
        var hooks = removingOurs(root["hooks"] as? [String: Any] ?? [:])
        let handler: [String: Any] = ["type": "command", "command": "\(binary) hook", "async": true, "timeout": 5]
        for e in events {
            var groups = hooks[e] as? [[String: Any]] ?? []
            groups.append(["hooks": [handler]])
            hooks[e] = groups
        }
        root["hooks"] = hooks
        return try serialize(root)
    }

    public static func uninstall(settings: Data) throws -> Data {
        var root = try parse(settings)
        let hooks = removingOurs(root["hooks"] as? [String: Any] ?? [:])
        root["hooks"] = hooks.isEmpty ? nil : hooks
        return try serialize(root)
    }

    /// True if any Earshot hook is present, whichever binary path it points at.
    public static func hasOurs(settings: Data?) -> Bool {
        guard let root = try? parse(settings), let hooks = root["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { value in
            (value as? [[String: Any]] ?? []).contains { g in
                (g["hooks"] as? [[String: Any]] ?? []).contains(where: isOurs)
            }
        }
    }

    public static func isInstalled(settings: Data?, binary: String) -> Bool {
        status(settings: settings, binary: binary) == .installed
    }

    public static func status(settings: Data?, binary: String) -> Status {
        guard let root = try? parse(settings), let hooks = root["hooks"] as? [String: Any] else { return .missing }
        let missing = events.filter { e in
            let groups = hooks[e] as? [[String: Any]] ?? []
            return !groups.contains { g in
                (g["hooks"] as? [[String: Any]] ?? []).contains { $0["command"] as? String == "\(binary) hook" }
            }
        }
        if missing.isEmpty { return .installed }
        return missing.count == events.count ? .missing : .outdated(missing: missing)
    }

    /// Writes settings atomically to the file `url` points at. A symlinked settings.json (dotfile
    /// managers) keeps its link: an atomic write to the link itself would replace it with a file.
    public static func writeSettings(_ data: Data, to url: URL) throws {
        try data.write(to: url.resolvingSymlinksInPath(), options: .atomic)
    }

    /// Suffix for the settings backup file, e.g. `.earshot-backup-20261019-143000`.
    public static func backupSuffix(for date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyyMMdd-HHmmss"
        return ".earshot-backup-" + f.string(from: date)
    }

    static func isOurs(_ handler: [String: Any]) -> Bool {
        (handler["command"] as? String)?.hasSuffix("earshot hook") ?? false
    }

    private static func removingOurs(_ hooks: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else {
                out[event] = value
                continue
            }
            let kept: [[String: Any]] = groups.compactMap { g in
                guard let handlers = g["hooks"] as? [[String: Any]] else { return g }
                let rest = handlers.filter { !isOurs($0) }
                if rest.isEmpty { return nil }
                var copy = g
                copy["hooks"] = rest
                return copy
            }
            if !kept.isEmpty { out[event] = kept }
        }
        return out
    }

    private static func parse(_ data: Data?) throws -> [String: Any] {
        guard let data, !data.isEmpty else { return [:] }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.notAnObject
        }
        return obj
    }

    private static func serialize(_ obj: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys])
    }
}
