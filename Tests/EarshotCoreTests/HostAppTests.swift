import Testing
@testable import EarshotCore

@Test func hostAppNamesTheTerminalEarshotRunsIn() {
    #expect(HostApp.name(env: ["TERM_PROGRAM": "Apple_Terminal"]) == "Terminal")
    #expect(HostApp.name(env: ["TERM_PROGRAM": "iTerm.app"]) == "iTerm2")
    #expect(HostApp.name(env: ["TERM_PROGRAM": "ghostty"]) == "your terminal app")
    #expect(HostApp.name(env: [:]) == "your terminal app")
}
