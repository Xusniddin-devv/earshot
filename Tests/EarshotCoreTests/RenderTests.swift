import Foundation
import Testing
@testable import EarshotCore

private let now = Date(timeIntervalSince1970: 1000)

private func session(_ id: String, _ project: String, _ status: SessionStatus, unread: Bool = false,
                     tty: String, age: TimeInterval) -> Session {
    Session(id: id, cwd: "/Users/x/\(project)", tty: tty, status: status, unread: unread, reply: nil,
            changedAt: now.addingTimeInterval(-age))
}

private func state(_ sessions: [Session], selected: Int = 0, focused: String? = nil, playing: String? = nil,
                   titles: [String: String] = [:], status: String = "") -> ViewState {
    ViewState(sessions: sessions, titles: titles, selected: selected, focusedTTY: focused, playingId: playing,
              listening: false, mode: .whole, status: status, now: now)
}

@Test func rendersEmptyState() {
    #expect(Render.lines(state([]), width: 80) == [
        "Earshot  ·  0 sessions  ·  mode: whole",
        "",
        "No Claude sessions yet. Start claude in a Terminal tab.",
        "",
        "↑↓ select  enter jump  p play  s mode  c copy  q quit",
        "",
    ])
}

@Test func rendersRowsWithMarkers() {
    let lines = Render.lines(state([
        session("a", "webapp", .finished, unread: true, tty: "/dev/ttys002", age: 120),
        session("b", "store", .waiting, tty: "/dev/ttys003", age: 10),
        session("c", "crawl", .working, tty: "/dev/ttys004", age: 7200),
    ], focused: "/dev/ttys004", titles: ["/dev/ttys002": "✳ Fix login bug"], status: "ready"), width: 80)
    #expect(lines[0] == "Earshot  ·  3 sessions  ·  mode: whole")
    #expect(lines[2] == "> * " + "webapp          " + " " + "finished       " + " " + "  2m" + "  " + "Fix login bug")
    #expect(lines[3] == "    " + "store           " + " " + "waiting on you " + " " + " 10s")
    #expect(lines[4] == "  @ " + "crawl           " + " " + "working        " + " " + "  2h")
    #expect(lines.last == "ready")
}

@Test func playingStatusShown() {
    let lines = Render.lines(state([session("a", "webapp", .finished, tty: "/dev/ttys002", age: 5)], playing: "a"),
                             width: 80)
    #expect(lines[2].contains("playing"))
}

@Test func singularSession() {
    #expect(Render.lines(state([session("a", "x", .idle, tty: "/dev/ttys002", age: 1)]), width: 80)[0]
        == "Earshot  ·  1 session  ·  mode: whole")
}

@Test func truncatesToWidth() {
    let lines = Render.lines(state([session("a", "a-very-long-project-name", .idle, tty: "/dev/ttys002", age: 1)],
                                   titles: ["/dev/ttys002": String(repeating: "t", count: 200)]), width: 30)
    #expect(lines.allSatisfy { $0.count <= 30 })
}

@Test func ageFormatting() {
    #expect(Render.age(5) == "5s" && Render.age(240) == "4m" && Render.age(7200) == "2h")
}

@Test func titleSpinnerStripped() {
    #expect(Render.cleanTitle("✳ Hello from earshot") == "Hello from earshot")
    #expect(Render.cleanTitle("◐ Icons8 MCP") == "Icons8 MCP")
    #expect(Render.cleanTitle("Terminal") == "Terminal")
}

@Test func selectionFollowsSessionWhenListReorders() {
    let a = session("a", "a", .idle, tty: "/dev/ttys001", age: 1)
    let b = session("b", "b", .idle, tty: "/dev/ttys002", age: 2)
    let c = session("c", "c", .idle, tty: "/dev/ttys003", age: 3)
    #expect(Render.reselect(id: "b", fallback: 1, in: [c, a, b]) == 2)
    #expect(Render.reselect(id: "gone", fallback: 5, in: [a, b]) == 1)
    #expect(Render.reselect(id: nil, fallback: 0, in: []) == 0)
}

@Test func errorRowLabel() {
    let lines = Render.lines(state([session("a", "webapp", .error, tty: "/dev/ttys002", age: 5)]), width: 80)
    #expect(lines[2] == ">   " + "webapp          " + " " + "error          " + " " + "  5s")
}
