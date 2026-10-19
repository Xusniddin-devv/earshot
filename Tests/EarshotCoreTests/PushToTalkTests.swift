import Foundation
import Testing
@testable import EarshotCore

private let shiftDown: UInt64 = 0x20102, released: UInt64 = 0x100

@Test func shiftAloneStartsAndStops() {
    var p = PushToTalk(key: .shift)
    #expect(p.flagsChanged(keycode: 56, flags: shiftDown) == .start)
    #expect(p.flagsChanged(keycode: 56, flags: released) == .stop)
}

@Test func eitherShiftKeyWorks() {
    var p = PushToTalk(key: .shift)
    #expect(p.flagsChanged(keycode: 60, flags: 0x20104) == .start)
    #expect(p.flagsChanged(keycode: 60, flags: released) == .stop)
}

@Test func typingWhileShiftHeldCancels() {
    // Shift+A for a capital letter must never record or send anything.
    var p = PushToTalk(key: .shift)
    #expect(p.flagsChanged(keycode: 56, flags: shiftDown) == .start)
    #expect(p.keyDown(keycode: 0) == .cancel)
    #expect(p.keyDown(keycode: 0) == PushToTalk.Action?.none)
    #expect(p.flagsChanged(keycode: 56, flags: released) == PushToTalk.Action?.none)
}

@Test func otherModifierWhileHeldCancels() {
    var p = PushToTalk(key: .shift)
    _ = p.flagsChanged(keycode: 56, flags: shiftDown)
    #expect(p.flagsChanged(keycode: 55, flags: 0x120108) == .cancel)   // Shift+Cmd shortcut
    #expect(p.flagsChanged(keycode: 56, flags: released) == PushToTalk.Action?.none)
}

@Test func keyDownWhenIdleIgnored() {
    var p = PushToTalk(key: .shift)
    #expect(p.keyDown(keycode: 0) == PushToTalk.Action?.none)
}

@Test func rightOptionStillWorks() {
    var p = PushToTalk(key: .rightOption)
    #expect(p.flagsChanged(keycode: 58, flags: 0x80120) == PushToTalk.Action?.none)  // left Option ignored
    #expect(p.flagsChanged(keycode: 61, flags: 0x80140) == .start)
    #expect(p.flagsChanged(keycode: 61, flags: released) == .stop)
}

@Test func eitherControlKeyWorks() {
    var p = PushToTalk(key: .control)
    #expect(p.flagsChanged(keycode: 59, flags: 0x40101) == .start)
    #expect(p.flagsChanged(keycode: 59, flags: released) == .stop)
    #expect(p.flagsChanged(keycode: 62, flags: 0x42100) == .start)
    #expect(p.keyDown(keycode: 0) == .cancel)   // Ctrl+C etc. never record
}

@Test func plainKeyHoldStartsAndStops() {
    // Owner's PC keyboard sends Right Ctrl as an ordinary key, code 102, with auto-repeat.
    var p = PushToTalk(keycode: 102)
    #expect(p.keyDown(keycode: 102) == .start)
    #expect(p.keyDown(keycode: 102) == PushToTalk.Action?.none)   // auto-repeat
    #expect(p.keyDown(keycode: 102) == PushToTalk.Action?.none)
    #expect(p.keyUp(keycode: 102) == .stop)
    #expect(p.keyUp(keycode: 102) == PushToTalk.Action?.none)
}

@Test func plainKeyOtherKeyWhileHeldCancels() {
    var p = PushToTalk(keycode: 102)
    _ = p.keyDown(keycode: 102)
    #expect(p.keyDown(keycode: 0) == .cancel)
    #expect(p.keyUp(keycode: 102) == PushToTalk.Action?.none)
    #expect(p.keyDown(keycode: 102) == .start)   // next press works again
}

@Test func plainKeyIgnoresOtherKeysWhenIdle() {
    var p = PushToTalk(keycode: 102)
    #expect(p.keyDown(keycode: 0) == PushToTalk.Action?.none)
    #expect(p.keyUp(keycode: 0) == PushToTalk.Action?.none)
    #expect(p.flagsChanged(keycode: 56, flags: 0x20102) == PushToTalk.Action?.none)
}

@Test func configReadsHotkeyKeycode() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    try Data(#"{"hotkeyKeycode":102}"#.utf8).write(to: url)
    #expect(Config.load(url).hotkeyKeycode == 102)
    #expect(Config().hotkeyKeycode == nil)
}
