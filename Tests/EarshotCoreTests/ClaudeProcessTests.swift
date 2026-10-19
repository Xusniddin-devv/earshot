import Testing
@testable import EarshotCore

@Test func findsTTYsRunningInteractiveClaude() {
    let ps = """
    ??       /Users/x/.local/bin/claude
    ttys000  claude
    ttys001  /Users/x/.local/bin/claude
    ttys005  claude bg-spare
    ttys006  -zsh
    ttys007  claudette

    """
    #expect(ClaudeProcesses.ttys(psOutput: ps) == ["/dev/ttys000", "/dev/ttys001"])
}

@Test func backgroundJobClientTabCounts() {
    // Tab attached to a background job: plain `claude` client; the job's own pty shows `claude bg-spare`.
    let ps = """
    ttys002  claude
    ttys011  claude bg-spare
    """
    #expect(ClaudeProcesses.ttys(psOutput: ps) == ["/dev/ttys002"])
}
