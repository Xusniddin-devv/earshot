/// Turns one key press into a talk-key setting, for `earshot set-key`.
public enum KeyChoice: Equatable {
    case modifier(Config.Hotkey)
    case keycode(Int)
    case rejected(String)

    public static func fromModifier(keycode: Int64) -> KeyChoice {
        switch keycode {
        case 61: .modifier(.rightOption)
        case 54: .modifier(.rightCommand)
        case 62: .modifier(.rightControl)
        case 56, 60: .modifier(.shift)
        case 59: .modifier(.control)
        case 58: .rejected("Left Option is used for typing symbols; try Right Option or another key")
        default: .rejected("that key can't be held to talk; try Right Option, Right Ctrl or an F-key")
        }
    }

    /// Ordinary keys are fine unless they type something.
    public static func fromKey(keycode: Int64) -> KeyChoice {
        // Letters, digits, punctuation, space, return, tab, delete, escape (macOS ANSI codes 0–53).
        if keycode <= 53 || (65...92).contains(keycode) {   // + keypad
            return .rejected("that key types text; pick an F-key or a spare key")
        }
        if [115, 116, 117, 119, 121, 123, 124, 125, 126].contains(keycode) {   // Home/End/Page/arrows
            return .rejected("that key moves the cursor; pick an F-key or a spare key")
        }
        return .keycode(Int(keycode))
    }

    public func apply(to config: inout Config) {
        switch self {
        case .modifier(let key):
            config.hotkey = key
            config.hotkeyKeycode = nil
        case .keycode(let code):
            config.hotkeyKeycode = code
        case .rejected:
            break
        }
    }
}
