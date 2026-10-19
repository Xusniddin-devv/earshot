import Foundation
import Testing
@testable import EarshotCore

private let tree = FakeTree(parents: [500: 400], ttys: [400: "ttys002"])

private func hook(_ json: String, env: [String: String] = [:], log: EventLog) {
    runHook(stdin: Data(json.utf8), env: env, ppid: 500, tree: tree, log: log, now: Date(timeIntervalSince1970: 0))
}

@Test func decodesStopEventFromClaudeStdin() throws {
    let json = #"{"session_id":"abc","transcript_path":"/t.jsonl","cwd":"/Users/x/webapp","hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"Done. Tests pass."}"#
    let log = EventLog(url: tmpFile())
    hook(json, log: log)
    let e = try #require(log.readNew().first)
    #expect(e.kind == .stop && e.sessionId == "abc" && e.cwd == "/Users/x/webapp")
    #expect(e.tty == "/dev/ttys002" && e.lastMessage == "Done. Tests pass.")
}

@Test func notificationKeepsType() throws {
    let log = EventLog(url: tmpFile())
    hook(#"{"session_id":"a","cwd":"/x","hook_event_name":"Notification","message":"m","notification_type":"permission_prompt"}"#, log: log)
    #expect(try #require(log.readNew().first).notificationType == "permission_prompt")
}

@Test func sessionStartKeepsSource() throws {
    let log = EventLog(url: tmpFile())
    hook(#"{"session_id":"a","cwd":"/x","hook_event_name":"SessionStart","source":"clear"}"#, log: log)
    #expect(try #require(log.readNew().first).source == "clear")
}

@Test func dropsInternalAndSubagentEvents() {
    let log = EventLog(url: tmpFile())
    hook(#"{"session_id":"a","cwd":"/x","hook_event_name":"Stop"}"#, env: ["EARSHOT_INTERNAL": "1"], log: log)
    hook(#"{"session_id":"a","cwd":"/x","hook_event_name":"Stop","agent_id":"sub1"}"#, log: log)
    #expect(log.readNew().isEmpty)
}

@Test func ignoresUnknownEventAndGarbage() {
    let log = EventLog(url: tmpFile())
    hook(#"{"session_id":"a","cwd":"/x","hook_event_name":"PreToolUse"}"#, log: log)
    hook("not json", log: log)
    #expect(log.readNew().isEmpty)
}

@Test func hookNeverFailsOnUnwritableLog() throws {
    let dir = tmpDir()
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path) }
    let log = EventLog(url: dir.appendingPathComponent("sub/events.jsonl"))
    hook(#"{"session_id":"a","cwd":"/x","hook_event_name":"Stop"}"#, log: log)
    #expect(log.readNew().isEmpty)
}

@Test func readNewIsIncremental() throws {
    let url = tmpFile()
    let log = EventLog(url: url)
    try log.append(event(.sessionStart, "a"))
    try log.append(event(.stop, "a"))
    #expect(log.readNew().count == 2)
    let handle = try FileHandle(forWritingTo: url)
    handle.seekToEndOfFile()
    handle.write(Data("garbage\n".utf8))
    try handle.close()
    try log.append(event(.sessionEnd, "a"))
    let next = log.readNew()
    #expect(next.count == 1 && next.first?.kind == .sessionEnd)
}

@Test func readNewResetsWhenFileShrinks() throws {
    let url = tmpFile()
    let log = EventLog(url: url)
    for i in 0..<5 { try log.append(event(.stop, "s\(i)")) }
    _ = log.readNew()
    EventLog.trim(url: url, keepLast: 1)
    try log.append(event(.sessionEnd, "s9"))
    #expect(log.readNew().map(\.sessionId) == ["s4", "s9"])
}

@Test func trimKeepsLastLines() throws {
    let url = tmpFile()
    let log = EventLog(url: url)
    for i in 0..<10 { try log.append(event(.stop, "s\(i)")) }
    EventLog.trim(url: url, keepLast: 3)
    #expect(EventLog(url: url).readNew().map(\.sessionId) == ["s7", "s8", "s9"])
}

@Test func resolveTTYWalksAncestors() {
    let t = FakeTree(parents: [18565: 66813, 66813: 68372], ttys: [66813: "ttys002", 68372: "ttys002"])
    #expect(resolveTTY(start: 18565, tree: t) == "/dev/ttys002")
    #expect(resolveTTY(start: 1, tree: FakeTree(parents: [:], ttys: [:])) == nil)
    let cycle = FakeTree(parents: [10: 11, 11: 10], ttys: [:])
    #expect(resolveTTY(start: 10, tree: cycle) == nil)
}

@Test func eventJSONUsesSnakeCase() throws {
    let data = try JSONEncoder.earshot.encode(event(.stop, "a", message: "hi"))
    let s = String(decoding: data, as: UTF8.self)
    #expect(s.contains(#""session_id":"a""#) && s.contains(#""last_message":"hi""#) && s.contains(#""kind":"Stop""#))
}

@Test func permissionRequestAndPostToolUseAreLogged() throws {
    let log = EventLog(url: tmpFile())
    hook(#"{"session_id":"a","cwd":"/x","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf x"}}"#, log: log)
    hook(#"{"session_id":"a","cwd":"/x","hook_event_name":"PostToolUse","tool_name":"Write","tool_response":{},"tool_use_id":"t1"}"#, log: log)
    #expect(log.readNew().map(\.kind) == [.permissionRequest, .postToolUse])
}

@Test func stopFailureReplyIsTheErrorText() throws {
    let log = EventLog(url: tmpFile())
    hook(#"{"session_id":"a","cwd":"/x","hook_event_name":"StopFailure","error":"rate_limit","error_details":"429 Too Many Requests","last_assistant_message":"API Error: Rate limit reached"}"#, log: log)
    hook(#"{"session_id":"a","cwd":"/x","hook_event_name":"StopFailure","error":"overloaded","error_details":"529"}"#, log: log)
    hook(#"{"session_id":"a","cwd":"/x","hook_event_name":"StopFailure","error":"unknown"}"#, log: log)
    hook(#"{"session_id":"a","cwd":"/x","hook_event_name":"StopFailure"}"#, log: log)
    #expect(log.readNew().map(\.lastMessage) == ["API Error: Rate limit reached", "529", "unknown", nil])
}

@Test func onlyTurnEndsPlayTheFinishSound() {
    #expect(EventKind.allCases.filter(\.endsTurn) == [.stop, .stopFailure])
}
