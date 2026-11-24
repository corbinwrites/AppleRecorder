import Foundation
import WhisperKit

public func verifyWhisperAPIs() async throws {
    let config = WhisperKitConfig(model: "tiny")
    let kit = try await WhisperKit(config)
    let decodeOptions = DecodingOptions(
        wordTimestamps: false,
        promptTokens: [1, 2, 3],
        chunkingStrategy: .vad
    )
    let audioOptions = AudioInputOptions(audioLoadingMode: .incremental)
    let results = try await kit.transcribe(
        audioPath: "/tmp/nonexistent.wav",
        audioInputOptions: audioOptions,
        decodeOptions: decodeOptions
    )
    for seg in results.flatMap(\.segments) {
        _ = seg.start
        _ = seg.end
        _ = seg.text
    }
}
