import CoreGraphics
import Darwin

/// Types text into whatever app is frontmost, as synthetic key events.
/// Needs Accessibility permission (granted to Terminal). Never touches the clipboard.
public enum KeyTyper {
    public static func type(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        let units = Array(text.utf16)
        var i = 0
        while i < units.count {
            var chunk = Array(units[i..<min(i + 20, units.count)])
            i += chunk.count
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                e.flags = []
                e.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                e.post(tap: .cghidEventTap)
                usleep(3000)
            }
        }
    }

    public static func pressReturn() {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: down)
            e?.flags = []
            e?.post(tap: .cghidEventTap)
        }
    }
}
