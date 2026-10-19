import Testing
@testable import EarshotCore

@Test func parsesTabLines() {
    let out = "1\t1\t/dev/ttys002\tclaude\n2\t3\t/dev/ttys009\t\n"
    #expect(TerminalParse.tabs(out) == [
        TabRef(window: 1, tab: 1, tty: "/dev/ttys002", title: "claude"),
        TabRef(window: 2, tab: 3, tty: "/dev/ttys009", title: ""),
    ])
}

@Test func skipsMalformedLines() {
    #expect(TerminalParse.tabs("garbage\nx\ty\t/dev/ttys1\tt\n\n") == [])
}
