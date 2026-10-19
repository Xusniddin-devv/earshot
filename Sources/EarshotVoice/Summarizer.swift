import EarshotCore
import Foundation

/// Runs the user's own `claude -p` to summarize a reply. Earshot never sees credentials.
public enum Summarizer {
    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    public static func summarize(_ reply: String, timeout: TimeInterval = 60,
                                 command: [String] = ["/usr/bin/env", "claude"]) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global().async {
                do {
                    cont.resume(returning: try run(reply, timeout: timeout, command: command))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private static func run(_ reply: String, timeout: TimeInterval, command: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: command[0])
        p.arguments = Array(command.dropFirst()) + SummaryPrompt.arguments()
        p.environment = SummaryPrompt.environment(base: ProcessInfo.processInfo.environment)
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = stderr
        // A child that exits without reading its input must not kill the dashboard.
        signal(SIGPIPE, SIG_IGN)
        try p.run()

        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        // Write on another queue: a reply over the 64 KB pipe buffer blocks until the child reads.
        let input = Data(SummaryPrompt.input(reply: reply).utf8)
        let writer = stdin.fileHandleForWriting
        DispatchQueue.global().async {
            try? writer.write(contentsOf: input)
            try? writer.close()
        }
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()

        if p.terminationReason == .uncaughtSignal { throw Failure(description: "claude timed out") }
        if p.terminationStatus == 127 { throw Failure(description: "claude not found on PATH") }
        guard p.terminationStatus == 0 else {
            let first = String(decoding: err, as: UTF8.self).split(separator: "\n").first.map(String.init)
            throw Failure(description: first ?? "claude exited with \(p.terminationStatus)")
        }
        return String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
