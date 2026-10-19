import FluidAudio

/// Local English speech-to-text (Parakeet TDT v2).
public final class Transcriber {
    private let manager = AsrManager(config: .default)
    public private(set) var isReady = false

    public init() {}

    /// Downloads (first run) and loads the model.
    public func prepare() async throws {
        let models = try await AsrModels.downloadAndLoad(version: .v2)
        try await manager.loadModels(models)
        isReady = true
    }

    public func transcribe(_ samples: [Float]) async throws -> String {
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        return try await manager.transcribe(samples, decoderState: &state).text
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
