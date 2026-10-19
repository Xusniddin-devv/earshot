import Testing
@testable import EarshotVoice

@Test func childThatIgnoresInputDoesNotKillUs() async {
    // 1 MB reply into a child that exits without reading: must throw, not die of SIGPIPE.
    let reply = String(repeating: "word ", count: 200_000)
    await #expect(throws: Summarizer.Failure.self) {
        _ = try await Summarizer.summarize(reply, timeout: 5, command: ["/bin/sh", "-c", "exit 3"])
    }
}

@Test func missingClaudeGivesClearMessage() async {
    do {
        _ = try await Summarizer.summarize("hi", timeout: 5, command: ["/bin/sh", "-c", "exit 127"])
        Issue.record("expected failure")
    } catch let f as Summarizer.Failure {
        #expect(f.description == "claude not found on PATH")
    } catch {
        Issue.record("wrong error \(error)")
    }
}

@Test func stalledChildTimesOut() async {
    let start = ContinuousClock.now
    await #expect(throws: Summarizer.Failure.self) {
        _ = try await Summarizer.summarize(String(repeating: "x", count: 200_000), timeout: 1,
                                           command: ["/bin/sh", "-c", "sleep 30"])
    }
    #expect(ContinuousClock.now - start < .seconds(5))
}

@Test func returnsTrimmedOutput() async throws {
    let out = try await Summarizer.summarize("ignored", timeout: 5, command: ["/bin/sh", "-c", "cat >/dev/null; echo '  short summary  '"])
    #expect(out == "short summary")
}
