import Testing
@testable import EarshotCore

private let own = "/dev/ttys010"
private let known: Set<String> = ["/dev/ttys002", "/dev/ttys003"]

@Test func routeTypesIntoKnownFocusedTab() {
    #expect(route(focusedTTYAtRelease: "/dev/ttys002", ownTTY: own, knownTTYs: known, transcript: "list files")
        == .type(tty: "/dev/ttys002"))
}

@Test func routeUsesFocusAtRelease() {
    // Pressed in ttys002, released after switching to ttys003: the release-time tab wins.
    #expect(route(focusedTTYAtRelease: "/dev/ttys003", ownTTY: own, knownTTYs: known, transcript: "hi")
        == .type(tty: "/dev/ttys003"))
}

@Test func routeRefusesDashboardTab() {
    #expect(route(focusedTTYAtRelease: own, ownTTY: own, knownTTYs: known.union([own]), transcript: "hi")
        == .refuse(reason: "dashboard tab is focused"))
}

@Test func routeRefusesUnknownTab() {
    #expect(route(focusedTTYAtRelease: "/dev/ttys009", ownTTY: own, knownTTYs: known, transcript: "hi")
        == .refuse(reason: "focused tab is not a Claude session"))
}

@Test func routeRefusesWhenTerminalNotFront() {
    #expect(route(focusedTTYAtRelease: nil, ownTTY: own, knownTTYs: known, transcript: "hi")
        == .refuse(reason: "Terminal is not in front"))
}

@Test func routeRefusesEmptyTranscript() {
    #expect(route(focusedTTYAtRelease: "/dev/ttys002", ownTTY: own, knownTTYs: known, transcript: "  \n")
        == .refuse(reason: "heard nothing"))
}
