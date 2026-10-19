import AVFoundation

/// Records the default mic as 16 kHz mono Float32 (what Parakeet expects). Capped at 60 s.
/// Call from the main thread.
public final class Recorder {
    public static let sampleRate = 16_000.0
    private let maxSamples = Int(sampleRate * 60)
    private var engine = AVAudioEngine()
    private var recording = false
    private var observer: NSObjectProtocol?
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Recorder.sampleRate,
                                       channels: 1, interleaved: false)!
    private let lock = NSLock()
    private var samples: [Float] = []

    public init() {
        observe()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// When the input device changes (AirPods connect, a mic is unplugged) a prepared engine can
    /// keep the old one; prepare again so the next press records from the current default.
    private func observe() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                          object: engine, queue: .main) { [weak self] _ in
            guard let self, !self.recording else { return }
            self.warmUp()
        }
    }

    /// Opens the input device ahead of the first key press. `prepare()` does not start capture,
    /// so the mic indicator stays off until `start()`.
    public func warmUp() {
        _ = engine.inputNode.outputFormat(forBus: 0)
        engine.prepare()
    }

    public func start() throws {
        do {
            try begin()
        } catch {
            // A stale engine can fail to start after a device change; a fresh one uses the current input.
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            engine = AVAudioEngine()
            observe()
            try begin()
        }
        recording = true
    }

    private func begin() throws {
        lock.withLock { samples = [] }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: format, to: target) else {
            throw NSError(domain: "Earshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "no usable microphone"])
        }
        // A second tap on the same bus raises an NSException, so always clear the old one.
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.append(buffer, converter: converter)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    public func stop() -> [Float] {
        recording = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // stop() releases what prepare() set up; prepare again so the next press starts fast (~48 vs ~84 ms).
        engine.prepare()
        return lock.withLock { samples }
    }

    private func append(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter) {
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let data = out.floatChannelData?[0] else { return }
        let chunk = Array(UnsafeBufferPointer(start: data, count: Int(out.frameLength)))
        lock.withLock {
            if samples.count < maxSamples { samples.append(contentsOf: chunk.prefix(maxSamples - samples.count)) }
        }
    }
}
