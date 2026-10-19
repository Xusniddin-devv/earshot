import Testing
@testable import EarshotCore

@Test func modifierKeysMapToHotkeys() {
    #expect(KeyChoice.fromModifier(keycode: 61) == .modifier(.rightOption))
    #expect(KeyChoice.fromModifier(keycode: 54) == .modifier(.rightCommand))
    #expect(KeyChoice.fromModifier(keycode: 62) == .modifier(.rightControl))
    #expect(KeyChoice.fromModifier(keycode: 56) == .modifier(.shift))
    #expect(KeyChoice.fromModifier(keycode: 59) == .modifier(.control))
}

@Test func unusableModifiersAreRejected() {
    // Left Command, Caps Lock, fn: used constantly or toggle state.
    for code: Int64 in [55, 57, 63] {
        guard case .rejected = KeyChoice.fromModifier(keycode: code) else {
            Issue.record("\(code) accepted"); continue
        }
    }
}

@Test func ordinaryKeysBecomeKeycodes() {
    #expect(KeyChoice.fromKey(keycode: 102) == .keycode(102))
    #expect(KeyChoice.fromKey(keycode: 111) == .keycode(111))   // F12
}

@Test func typingKeysAreRejected() {
    // Letters, digits, space, return, delete, tab, escape, keypad, arrows, Page Up would break typing.
    for code: Int64 in [0, 18, 49, 36, 51, 48, 53, 82, 123, 126, 116] {
        guard case .rejected = KeyChoice.fromKey(keycode: code) else {
            Issue.record("\(code) accepted"); continue
        }
    }
}

@Test func applyingChoiceUpdatesConfig() {
    var c = Config()
    KeyChoice.keycode(102).apply(to: &c)
    #expect(c.hotkeyKeycode == 102)
    KeyChoice.modifier(.shift).apply(to: &c)
    #expect(c.hotkeyKeycode == nil && c.hotkey == .shift)
}

@Test func fKeysGetReadableLabels() {
    var c = Config()
    c.hotkeyKeycode = 111
    #expect(c.hotkeyLabel == "F12")
    c.hotkeyKeycode = 102
    #expect(c.hotkeyLabel == "the talk key (code 102)")
}
