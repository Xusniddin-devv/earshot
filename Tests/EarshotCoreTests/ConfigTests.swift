import Foundation
import Testing
@testable import EarshotCore

@Test func configDefaultsWhenMissing() {
    let c = Config.load(tmpDir().appendingPathComponent("none.json"))
    #expect(c == Config())
    #expect(c.mode == .whole && c.voice == "af_heart" && c.speed == 1.0)
    #expect(c.finishSound && c.autoSend && c.hotkey == .rightOption)
}

@Test func configKeepsKnownKeysIgnoresUnknown() throws {
    let url = tmpDir().appendingPathComponent("config.json")
    try Data(#"{"mode":"summary","autoSend":true,"bogus":1}"#.utf8).write(to: url)
    let c = Config.load(url)
    #expect(c.mode == .summary && c.autoSend && c.voice == "af_heart" && c.finishSound)
}

@Test func configGarbageFallsBackToDefaults() throws {
    let url = tmpDir().appendingPathComponent("config.json")
    try Data("{nope".utf8).write(to: url)
    #expect(Config.load(url) == Config())
}

@Test func configRoundTrip() throws {
    let url = tmpDir().appendingPathComponent("sub/config.json")
    var c = Config()
    c.mode = .summary
    c.hotkey = .rightCommand
    c.speed = 1.2
    try c.save(url)
    #expect(Config.load(url) == c)
}
