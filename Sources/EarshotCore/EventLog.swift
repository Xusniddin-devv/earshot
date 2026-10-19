import Foundation

/// Append-only JSONL log shared by the hook (writer) and the dashboard (reader).
public final class EventLog {
    public let url: URL
    private var offset: UInt64 = 0
    private var pending = Data()

    public init(url: URL) {
        self.url = url
    }

    /// Appends one event as a single `write` so concurrent hooks never interleave.
    public func append(_ e: HookEvent) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        var line = try JSONEncoder.earshot.encode(e)
        line.append(0x0A)
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { close(fd) }
        let written = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard written == line.count else { throw CocoaError(.fileWriteUnknown) }
    }

    /// Events appended since the previous call. Malformed lines are skipped.
    public func readNew() -> [HookEvent] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset {
            offset = 0
            pending = Data()
        }
        guard size > offset else { return [] }
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else { return [] }
        offset += UInt64(data.count)
        pending.append(data)

        var events: [HookEvent] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = pending[pending.startIndex..<newline]
            pending = Data(pending[pending.index(after: newline)...])
            if let e = try? JSONDecoder.earshot.decode(HookEvent.self, from: line) {
                events.append(e)
            }
        }
        return events
    }

    /// Keeps only the newest `keepLast` lines.
    public static func trim(url: URL, keepLast: Int) {
        guard let data = try? Data(contentsOf: url) else { return }
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        guard lines.count > keepLast else { return }
        var out = Data()
        for line in lines.suffix(keepLast) {
            out.append(line)
            out.append(0x0A)
        }
        try? out.write(to: url, options: .atomic)
    }
}
