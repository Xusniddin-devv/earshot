import Foundation

public enum SessionStatus: Equatable, Sendable {
    case idle, working, finished, waiting, error
}

public struct Session: Equatable, Sendable {
    public let id: String
    public var cwd: String
    public var tty: String?
    public var status: SessionStatus
    public var unread: Bool
    public var reply: String?
    public var changedAt: Date
    /// The tty the hooks last reported, before any override; where the session goes back to
    /// when its override disappears (the job was un-parked).
    public var hookTTY: String? = nil

    public var project: String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? "?" : name
    }
}

/// Live view of Claude Code sessions, built from hook events.
public final class SessionStore {
    public private(set) var sessions: [Session] = []

    /// Notification types that mean Claude is blocked on the user.
    static let waitingTypes: Set<String> = [
        "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input",
    ]

    /// Background jobs whose hooks report a hidden pty: session id -> the visible tab's tty.
    public private(set) var ttyOverrides: [String: String] = [:]

    public init() {}

    /// Moves background-job sessions onto their visible tab. That tab shows the job, so any other
    /// session still on it (the parked client's own) is dropped, as on a new SessionStart.
    public func setTTYOverrides(_ overrides: [String: String]) {
        for (id, _) in ttyOverrides where overrides[id] == nil {
            if let i = sessions.firstIndex(where: { $0.id == id }) { sessions[i].tty = sessions[i].hookTTY }
        }
        ttyOverrides = overrides
        for (id, tty) in overrides where sessions.contains(where: { $0.id == id }) {
            sessions.removeAll { $0.tty == tty && $0.id != id }
            if let i = sessions.firstIndex(where: { $0.id == id }) { sessions[i].tty = tty }
        }
    }

    public func apply(_ raw: HookEvent) {
        var e = raw
        if let tty = ttyOverrides[e.sessionId] { e.tty = tty }
        if e.kind == .sessionEnd {
            sessions.removeAll { $0.id == e.sessionId }
            return
        }
        if e.kind == .sessionStart, let tty = e.tty {
            sessions.removeAll { $0.tty == tty && $0.id != e.sessionId }
        }

        let index = sessions.firstIndex { $0.id == e.sessionId }
        var s = index.map { sessions[$0] }
            ?? Session(id: e.sessionId, cwd: e.cwd, tty: e.tty, status: .idle, unread: false,
                       reply: nil, changedAt: e.time, hookTTY: raw.tty)

        switch e.kind {
        case .sessionStart:
            s.status = .idle
        case .userPromptSubmit:
            s.status = .working
            s.unread = false
        case .stop:
            s.status = .finished
            s.unread = true
            if let m = e.lastMessage { s.reply = m }
        case .stopFailure:
            s.status = .error
            s.unread = true
            if let m = e.lastMessage { s.reply = m }
        case .notification:
            if let t = e.notificationType, Self.waitingTypes.contains(t) { s.status = .waiting }
        case .permissionRequest:
            s.status = .waiting
        case .postToolUse:
            // Async hooks can land after the turn's Stop; only a new prompt reopens a finished turn.
            if s.status != .finished && s.status != .error { s.status = .working }
        case .sessionEnd:
            break
        }
        s.changedAt = e.time
        if !e.cwd.isEmpty { s.cwd = e.cwd }
        if let tty = e.tty { s.tty = tty }
        if let tty = raw.tty { s.hookTTY = tty }

        if let i = index { sessions[i] = s } else { sessions.append(s) }
        sort()
    }

    public func markRead(id: String) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[i].unread = false
    }

    /// Drops sessions whose Terminal tab no longer exists.
    public func prune(liveTTYs: Set<String>) {
        sessions.removeAll { s in s.tty.map { !liveTTYs.contains($0) } ?? false }
    }

    public func session(forTTY tty: String) -> Session? {
        sessions.first { $0.tty == tty }
    }

    private func sort() {
        sessions.sort { $0.changedAt > $1.changedAt }
    }
}
