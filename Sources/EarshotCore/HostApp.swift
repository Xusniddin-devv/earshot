/// The app macOS attributes Earshot's permissions to: the terminal it runs in.
public enum HostApp {
    public static func name(env: [String: String]) -> String {
        switch env["TERM_PROGRAM"] {
        case "Apple_Terminal": "Terminal"
        case "iTerm.app": "iTerm2"
        default: "your terminal app"
        }
    }
}
