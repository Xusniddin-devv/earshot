/// How summary mode calls the user's own `claude` CLI.
public enum SummaryPrompt {
    public static func arguments() -> [String] {
        ["-p", "--model", "haiku"]
    }

    public static func input(reply: String) -> String {
        "Summarize this reply from a coding assistant in 2 to 3 short spoken sentences for someone listening. Plain English, no markdown, no code.\n\n"
            + reply
    }

    /// `EARSHOT_INTERNAL=1` makes `earshot hook` ignore this run, so it never shows as a session.
    public static func environment(base: [String: String]) -> [String: String] {
        var env = base
        env["EARSHOT_INTERNAL"] = "1"
        return env
    }
}
