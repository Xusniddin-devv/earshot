import Testing
@testable import EarshotCore

@Test func codeBlockBecomesMarker() {
    #expect(SpeechText.chunks(from: "Fixed it.\n```swift\nlet a = 1\nlet b = 2\n```\nDone.")
        == ["Fixed it.", "Code block, 2 lines.", "Done."])
}

@Test func singleLineCodeBlock() {
    #expect(SpeechText.chunks(from: "```\nls\n```") == ["Code block, 1 line."])
}

@Test func pathsShortened() {
    #expect(SpeechText.chunks(from: "Edited `src/auth/login.ts` and ~/dev/store/api/app.py.")
        == ["Edited login.ts and app.py."])
}

@Test func linksAndUrls() {
    #expect(SpeechText.chunks(from: "See [docs](https://x.io) or https://y.io/z.") == ["See docs or link."])
}

@Test func markdownStripped() {
    #expect(SpeechText.chunks(from: "## Summary\n- **Tests** pass\n- Build _ok_\n> quoted\n1. first")
        == ["Summary", "Tests pass", "Build ok", "quoted", "first"])
}

@Test func tableRowsRead() {
    #expect(SpeechText.chunks(from: "| a | b |\n|---|---|\n| 1 | 2 |") == ["a, b", "1, 2"])
}

@Test func sentencesSplit() {
    #expect(SpeechText.chunks(from: "One. Two! Three? Four") == ["One.", "Two!", "Three?", "Four"])
}

@Test func chunksNeverExceedLimit() {
    let words = (0..<5000).map { "word\($0)" }
    let chunks = SpeechText.chunks(from: words.joined(separator: " "))
    #expect(chunks.allSatisfy { $0.count <= 280 })
    #expect(chunks.joined(separator: " ").split(separator: " ").map(String.init) == words)
}

@Test func emptyInput() {
    #expect(SpeechText.chunks(from: "").isEmpty)
    #expect(SpeechText.chunks(from: "```\n```") == ["Code block, 0 lines."])
}

@Test func unclosedFenceStillMarker() {
    #expect(SpeechText.chunks(from: "Here:\n```\na\nb") == ["Here:", "Code block, 2 lines."])
}
