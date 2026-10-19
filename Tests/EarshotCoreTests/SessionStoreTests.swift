import Foundation
import Testing
@testable import EarshotCore

@Test func startThenPromptThenStop() throws {
    let s = SessionStore()
    s.apply(event(.sessionStart, "a", at: 1))
    #expect(s.sessions.first?.status == .idle)
    s.apply(event(.userPromptSubmit, "a", at: 2))
    #expect(s.sessions.first?.status == .working)
    s.apply(event(.stop, "a", at: 3, message: "Done."))
    let a = try #require(s.sessions.first)
    #expect(a.status == .finished && a.unread && a.reply == "Done." && a.project == "webapp")
}

@Test func stopWithoutMessageKeepsPreviousReply() {
    let s = SessionStore()
    s.apply(event(.stop, "a", message: "First."))
    s.apply(event(.stop, "a", message: nil))
    #expect(s.sessions.first?.reply == "First.")
}

@Test func promptClearsUnread() {
    let s = SessionStore()
    s.apply(event(.stop, "a", message: "x"))
    s.apply(event(.userPromptSubmit, "a"))
    #expect(s.sessions.first?.unread == false)
}

@Test func permissionNotificationWaits() {
    for type in ["permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input"] {
        let s = SessionStore()
        s.apply(event(.userPromptSubmit, "a"))
        s.apply(event(.notification, "a", type: type))
        #expect(s.sessions.first?.status == .waiting)
    }
}

@Test func idleNotificationIgnored() {
    let s = SessionStore()
    s.apply(event(.stop, "a", message: "x"))
    s.apply(event(.notification, "a", type: "idle_prompt"))
    #expect(s.sessions.first?.status == .finished)
}

@Test func sessionEndRemoves() {
    let s = SessionStore()
    s.apply(event(.sessionStart, "a"))
    s.apply(event(.sessionEnd, "a"))
    #expect(s.sessions.isEmpty)
}

@Test func newSessionOnSameTTYReplacesOld() {
    let s = SessionStore()
    s.apply(event(.sessionStart, "a", tty: "/dev/ttys002", at: 1))
    s.apply(event(.sessionStart, "b", tty: "/dev/ttys002", at: 2))
    #expect(s.sessions.map(\.id) == ["b"])
}

@Test func unknownSessionCreatedFromStop() {
    let s = SessionStore()
    s.apply(event(.stop, "z", message: "hi"))
    #expect(s.sessions.first?.id == "z" && s.sessions.first?.status == .finished)
}

@Test func unknownSessionFromIdleNotificationIsIdle() {
    let s = SessionStore()
    s.apply(event(.notification, "z", type: "idle_prompt"))
    #expect(s.sessions.first?.status == .idle)
}

@Test func pruneDropsClosedTabs() {
    let s = SessionStore()
    s.apply(event(.sessionStart, "a", tty: "/dev/ttys002"))
    s.apply(event(.sessionStart, "b", tty: "/dev/ttys003"))
    s.apply(event(.sessionStart, "c", tty: nil))
    s.prune(liveTTYs: ["/dev/ttys003"])
    #expect(Set(s.sessions.map(\.id)) == ["b", "c"])
}

@Test func sortedNewestFirst() {
    let s = SessionStore()
    s.apply(event(.sessionStart, "a", tty: "/dev/ttys001", at: 1))
    s.apply(event(.sessionStart, "b", tty: "/dev/ttys002", at: 2))
    s.apply(event(.userPromptSubmit, "a", tty: "/dev/ttys001", at: 3))
    #expect(s.sessions.map(\.id) == ["a", "b"])
}

@Test func markReadClearsUnread() {
    let s = SessionStore()
    s.apply(event(.stop, "a", message: "x"))
    s.markRead(id: "a")
    #expect(s.sessions.first?.unread == false)
}

@Test func sessionForTTY() {
    let s = SessionStore()
    s.apply(event(.sessionStart, "a", tty: "/dev/ttys004"))
    #expect(s.session(forTTY: "/dev/ttys004")?.id == "a")
    #expect(s.session(forTTY: "/dev/ttys009") == nil)
}

@Test func replayedSessionOnReusedTTYWithoutClaudeIsPruned() {
    // Yesterday's session on ttys001; after reboot ttys001 is a plain shell.
    let s = SessionStore()
    s.apply(event(.stop, "old", tty: "/dev/ttys001", message: "x"))
    s.apply(event(.stop, "live", tty: "/dev/ttys002", message: "y"))
    let tabs: Set<String> = ["/dev/ttys001", "/dev/ttys002"]
    let claude: Set<String> = ["/dev/ttys002"]
    s.prune(liveTTYs: tabs.intersection(claude))
    #expect(s.sessions.map(\.id) == ["live"])
}

@Test func permissionRequestWaitsAndPostToolUseResumes() {
    let s = SessionStore()
    s.apply(event(.userPromptSubmit, "a", at: 1))
    s.apply(event(.permissionRequest, "a", at: 2))
    #expect(s.sessions.first?.status == .waiting)
    s.apply(event(.postToolUse, "a", at: 3))
    #expect(s.sessions.first?.status == .working)
    s.apply(event(.notification, "a", at: 4, type: "permission_prompt"))
    s.apply(event(.postToolUse, "a", at: 5))
    #expect(s.sessions.first?.status == .working && s.sessions.first?.unread == false)
}

@Test func lateToolEventDoesNotReopenAFinishedTurn() {
    let s = SessionStore()
    s.apply(event(.userPromptSubmit, "a", at: 1))
    s.apply(event(.stop, "a", at: 2, message: "Done."))
    s.apply(event(.postToolUse, "a", at: 3))
    #expect(s.sessions.first?.status == .finished)
    s.apply(event(.stopFailure, "b", at: 4, message: "API Error"))
    s.apply(event(.postToolUse, "b", at: 5))
    #expect(s.sessions.first { $0.id == "b" }?.status == .error)
}

@Test func postToolUseCreatesUnknownSessionAsWorking() {
    let s = SessionStore()
    s.apply(event(.postToolUse, "a"))
    #expect(s.sessions.first?.status == .working)
}

@Test func stopFailureIsAnError() throws {
    let s = SessionStore()
    s.apply(event(.userPromptSubmit, "a", at: 1))
    s.apply(event(.stop, "a", at: 2, message: "Earlier reply."))
    s.apply(event(.userPromptSubmit, "a", at: 3))
    s.apply(event(.stopFailure, "a", at: 4, message: "API Error: Rate limit reached"))
    let a = try #require(s.sessions.first)
    #expect(a.status == .error && a.unread && a.reply == "API Error: Rate limit reached")
    s.apply(event(.stopFailure, "a", at: 5, message: nil))
    #expect(s.sessions.first?.reply == "API Error: Rate limit reached")
    s.apply(event(.userPromptSubmit, "a", at: 6))
    #expect(s.sessions.first?.status == .working)
}
