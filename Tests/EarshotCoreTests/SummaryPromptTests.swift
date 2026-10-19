import Testing
@testable import EarshotCore

@Test func summaryArgsExact() {
    #expect(SummaryPrompt.arguments() == ["-p", "--model", "haiku"])
}

@Test func summaryInputPrefixesReply() {
    #expect(SummaryPrompt.input(reply: "Fixed the bug.") ==
        "Summarize this reply from a coding assistant in 2 to 3 short spoken sentences for someone listening. Plain English, no markdown, no code.\n\nFixed the bug.")
}

@Test func summaryEnvMarksInternal() {
    let env = SummaryPrompt.environment(base: ["PATH": "/bin"])
    #expect(env["EARSHOT_INTERNAL"] == "1" && env["PATH"] == "/bin")
}
