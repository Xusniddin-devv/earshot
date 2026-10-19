import Foundation
@testable import EarshotCore

struct FakeTree: ProcessTree {
    var parents: [Int32: Int32]
    var ttys: [Int32: String]
    func parent(of pid: Int32) -> Int32? { parents[pid] }
    func tty(of pid: Int32) -> String? { ttys[pid] }
}

func tmpDir() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("earshot-tests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func tmpFile() -> URL {
    tmpDir().appendingPathComponent("events.jsonl")
}

func event(_ kind: EventKind, _ id: String, tty: String? = "/dev/ttys002", at seconds: TimeInterval = 0,
           message: String? = nil, type: String? = nil, cwd: String = "/Users/x/webapp") -> HookEvent {
    HookEvent(kind: kind, sessionId: id, cwd: cwd, tty: tty, time: Date(timeIntervalSince1970: seconds),
              lastMessage: message, notificationType: type, source: nil)
}
