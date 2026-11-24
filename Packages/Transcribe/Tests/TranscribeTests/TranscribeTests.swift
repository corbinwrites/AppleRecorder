import AVFoundation
import Foundation
import Testing
import Capture
import Core
import CoreTestSupport
@testable import Transcribe

private enum TestFailure: Error, Sendable { case engine }

private actor RecordingEngine: TranscriptionEngine {
    private var paths: [URL] = []
    private let outputs: [[RawSegment]]
    private let shouldFail: Bool

    init(outputs: [[RawSegment]], shouldFail: Bool = false) {
        self.outputs = outputs
        self.shouldFail = shouldFail
    }

    func transcribe(audioFile: URL, vocabulary: [String], onProgress: @escaping @Sendable (Double) -> Void) async throws -> [RawSegment] {
        paths.append(audioFile)
        onProgress(0.5)
        if shouldFail { throw TestFailure.engine }
        return outputs[min(paths.count - 1, outputs.count - 1)]
    }

    func recordedPaths() -> [URL] { paths }
}

private func writeAudio(_ url: URL, frequencies: [Double], seconds: Double = 1, sampleRate: Double = 48_000) throws {
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: frequencies.count,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings)
    guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(frequencies.count)) else {
        throw TranscribeError.invalidAudioFormat
    }
    let frameCount = AVAudioFrameCount(seconds * sampleRate)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount), let samples = buffer.floatChannelData else {
        throw TranscribeError.invalidAudioFormat
    }
    buffer.frameLength = frameCount
    for channel in frequencies.indices {
        for frame in 0..<Int(frameCount) {
            samples[channel][frame] = 0.5 * Float(sin(2 * .pi * frequencies[channel] * Double(frame) / sampleRate))
        }
    }
    try file.write(from: buffer)
}

private func readAudio(_ url: URL) throws -> (samples: [Float], sampleRate: Double, channels: Int) {
    let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
    let frameCount = AVAudioFrameCount(file.length)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount), let channelData = buffer.floatChannelData else {
        throw TranscribeError.invalidAudioFormat
    }
    try file.read(into: buffer)
    return (Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength))), file.processingFormat.sampleRate, Int(file.processingFormat.channelCount))
}

private func spectralPower(_ samples: [Float], frequency: Double, sampleRate: Double) -> Double {
    let coefficient = 2 * cos(2 * .pi * frequency / sampleRate)
    var first = 0.0, second = 0.0
    for sample in samples {
        let current = Double(sample) + coefficient * first - second
        second = first
        first = current
    }
    let count = Double(max(1, samples.count))
    return (first * first + second * second - coefficient * first * second) / (count * count)
}

@Suite struct TranscribePureTests {
    @Test func textCleaner() {
        #expect(TextCleaner.clean("<|startoftranscript|><|0.00|> Hello  world <|2.50|>") == "Hello world")
        #expect(TextCleaner.clean("  a\n b ") == "a b")
        #expect(TextCleaner.clean("") == "")
        #expect(TextCleaner.clean("ordinary text") == "ordinary text")
    }

    @Test func vocabularyPrompt() {
        #expect(VocabularyPrompt.make(terms: ["Soteriology", "soteriology", "Talbot", ""]) == "Vocabulary: Soteriology, Talbot.")
        #expect(VocabularyPrompt.make(terms: []) == nil)
        #expect((VocabularyPrompt.make(terms: (0..<100).map { "long-term-\($0)-with-some-extra-text" })?.count ?? 0) <= 224)
        #expect(VocabularyPrompt.make(terms: ["   "]) == nil)
    }

    @Test func transcriptMergeOrdersLabelsAndCleansText() {
        let me = [RawSegment(start: 5, end: 6, text: " B "), RawSegment(start: 0, end: 1, text: "A\nnow"), RawSegment(start: 2, end: 2.5, text: "  ")]
        let them = [RawSegment(start: 2, end: 3, text: " C "), RawSegment(start: 0, end: 0.5, text: "Equal")]
        let merged = TranscriptMerger.merge(me: me, them: them)
        #expect(merged.map(\.text) == ["A now", "Equal", "C", "B"])
        #expect(merged.map(\.speaker) == [.me, .them, .them, .me])
        #expect(TranscriptMerger.unlabeled(me).map(\.text) == ["A now", "B"])
        #expect(TranscriptMerger.unlabeled(me).allSatisfy { $0.speaker == nil })
    }

    @Test func hallucinationFilter() {
        let filter = HallucinationFilter()
        let repeats = Array(repeating: RawSegment(start: 0, end: 1, text: "Thank you."), count: 5)
        #expect(filter.apply(repeats, isSilent: { _, _ in false }).count == 2)
        let loop = Array(repeating: RawSegment(start: 0, end: 1, text: "I'm going to go"), count: 30)
        #expect(filter.apply(loop, isSilent: { _, _ in false }).count == 2)
        #expect(filter.apply([repeats[0]], isSilent: { _, _ in true }).isEmpty)
        #expect(filter.apply([repeats[0]], isSilent: { _, _ in false }).count == 1)
        #expect(filter.apply([RawSegment(start: 0, end: 1, text: "You")], isSilent: { _, _ in true }).isEmpty)
        #expect(filter.apply([RawSegment(start: 0, end: 1, text: "Yes."), RawSegment(start: 1, end: 2, text: "Yes.")], isSilent: { _, _ in false }).count == 2)
        let separated = [RawSegment(start: 0, end: 1, text: "same"), RawSegment(start: 1, end: 2, text: "different"), RawSegment(start: 2, end: 3, text: "same")]
        #expect(filter.apply(separated, isSilent: { _, _ in false }).count == 3)
        #expect(filter.apply([], isSilent: { _, _ in false }).isEmpty)
    }
}

@Suite struct AudioTranscribeTests {
    @Test func channelExtractorSelectsAndMixesChannels() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("stereo.caf")
        try writeAudio(source, frequencies: [440, 880])
        let mic = try ChannelExtractor.extract(.channel(0), from: source, into: directory)
        let app = try ChannelExtractor.extract(.channel(1), from: source, into: directory)
        let mixed = try ChannelExtractor.extract(.mixdown, from: source, into: directory)
        let micData = try readAudio(mic), appData = try readAudio(app), mixedData = try readAudio(mixed)
        #expect(micData.sampleRate == 16_000 && micData.channels == 1)
        #expect(appData.sampleRate == 16_000 && appData.channels == 1)
        #expect(abs(Double(micData.samples.count) / 16_000 - 1) < 0.05)
        #expect(spectralPower(micData.samples, frequency: 440, sampleRate: 16_000) > 100 * spectralPower(micData.samples, frequency: 880, sampleRate: 16_000))
        #expect(spectralPower(appData.samples, frequency: 880, sampleRate: 16_000) > 100 * spectralPower(appData.samples, frequency: 440, sampleRate: 16_000))
        #expect(spectralPower(mixedData.samples, frequency: 440, sampleRate: 16_000) > 0)
        #expect(spectralPower(mixedData.samples, frequency: 880, sampleRate: 16_000) > 0)
        #expect(throws: TranscribeError.invalidChannel(2)) { try ChannelExtractor.extract(.channel(2), from: source, into: directory) }
        let mono = directory.appendingPathComponent("mono.caf")
        try writeAudio(mono, frequencies: [440])
        #expect(try ChannelExtractor.extract(.channel(0), from: mono, into: directory).pathExtension == "wav")
    }

    @Test func silenceMapRecognizesQuietWindows() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tone-silence-tone.caf")
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1) else { throw TranscribeError.invalidAudioFormat }
        for second in 0..<3 {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000), let data = buffer.floatChannelData else { throw TranscribeError.invalidAudioFormat }
            buffer.frameLength = 16_000
            for frame in 0..<16_000 { data[0][frame] = second == 1 ? 0 : 0.5 * sin(Float(2 * Double.pi * 440 * Double(frame) / 16_000)) }
            try file.write(from: buffer)
        }
        let map = try SilenceMap.build(from: url)
        #expect(map.isSilent(1.1, 1.9))
        #expect(!map.isSilent(0.1, 0.9))
        #expect(!map.isSilent(0.5, 1.5))
    }

    @Test func orchestratorTranscribesAndCleansTemporaryFiles() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("stereo.caf")
        try writeAudio(source, frequencies: [440, 880])
        let engine = RecordingEngine(outputs: [[RawSegment(start: 1, end: 2, text: "Me said hello")], [RawSegment(start: 1, end: 2, text: "Them replied")]])
        let result = try await TranscribeOrchestrator(engine: engine).transcribe(audioFile: source, mode: .appAndMic, tempDirectory: directory)
        #expect(result.map(\.text) == ["Me said hello", "Them replied"])
        #expect(result.map(\.speaker) == [.me, .them])
        let paths = await engine.recordedPaths()
        #expect(paths.map(\.lastPathComponent).contains(where: { $0.contains("channel-0") }))
        #expect(paths.map(\.lastPathComponent).contains(where: { $0.contains("channel-1") }))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["stereo.caf"])
    }

    @Test func orchestratorMonoUnlabeledAndEngineErrorsAreCleaned() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mono = directory.appendingPathComponent("mono.caf")
        try writeAudio(mono, frequencies: [440])
        let engine = RecordingEngine(outputs: [[RawSegment(start: 0, end: 1, text: " words ")]])
        let result = try await TranscribeOrchestrator(engine: engine).transcribe(audioFile: mono, mode: .micOnly, tempDirectory: directory)
        #expect(result.count == 1 && result[0].text == "words" && result[0].speaker == nil)
        #expect(await engine.recordedPaths().count == 1)
        let failing = RecordingEngine(outputs: [], shouldFail: true)
        do {
            _ = try await TranscribeOrchestrator(engine: failing).transcribe(audioFile: mono, mode: .micOnly, tempDirectory: directory)
            Issue.record("Expected engine failure")
        } catch let error as TranscribeError {
            #expect(error == .engineFailed(stage: "transcribing"))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["mono.caf"])
    }
}

@Suite struct TranscribeIntegrationTests {
    @Test func gatedSpeechIntegration() async throws {
        guard ProcessInfo.processInfo.environment["AR_INTEGRATION"] == "1" else { return }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let speech = directory.appendingPathComponent("speech.aiff")
        let caf = directory.appendingPathComponent("speech.caf")
        let audio = directory.appendingPathComponent("speech.m4a")
        try run("/usr/bin/say", ["-o", speech.path, "The quarterly budget review is on Friday and Sarah owns the action item."])
        try run("/usr/bin/afconvert", ["-f", "caff", "-d", "LEI16@48000", speech.path, caf.path])
        _ = try Finalizer.finalize(mic: TrackInput(url: caf, startNanos: 1), app: nil, to: audio)
        let engine = WhisperEngine(modelName: "tiny")
        let segments = try await TranscribeOrchestrator(engine: engine).transcribe(audioFile: audio, mode: .micOnly, tempDirectory: directory)
        await engine.unload()
        let transcript = segments.map(\.text).joined(separator: " ").lowercased()
        let keywords = ["quarterly", "budget", "friday", "sarah", "action"].filter { transcript.contains($0) }
        #expect(keywords.count >= 3)
    }

    private func run(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw TranscribeError.engineFailed(stage: "integration setup") }
    }
}
