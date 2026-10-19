import AVFoundation
import FluidAudio
import Foundation

/// Local Kokoro voice. Synthesizes chunk n+1 while chunk n plays. Use from the main thread.
public final class Speaker {
    public private(set) var isReady = false
    public private(set) var isPlaying = false
    public var onFinish: (() -> Void)?

    private let voice: String
    private let speed: Float
    private let manager: KokoroAneManager
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
    private var task: Task<Void, Never>?
    /// Bumped on every speak/stop so callbacks from old playback are ignored.
    private var generation = 0

    public init(voice: String, speed: Double) {
        self.voice = voice
        self.speed = Float(speed)
        manager = KokoroAneManager(defaultVoice: voice, version: .v3)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    /// Downloads (first run) and loads the model.
    public func prepare() async throws {
        try await manager.initialize(preloadVoices: [voice])
        await MainActor.run { isReady = true }
    }

    var engineRunning: Bool { engine.isRunning }

    /// Plays `chunks`. Every path that ends — played, nothing to say, not ready, failure — calls `onFinish` once.
    public func speak(chunks: [String]) {
        stop()
        guard isReady, !chunks.isEmpty else {
            finish()
            return
        }
        generation += 1
        let gen = generation
        isPlaying = true
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            finish()
            return
        }
        player.play()
        task = Task { [weak self, manager, voice, speed] in
            for (i, chunk) in chunks.enumerated() {
                guard !Task.isCancelled else { return }
                let last = i == chunks.count - 1
                // A failed chunk schedules nothing; if it was the last, schedule() still ends playback.
                let samples = (try? await manager.synthesizeDetailed(text: chunk, voice: voice, speed: speed))?.samples ?? []
                await MainActor.run { self?.schedule(samples, last: last, gen: gen) }
            }
        }
    }

    func synthesizeOnly(_ text: String) async throws -> KokoroAneSynthesisResult {
        try await manager.synthesizeDetailed(text: text, voice: voice, speed: speed)
    }

    public func stop() {
        generation += 1
        task?.cancel()
        task = nil
        player.stop()
        // A running output engine keeps CoreAudio awake (and can block idle sleep).
        engine.pause()
        isPlaying = false
    }

    private func schedule(_ samples: [Float], last: Bool, gen: Int) {
        guard gen == generation, !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else {
            if last, gen == generation { finish() }
            return
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard last else { return }
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                self.finish()
            }
        }
    }

    private func finish() {
        isPlaying = false
        engine.pause()
        onFinish?()
    }
}

extension Speaker {
    /// Synthesizes without playing; used by `earshot selftest`.
    public func render(_ text: String) async throws -> (samples: [Float], sampleRate: Int) {
        let r = try await synthesizeOnly(text)
        return (r.samples, r.sampleRate)
    }
}
