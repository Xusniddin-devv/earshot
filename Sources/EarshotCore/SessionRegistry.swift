import Foundation

/// Claude Code's live session registry (`~/.claude/sessions/<pid>.json`).
///
/// A background job's hooks report the job's hidden pty, not the tab the user sees. The registry
/// links the two: the tab's interactive client has `parkedJobId` = the job's `jobId`.
/// The format is undocumented, so anything unexpected is skipped and Earshot falls back to hook TTYs.
public enum SessionRegistry {
    public struct Entry: Equatable, Sendable {
        public var pid: Int32
        public var sessionId: String
        public var kind: String?
        public var jobId: String?
        public var parkedJobId: String?
        public var cwd: String?
        /// `busy`, `waiting`, `idle`, `shell`…
        public var status: String?

        public init(pid: Int32, sessionId: String, kind: String?, jobId: String?, parkedJobId: String?,
                    cwd: String? = nil, status: String? = nil) {
            self.pid = pid
            self.sessionId = sessionId
            self.kind = kind
            self.jobId = jobId
            self.parkedJobId = parkedJobId
            self.cwd = cwd
            self.status = status
        }
    }

    /// A running session as seen on a tab, for sessions that have sent no hook event yet.
    public struct Visible: Equatable, Sendable {
        public var sessionId: String
        public var cwd: String
        public var tty: String
        public var status: SessionStatus

        public init(sessionId: String, cwd: String, tty: String, status: SessionStatus) {
            self.sessionId = sessionId
            self.cwd = cwd
            self.tty = tty
            self.status = status
        }
    }

    /// What the process table says about a pid now.
    public struct Process: Equatable, Sendable {
        public var name: String
        public var tty: String?

        public init(name: String, tty: String?) {
            self.name = name
            self.tty = tty
        }
    }

    public static var liveDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions")
    }

    /// Parses the first JSON object in `data`; files sometimes carry trailing garbage.
    public static func parse(_ data: Data) -> Entry? {
        guard let object = firstObject(data),
              let json = try? JSONSerialization.jsonObject(with: object) as? [String: Any],
              let pid = (json["pid"] as? NSNumber)?.int32Value, pid > 0,
              let sessionId = json["sessionId"] as? String, !sessionId.isEmpty
        else { return nil }
        return Entry(pid: pid, sessionId: sessionId, kind: json["kind"] as? String,
                     jobId: json["jobId"] as? String, parkedJobId: json["parkedJobId"] as? String,
                     cwd: json["cwd"] as? String, status: json["status"] as? String)
    }

    /// Reads every `*.json` in `dir`; a missing dir or unreadable file just yields fewer entries.
    public static func load(dir: URL) -> [Entry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { (try? Data(contentsOf: $0)).flatMap(parse) }
    }

    /// `[bg sessionId: visible tab tty]` for every background job whose client tab has a terminal.
    /// Registry files can outlive their process and the pid be reused, so a client only counts
    /// while its pid is still a `claude` process.
    public static func ttyOverrides(_ entries: [Entry], process: (Int32) -> Process?) -> [String: String] {
        var out: [String: String] = [:]
        let clients = entries.filter { $0.kind == "interactive" && $0.parkedJobId != nil }.sorted { $0.pid < $1.pid }
        for job in entries where job.kind == "bg" {
            guard let id = job.jobId else { continue }
            for c in clients where c.parkedJobId == id {
                if let p = process(c.pid), p.name == "claude", let t = p.tty {
                    out[job.sessionId] = t
                    break
                }
            }
        }
        return out
    }

    /// The bytes of the first balanced `{…}` object, honouring strings and escapes.
    static func firstObject(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard let start = bytes.firstIndex(where: { !($0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09) }),
              bytes[start] == UInt8(ascii: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        for i in start..<bytes.count {
            let b = bytes[i]
            if inString {
                if escaped { escaped = false } else if b == UInt8(ascii: "\\") { escaped = true } else if b == UInt8(ascii: "\"") { inString = false }
                continue
            }
            switch b {
            case UInt8(ascii: "\""): inString = true
            case UInt8(ascii: "{"): depth += 1
            case UInt8(ascii: "}"):
                depth -= 1
                if depth == 0 { return Data(bytes[start...i]) }
            default: break
            }
        }
        return nil
    }

    /// One entry per live client tab: the client's own session, or the background job parked in it.
    public static func visible(_ entries: [Entry], process: (Int32) -> Process?) -> [Visible] {
        let jobs = Dictionary(entries.filter { $0.kind == "bg" }.compactMap { e in e.jobId.map { ($0, e) } },
                              uniquingKeysWith: { a, _ in a })
        return entries.filter { $0.kind != "bg" }.sorted { $0.pid < $1.pid }.compactMap { client in
            guard let p = process(client.pid), p.name == "claude", let tty = p.tty else { return nil }
            let shown = client.parkedJobId.flatMap { jobs[$0] } ?? client
            return Visible(sessionId: shown.sessionId, cwd: shown.cwd ?? "", tty: tty, status: status(shown.status))
        }
    }

    static func status(_ raw: String?) -> SessionStatus {
        switch raw {
        case "busy": .working
        case "waiting": .waiting
        default: .idle
        }
    }
}
