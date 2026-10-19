import Foundation
import Testing
@testable import EarshotCore

private func entry(_ json: String) -> SessionRegistry.Entry { SessionRegistry.parse(Data(json.utf8))! }
private let procs: [Int32: SessionRegistry.Process] = [
    10: .init(name: "claude", tty: "/dev/ttys001"),
    20: .init(name: "claude", tty: "/dev/ttys002"),
    30: .init(name: "claude bg-spare", tty: "/dev/ttys009"),
    40: .init(name: "zsh", tty: "/dev/ttys004"),
]

@Test func parsesCwdAndStatus() {
    let e = entry(#"{"pid":10,"sessionId":"a","cwd":"/w/app","status":"busy","updatedAt":1792422367092}"#)
    #expect(e.cwd == "/w/app" && e.status == "busy")
}

@Test func visibleSessionsCoverIdleTabsAndParkedJobs() {
    let entries = [
        entry(#"{"pid":10,"sessionId":"plain","kind":"interactive","cwd":"/w/a","status":"idle"}"#),
        entry(#"{"pid":20,"sessionId":"client","kind":"interactive","cwd":"/w/b","status":"idle","parkedJobId":"J"}"#),
        entry(#"{"pid":30,"sessionId":"job","kind":"bg","jobId":"J","cwd":"/w/b","status":"busy"}"#),
        entry(#"{"pid":40,"sessionId":"stale","kind":"interactive","cwd":"/w/c","status":"idle"}"#),
    ]
    let v = SessionRegistry.visible(entries, process: { procs[$0] })
    #expect(v.map(\.sessionId).sorted() == ["job", "plain"])
    #expect(v.first { $0.sessionId == "job" }?.tty == "/dev/ttys002")
    #expect(v.first { $0.sessionId == "job" }?.status == .working)
}

@Test func seedAddsOnlyUnknownSessions() {
    let s = SessionStore()
    s.apply(event(.stop, "known", tty: "/dev/ttys001", message: "hi"))
    s.seed([
        .init(sessionId: "known", cwd: "/w/a", tty: "/dev/ttys001", status: .working),
        .init(sessionId: "other", cwd: "/w/x", tty: "/dev/ttys001", status: .idle),   // tab already taken
        .init(sessionId: "new", cwd: "/w/n", tty: "/dev/ttys003", status: .waiting),
    ])
    #expect(s.sessions.count == 2)
    #expect(s.sessions.first { $0.id == "known" }?.status == .finished)   // hooks win
    #expect(s.sessions.first { $0.id == "new" }?.status == .waiting)
}

@Test func emptyTabListDoesNotPrune() {
    #expect(TabScan.result(tabs: [], failedApps: [], allFailed: false, claudeTTYs: ["/dev/ttys001"],
                           ownTTY: nil, oldTitles: [:]) == nil)
}
