import Darwin
import Foundation

enum Key: Equatable {
    case up, down, enter, char(Character), quit
}

/// Raw-mode, alternate-screen terminal I/O for the dashboard.
enum TTY {
    private static var original = termios()
    private static var active = false

    static func enter() {
        tcgetattr(STDIN_FILENO, &original)
        var raw = original
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG | IEXTEN)
        raw.c_iflag &= ~tcflag_t(IXON | ICRNL)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        write("\u{1B}[?1049h\u{1B}[?25l")
        active = true
    }

    static func leave() {
        guard active else { return }
        active = false
        write("\u{1B}[?25h\u{1B}[?1049l")
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
    }

    static var size: (rows: Int, cols: Int) {
        var w = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) == 0, w.ws_col > 0 else { return (24, 80) }
        return (Int(w.ws_row), Int(w.ws_col))
    }

    static func write(_ s: String) {
        FileHandle.standardOutput.write(Data(s.utf8))
    }

    /// Draws full frame. `highlight` is the line index shown in inverse video.
    static func draw(_ lines: [String], highlight: Int?) {
        var out = "\u{1B}[H"
        for (i, line) in lines.enumerated() {
            out += i == highlight ? "\u{1B}[7m\(line)\u{1B}[0m" : line
            out += "\u{1B}[K\r\n"
        }
        out += "\u{1B}[J"
        write(out)
    }

    /// Decodes the bytes of one read() into keys.
    static func keys(_ bytes: [UInt8]) -> [Key] {
        var out: [Key] = []
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if b == 0x1B, i + 2 < bytes.count, bytes[i + 1] == 0x5B {
                if bytes[i + 2] == 0x41 { out.append(.up) }
                if bytes[i + 2] == 0x42 { out.append(.down) }
                i += 3
                continue
            }
            switch b {
            case 0x0D, 0x0A: out.append(.enter)
            case 0x03, 0x04: out.append(.quit)
            default:
                if let s = String(bytes: [b], encoding: .utf8), let c = s.first { out.append(.char(c)) }
            }
            i += 1
        }
        return out
    }
}
