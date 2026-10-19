import Foundation

/// Claude Code hook events Earshot listens to.
public enum EventKind: String, Codable, CaseIterable, Sendable {
    case sessionStart = "SessionStart"
    case userPromptSubmit = "UserPromptSubmit"
    case stop = "Stop"
    case stopFailure = "StopFailure"
    case notification = "Notification"
    case permissionRequest = "PermissionRequest"
    case postToolUse = "PostToolUse"
    case sessionEnd = "SessionEnd"

    /// The turn is over (done or failed): the moment for the finish sound.
    public var endsTurn: Bool { self == .stop || self == .stopFailure }
}

/// One line of the event log, written by `earshot hook`.
public struct HookEvent: Codable, Equatable, Sendable {
    public var kind: EventKind
    public var sessionId: String
    public var cwd: String
    public var tty: String?
    public var time: Date
    public var lastMessage: String?
    public var notificationType: String?
    public var source: String?

    public init(kind: EventKind, sessionId: String, cwd: String, tty: String?, time: Date,
                lastMessage: String? = nil, notificationType: String? = nil, source: String? = nil) {
        self.kind = kind
        self.sessionId = sessionId
        self.cwd = cwd
        self.tty = tty
        self.time = time
        self.lastMessage = lastMessage
        self.notificationType = notificationType
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case kind, cwd, tty, time, source
        case sessionId = "session_id"
        case lastMessage = "last_message"
        case notificationType = "notification_type"
    }
}

extension JSONEncoder {
    public static var earshot: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }
}

extension JSONDecoder {
    public static var earshot: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
