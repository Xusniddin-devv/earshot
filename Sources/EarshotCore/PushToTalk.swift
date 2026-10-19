/// Push-to-talk key state machine, fed raw key events by `Hotkey`.
/// The key must be held on its own: any other key while it is down cancels, so a
/// key also used for typing (Shift) never records during normal typing.
public struct PushToTalk {
    public enum Action: Equatable {
        case start, stop, cancel
    }

    let keycodes: Set<Int64>
    let flag: UInt64
    /// True for an ordinary (non-modifier) key, tracked by key down/up instead of modifier flags.
    let plain: Bool
    private var down = false
    private var cancelled = false

    /// An ordinary key by its macOS key code (some PC keyboards send Right Ctrl this way).
    public init(keycode: Int) {
        keycodes = [Int64(keycode)]
        flag = 0
        plain = true
    }

    public init(key: Config.Hotkey) {
        plain = false
        switch key {
        case .rightOption: (keycodes, flag) = ([61], 0x80000)
        case .rightCommand: (keycodes, flag) = ([54], 0x100000)
        case .rightControl: (keycodes, flag) = ([62], 0x40000)
        // Many PC keyboards report Right Shift as Left Shift, so accept both.
        case .shift: (keycodes, flag) = ([56, 60], 0x20000)
        case .control: (keycodes, flag) = ([59, 62], 0x40000)
        }
    }

    public mutating func flagsChanged(keycode: Int64, flags: UInt64) -> Action? {
        if plain { return down ? cancel() : nil }
        guard keycodes.contains(keycode) else { return down ? cancel() : nil }
        let pressed = flags & flag != 0
        if pressed, !down {
            down = true
            cancelled = false
            return .start
        }
        if !pressed, down {
            down = false
            return cancelled ? nil : .stop
        }
        return nil
    }

    public mutating func keyDown(keycode: Int64) -> Action? {
        guard plain, keycodes.contains(keycode) else { return down ? cancel() : nil }
        guard !down else { return nil }   // auto-repeat
        down = true
        cancelled = false
        return .start
    }

    public mutating func keyUp(keycode: Int64) -> Action? {
        guard plain, keycodes.contains(keycode), down else { return nil }
        down = false
        return cancelled ? nil : .stop
    }

    private mutating func cancel() -> Action? {
        guard !cancelled else { return nil }
        cancelled = true
        return .cancel
    }
}
