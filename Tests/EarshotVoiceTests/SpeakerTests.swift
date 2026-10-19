import Testing
@testable import EarshotVoice

@MainActor
@Test func speakerReportsFinishWhenNothingToSay() {
    let s = Speaker(voice: "af_heart", speed: 1)
    var finished = 0
    s.onFinish = { finished += 1 }
    s.speak(chunks: [])            // e.g. claude -p returned an empty summary
    #expect(finished == 1 && !s.isPlaying)
    s.speak(chunks: ["Hello."])    // model not loaded yet
    #expect(finished == 2 && !s.isPlaying)
}

@MainActor
@Test func stopLeavesAudioEngineIdle() {
    let s = Speaker(voice: "af_heart", speed: 1)
    s.stop()
    #expect(!s.engineRunning)
}
