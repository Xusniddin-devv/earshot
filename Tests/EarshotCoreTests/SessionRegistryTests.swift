import Foundation
import Testing
@testable import EarshotCore

private let client = #"{"pid":41001,"sessionId":"aaaa1111","kind":"interactive","status":"idle","name":"my-project","parkedJobId":"bbbb2222"}"#
private let job = #"{"pid":42002,"sessionId":"bbbb2222-cccc","kind":"bg","status":"busy","name":"voice tool","jobId":"bbbb2222"}"#

private func claude(_ tty: String?) -> SessionRegistry.Process? {
    SessionRegistry.Process(name: "claude", tty: tty)
}

private func entry(_ json: String) -> SessionRegistry.Entry? {
    SessionRegistry.parse(Data(json.utf8))
}

@Test func parsesRegistryEntries() throws {
    let c = try #require(entry(client))
    #expect(c == SessionRegistry.Entry(pid: 41001, sessionId: "aaaa1111", kind: "interactive",
                                       jobId: nil, parkedJobId: "bbbb2222"))
    let j = try #require(entry(job))
    #expect(j.kind == "bg" && j.jobId == "bbbb2222" && j.parkedJobId == nil && j.pid == 42002)
}

@Test func parsesFirstObjectDespiteTrailingGarbage() throws {
    let e = try #require(entry(job + "}"))
    #expect(e.jobId == "bbbb2222")
    // Two objects back to back, and braces inside strings must not confuse the scan.
    let tricky = #"{"pid":1,"sessionId":"s","kind":"bg","name":"a } \" {","jobId":"j"}{"pid":2}"#
    #expect(entry(tricky)?.jobId == "j")
    #expect(entry(tricky)?.pid == 1)
}

@Test func skipsUnreadableOrIncompleteEntries() {
    #expect(entry("") == nil)
    #expect(entry("not json") == nil)
    #expect(entry("[1,2]") == nil)
    #expect(entry(#"{"pid":1,"sessionId":"s""#) == nil) // truncated
    #expect(entry(#"{"sessionId":"s","kind":"bg"}"#) == nil) // no pid
    #expect(entry(#"{"pid":"x","sessionId":"s"}"#) == nil) // wrong type
    #expect(entry(#"{"pid":1,"kind":"bg"}"#) == nil) // no sessionId
    // Optional fields may be missing or of an unexpected type.
    #expect(entry(#"{"pid":1,"sessionId":"s","jobId":5}"#)
        == SessionRegistry.Entry(pid: 1, sessionId: "s", kind: nil, jobId: nil, parkedJobId: nil))
}

@Test func mapsBackgroundJobToItsClientTab() throws {
    let entries = [try #require(entry(client)), try #require(entry(job))]
    let process: (Int32) -> SessionRegistry.Process? = { claude($0 == 41001 ? "/dev/ttys002" : "/dev/ttys011") }
    #expect(SessionRegistry.ttyOverrides(entries, process: process) == ["bbbb2222-cccc": "/dev/ttys002"])
}

@Test func noOverrideWithoutParkedClient() {
    let bg = SessionRegistry.Entry(pid: 2, sessionId: "job", kind: "bg", jobId: "j1", parkedJobId: nil)
    let other = SessionRegistry.Entry(pid: 1, sessionId: "c", kind: "interactive", jobId: nil, parkedJobId: "j2")
    let plain = SessionRegistry.Entry(pid: 3, sessionId: "p", kind: "interactive", jobId: nil, parkedJobId: nil)
    #expect(SessionRegistry.ttyOverrides([bg, other, plain], process: { _ in claude("/dev/ttys001") }).isEmpty)
    #expect(SessionRegistry.ttyOverrides([], process: { _ in claude("/dev/ttys001") }).isEmpty)
}

@Test func noOverrideWhenClientHasNoTerminal() {
    // Stale file: the client pid is gone (or has no tty).
    let bg = SessionRegistry.Entry(pid: 2, sessionId: "job", kind: "bg", jobId: "j", parkedJobId: nil)
    let c = SessionRegistry.Entry(pid: 1, sessionId: "c", kind: "interactive", jobId: nil, parkedJobId: "j")
    #expect(SessionRegistry.ttyOverrides([bg, c], process: { _ in nil }).isEmpty)
    #expect(SessionRegistry.ttyOverrides([bg, c], process: { _ in claude(nil) }).isEmpty)
}

@Test func noOverrideWhenClientPidWasReused() {
    // Stale file whose pid now belongs to a shell in some other tab: that tty must not be trusted.
    let bg = SessionRegistry.Entry(pid: 2, sessionId: "job", kind: "bg", jobId: "j", parkedJobId: nil)
    let c = SessionRegistry.Entry(pid: 1, sessionId: "c", kind: "interactive", jobId: nil, parkedJobId: "j")
    #expect(SessionRegistry.ttyOverrides([bg, c], process: { _ in
        SessionRegistry.Process(name: "zsh", tty: "/dev/ttys004") }).isEmpty)
    #expect(SessionRegistry.ttyOverrides([bg, c], process: { _ in claude("/dev/ttys004") }) == ["job": "/dev/ttys004"])
}

@Test func multipleJobsAndClients() {
    let entries = [
        SessionRegistry.Entry(pid: 10, sessionId: "jobA", kind: "bg", jobId: "a", parkedJobId: nil),
        SessionRegistry.Entry(pid: 11, sessionId: "jobB", kind: "bg", jobId: "b", parkedJobId: nil),
        SessionRegistry.Entry(pid: 1, sessionId: "c1", kind: "interactive", jobId: nil, parkedJobId: "a"),
        SessionRegistry.Entry(pid: 2, sessionId: "c2", kind: "interactive", jobId: nil, parkedJobId: "b"),
        // Two clients claim job b; the stale one (no tty) loses, the live one wins.
        SessionRegistry.Entry(pid: 3, sessionId: "c3", kind: "interactive", jobId: nil, parkedJobId: "b"),
    ]
    let ttys: [Int32: String] = [1: "/dev/ttys001", 3: "/dev/ttys003"]
    #expect(SessionRegistry.ttyOverrides(entries, process: { claude(ttys[$0]) })
        == ["jobA": "/dev/ttys001", "jobB": "/dev/ttys003"])
    // Two live clients for one job: the lowest pid wins, so the answer is stable between refreshes.
    let both: [Int32: String] = [1: "/dev/ttys001", 2: "/dev/ttys002", 3: "/dev/ttys003"]
    #expect(SessionRegistry.ttyOverrides(entries, process: { claude(both[$0]) })["jobB"] == "/dev/ttys002")
}

@Test func loadsDirectorySkippingJunk() throws {
    let dir = tmpDir()
    try Data(client.utf8).write(to: dir.appendingPathComponent("41001.json"))
    try Data((job + "}").utf8).write(to: dir.appendingPathComponent("42002.json"))
    try Data("garbage".utf8).write(to: dir.appendingPathComponent("1.json"))
    try Data(job.utf8).write(to: dir.appendingPathComponent("42002.other.key"))
    let entries = SessionRegistry.load(dir: dir).sorted { $0.pid < $1.pid }
    #expect(entries.map(\.pid) == [41001, 42002])
    #expect(SessionRegistry.load(dir: dir.appendingPathComponent("missing")).isEmpty)
}

// MARK: store integration

@Test func overrideMovesBackgroundSessionToVisibleTab() {
    let s = SessionStore()
    s.apply(event(.userPromptSubmit, "job", tty: "/dev/ttys011"))
    s.setTTYOverrides(["job": "/dev/ttys002"])
    #expect(s.sessions.first?.tty == "/dev/ttys002")
    #expect(s.session(forTTY: "/dev/ttys002")?.id == "job")
    // Pruning by visible tabs keeps it.
    s.prune(liveTTYs: ["/dev/ttys002"])
    #expect(s.sessions.map(\.id) == ["job"])
}

@Test func laterEventsKeepTheOverride() {
    let s = SessionStore()
    s.setTTYOverrides(["job": "/dev/ttys002"])
    s.apply(event(.userPromptSubmit, "job", tty: "/dev/ttys011", at: 1))
    #expect(s.sessions.first?.tty == "/dev/ttys002")
    s.apply(event(.stop, "job", tty: "/dev/ttys011", at: 2, message: "ok"))
    #expect(s.sessions.first?.tty == "/dev/ttys002")
}

@Test func overriddenJobOwnsTheTab() {
    // The parked client's own (stale) session on that tab gives way to the job it shows.
    let s = SessionStore()
    s.apply(event(.stop, "client", tty: "/dev/ttys002", at: 1, message: "old"))
    s.apply(event(.userPromptSubmit, "job", tty: "/dev/ttys011", at: 2))
    s.apply(event(.stop, "other", tty: "/dev/ttys005", at: 3))
    s.setTTYOverrides(["job": "/dev/ttys002"])
    #expect(Set(s.sessions.map(\.id)) == ["job", "other"])
}

@Test func withoutOverridesNothingChanges() {
    let s = SessionStore()
    s.apply(event(.userPromptSubmit, "job", tty: "/dev/ttys011"))
    s.setTTYOverrides([:])
    #expect(s.sessions.first?.tty == "/dev/ttys011")
    s.prune(liveTTYs: ["/dev/ttys002"])
    #expect(s.sessions.isEmpty)
}

@Test func liveProcessNameReadsArgv0() {
    #expect(SysctlProcessTree().name(of: getpid()) != nil)
    #expect(SysctlProcessTree().name(of: 999_999_999) == nil)
}

@Test func unparkedJobGoesBackToItsOwnTTY() {
    // The job is attached to a tab, then the client un-parks it: the override disappears and the
    // session must stop claiming the visible tab.
    let s = SessionStore()
    s.apply(event(.userPromptSubmit, "job", tty: "/dev/ttys011", at: 1))
    s.setTTYOverrides(["job": "/dev/ttys002"])
    s.apply(event(.stop, "job", tty: "/dev/ttys011", at: 2, message: "ok"))
    #expect(s.sessions.first?.tty == "/dev/ttys002")
    s.setTTYOverrides([:])
    #expect(s.sessions.first?.tty == "/dev/ttys011")
    #expect(s.session(forTTY: "/dev/ttys002") == nil)
}

@Test func unparkedJobFirstSeenUnderOverrideKeepsHookTTY() {
    let s = SessionStore()
    s.setTTYOverrides(["job": "/dev/ttys002"])
    s.apply(event(.userPromptSubmit, "job", tty: "/dev/ttys011"))
    s.setTTYOverrides([:])
    #expect(s.sessions.first?.tty == "/dev/ttys011")
}
