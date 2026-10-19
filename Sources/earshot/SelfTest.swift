import AVFoundation
import EarshotCore
import EarshotVoice
import Foundation

/// `earshot selftest`: text → Kokoro speech → Parakeet text, with no audio played.
/// Proves both models load and the voice is intelligible.
func runSelfTest() async {
    let config = Config.load(Paths.live.configFile)
    let text = "Webapp finished. I fixed the login bug and all tests pass."
    do {
        let speaker = Speaker(voice: config.voice, speed: config.speed)
        try await speaker.prepare()
        let audio = try await speaker.render(text)
        let transcriber = Transcriber()
        try await transcriber.prepare()
        let heard = try await transcriber.transcribe(resample(audio.samples, from: audio.sampleRate, to: 16_000))
        print("said:  \(text)")
        print("heard: \(heard)")
    } catch {
        print("selftest failed: \(error)")
        exit(1)
    }
}

private func resample(_ samples: [Float], from: Int, to: Int) -> [Float] {
    guard from != to, !samples.isEmpty else { return samples }
    let ratio = Double(from) / Double(to)
    let count = Int(Double(samples.count) / ratio)
    return (0..<count).map { i in
        let x = Double(i) * ratio
        let j = Int(x)
        let f = Float(x - Double(j))
        let a = samples[j], b = samples[min(j + 1, samples.count - 1)]
        return a + (b - a) * f
    }
}
