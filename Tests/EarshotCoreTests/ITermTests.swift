import Foundation
import Testing
@testable import EarshotCore

// MARK: parsing

@Test func parsesITermSessionLines() {
    let out = "1\t1\t/dev/ttys004\tclaude (node)\n1\t2\t/dev/ttys005\t\n"
    #expect(TerminalParse.iTermSessions(out) == [
        TabRef(window: 1, tab: 1, tty: "/dev/ttys004", title: "claude (node)"),
        TabRef(window: 1, tab: 2, tty: "/dev/ttys005", title: ""),
    ])
}

@Test func iTermSplitPanesAreSeparateEntries() {
    let out = "2\t1\t/dev/ttys010\tleft\n2\t1\t/dev/ttys011\tright\n"
    #expect(TerminalParse.iTermSessions(out).map(\.tty) == ["/dev/ttys010", "/dev/ttys011"])
    #expect(TerminalParse.iTermSessions(out).allSatisfy { $0.window == 2 && $0.tab == 1 })
}

@Test func iTermNameKeepsTabsAndDropsCR() {
    let out = "1\t1\t/dev/ttys004\ta\tb\r\n"
    #expect(TerminalParse.iTermSessions(out) == [TabRef(window: 1, tab: 1, tty: "/dev/ttys004", title: "a\tb")])
}

@Test func iTermSkipsMalformedAndDuplicateLines() {
    // A session name with a newline spills onto a line of its own; it must not become a session.
    let out = "garbage\n1\t1\t/dev/ttys004\tfirst\nspilled name part\n1\tx\t/dev/ttys006\tt\n1\t1\tnotatty\tt\n2\t1\t/dev/ttys004\tdupe\n"
    #expect(TerminalParse.iTermSessions(out) == [TabRef(window: 1, tab: 1, tty: "/dev/ttys004", title: "first")])
    #expect(TerminalParse.iTermSessions("") == [])
}

// MARK: composite adapter

private final class FakeTerminal: TerminalAdapter {
    let name: String
    var list: [TabRef]
    var front: String?
    var error: String?
    private(set) var focusCalls: [String] = []
    private(set) var lastError: String?

    init(_ name: String, ttys: [String], front: String? = nil, error: String? = nil) {
        self.name = name
        list = ttys.enumerated().map { TabRef(window: 1, tab: $0.offset + 1, tty: $0.element, title: name) }
        self.front = front
        self.error = error
    }

    func tabs() -> [TabRef] {
        lastError = error
        return error == nil ? list : []
    }

    func focusedTTY() -> String? { front }

    func focus(tty: String) -> Bool {
        focusCalls.append(tty)
        return list.contains { $0.tty == tty }
    }
}

@Test func compositeMergesTabLists() {
    let apple = FakeTerminal("Terminal", ttys: ["/dev/ttys001", "/dev/ttys002"])
    let iterm = FakeTerminal("iTerm2", ttys: ["/dev/ttys009"])
    let c = CompositeTerminal([apple, iterm])
    #expect(c.tabs().map(\.tty) == ["/dev/ttys001", "/dev/ttys002", "/dev/ttys009"])
    #expect(c.tabs().map(\.title) == ["Terminal", "Terminal", "iTerm2"])
    #expect(c.lastError == nil && c.failedApps.isEmpty)
}

@Test func compositeReportsWhichMemberFailedButKeepsTheOthers() {
    let apple = FakeTerminal("Terminal", ttys: ["/dev/ttys001"], error: "not allowed")
    let iterm = FakeTerminal("iTerm2", ttys: ["/dev/ttys009"])
    let c = CompositeTerminal([apple, iterm])
    #expect(c.tabs().map(\.tty) == ["/dev/ttys009"])
    // One healthy member is enough for a usable (partial) scan.
    #expect(c.lastError == nil && c.failedApps == ["Terminal"])
    iterm.error = "also not allowed"
    #expect(c.tabs().isEmpty)
    #expect(c.lastError != nil && c.failedApps == ["Terminal", "iTerm2"])
    apple.error = nil
    iterm.error = nil
    _ = c.tabs()
    #expect(c.lastError == nil && c.failedApps.isEmpty)
}

@Test func singleAdapterFailedAppsIsItself() {
    let apple = FakeTerminal("Terminal", ttys: ["/dev/ttys001"], error: "nope")
    _ = apple.tabs()
    #expect(apple.failedApps == ["Terminal"])
    apple.error = nil
    _ = apple.tabs()
    #expect(apple.failedApps.isEmpty)
}

// MARK: scan results

@Test func healthyScanPrunesToClaudeTabsAndRetitles() throws {
    let tabs = [TabRef(window: 1, tab: 1, tty: "/dev/ttys001", title: "a"),
                TabRef(window: 1, tab: 2, tty: "/dev/ttys002", title: "b")]
    let r = try #require(TabScan.result(tabs: tabs, failedApps: [], allFailed: false,
                                        claudeTTYs: ["/dev/ttys001", "/dev/ttys002", "/dev/ttys050"],
                                        ownTTY: "/dev/ttys002", oldTitles: ["/dev/ttys009": "gone"]))
    #expect(r.live == ["/dev/ttys001"])
    #expect(r.titles == ["/dev/ttys001": "a", "/dev/ttys002": "b"])
}

@Test func partialScanKeepsSessionsTheFailedAppMayOwn() throws {
    // Terminal failed, iTerm2 answered: tabs from iTerm2 still retitle, and a claude tty that
    // could be one of Terminal's tabs survives; a tty without claude is still pruned.
    let tabs = [TabRef(window: 1, tab: 1, tty: "/dev/ttys009", title: "iterm")]
    let r = try #require(TabScan.result(tabs: tabs, failedApps: ["Terminal"], allFailed: false,
                                        claudeTTYs: ["/dev/ttys009", "/dev/ttys001", "/dev/ttys002"],
                                        ownTTY: "/dev/ttys002", oldTitles: ["/dev/ttys001": "old", "/dev/ttys009": "x"]))
    #expect(r.live == ["/dev/ttys009", "/dev/ttys001"])
    #expect(r.titles == ["/dev/ttys009": "iterm", "/dev/ttys001": "old"])
}

@Test func failedScanConcludesNothing() {
    #expect(TabScan.result(tabs: [], failedApps: ["Terminal"], allFailed: true, claudeTTYs: ["/dev/ttys001"],
                           ownTTY: nil, oldTitles: [:]) == nil)
}

@Test func compositeFocusedTTYComesFromTheFrontmostApp() {
    let apple = FakeTerminal("Terminal", ttys: ["/dev/ttys001"])
    let iterm = FakeTerminal("iTerm2", ttys: ["/dev/ttys009"], front: "/dev/ttys009")
    let c = CompositeTerminal([apple, iterm])
    #expect(c.focusedTTY() == "/dev/ttys009")
    iterm.front = nil
    #expect(c.focusedTTY() == nil)
    apple.front = "/dev/ttys001"
    #expect(c.focusedTTY() == "/dev/ttys001")
}

@Test func compositeFocusAsksTheOwnerOnly() {
    let apple = FakeTerminal("Terminal", ttys: ["/dev/ttys001"])
    let iterm = FakeTerminal("iTerm2", ttys: ["/dev/ttys009"])
    let c = CompositeTerminal([apple, iterm])
    _ = c.tabs()
    #expect(c.focus(tty: "/dev/ttys009"))
    #expect(apple.focusCalls.isEmpty && iterm.focusCalls == ["/dev/ttys009"])
}

@Test func compositeFocusFallsBackToEveryMemberForUnknownTTY() {
    let apple = FakeTerminal("Terminal", ttys: ["/dev/ttys001"])
    let iterm = FakeTerminal("iTerm2", ttys: ["/dev/ttys009"])
    let c = CompositeTerminal([apple, iterm])
    // No tabs() yet: nothing known, so each member is tried in order.
    #expect(c.focus(tty: "/dev/ttys009"))
    #expect(apple.focusCalls == ["/dev/ttys009"] && iterm.focusCalls == ["/dev/ttys009"])
    #expect(!c.focus(tty: "/dev/ttys077"))
}

@Test func compositeWithNoMembersIsEmpty() {
    let c = CompositeTerminal([])
    #expect(c.tabs().isEmpty && c.focusedTTY() == nil && !c.focus(tty: "/dev/ttys001") && c.lastError == nil)
}

// MARK: config

@Test func configTerminalDefaultsToAuto() throws {
    #expect(Config().terminal == .auto)
    let url = tmpDir().appendingPathComponent("config.json")
    try Data(#"{"terminal":"iterm"}"#.utf8).write(to: url)
    #expect(Config.load(url).terminal == .iterm)
    try Data(#"{"terminal":"ghostty","mode":"summary"}"#.utf8).write(to: url)
    let c = Config.load(url)
    #expect(c.terminal == .auto && c.mode == .summary)
}
