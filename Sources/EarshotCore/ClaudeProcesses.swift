import Foundation

/// Which TTYs have an interactive `claude` process right now.
/// TTY names are reused (after a reboot, a closed tab), so a TTY alone is not proof of a session.
public enum ClaudeProcesses {
    /// Parses `ps -A -o tty=,comm=` output.
    public static func ttys(psOutput: String) -> Set<String> {
        var out = Set<String>()
        for line in psOutput.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 2, parts[0] != "??" else { continue }
            if parts[1].split(separator: "/").last == "claude" { out.insert("/dev/" + parts[0]) }
        }
        return out
    }

    public static func live() -> Set<String> {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-A", "-o", "tty=,comm="]
        let pipe = Pipe()
        p.standardOutput = pipe
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return ttys(psOutput: String(decoding: data, as: UTF8.self))
    }
}
