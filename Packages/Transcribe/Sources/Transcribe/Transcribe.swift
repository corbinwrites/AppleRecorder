import AVFoundation
import Foundation
import Core
import WhisperKit

public enum ChannelSelection: Sendable, Equatable { case channel(Int), mixdown }

public enum TranscribeError: Error, Sendable, Equatable {
    case engineFailed(stage: String)
    case invalidChannel(Int)
    case invalidAudioFormat
    case silenceReadFailed(String)
}

public enum ChannelExtractor {
    public static func extract(_ selection: ChannelSelection, from source: URL, into directory: URL) throws -> URL {
        let input = try AVAudioFile(forReading: source, commonFormat: .pcmFormatFloat32, interleaved: false)
        let channels = Int(input.processingFormat.channelCount)
        let selectedChannel: Int?
        switch selection {
        case .channel(let index):
            guard index >= 0, index < channels else { throw TranscribeError.invalidChannel(index) }
            selectedChannel = index
        case .mixdown:
            selectedChannel = nil
        }
        let name = "\(source.deletingPathExtension().lastPathComponent)-\(selection.fileSuffix).wav"
        var suffix = 1
        var outputURL = directory.appendingPathComponent(name)
        while FileManager.default.fileExists(atPath: outputURL.path) {
            suffix += 1
            outputURL = directory.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent)-\(selection.fileSuffix)-\(suffix).wav")
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let output = try AVAudioFile(forWriting: outputURL, settings: settings)
        var keepOutput = false
        defer { if !keepOutput { try? FileManager.default.removeItem(at: outputURL) } }
        guard let converter = AVAudioConverter(from: input.processingFormat, to: output.processingFormat) else {
            throw TranscribeError.invalidAudioFormat
        }
        if let selectedChannel { converter.channelMap = [NSNumber(value: selectedChannel)] }
        else { converter.downmix = true }
        let inputCapacity = AVAudioFrameCount(max(1, input.processingFormat.sampleRate.rounded()))
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: inputCapacity) else {
            throw TranscribeError.invalidAudioFormat
        }
        let outputCapacity = AVAudioFrameCount(17_024)
        var conversionError: NSError?
        var inputReadError: (any Error)?
        var endOfInput = false
        var inputFramesRead: Int64 = 0
        var status: AVAudioConverterOutputStatus = .haveData
        while status != .endOfStream {
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: output.processingFormat, frameCapacity: outputCapacity) else {
                throw TranscribeError.invalidAudioFormat
            }
            status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
                if endOfInput || inputFramesRead >= input.length {
                    endOfInput = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    try input.read(into: inputBuffer)
                    if inputBuffer.frameLength == 0 {
                        endOfInput = true
                        inputStatus.pointee = .endOfStream
                        return nil
                    }
                    inputFramesRead += Int64(inputBuffer.frameLength)
                    if let selectedChannel, selectedChannel >= Int(inputBuffer.format.channelCount) {
                        inputReadError = TranscribeError.invalidChannel(selectedChannel)
                        endOfInput = true
                        inputStatus.pointee = .endOfStream
                        return nil
                    }
                    inputStatus.pointee = .haveData
                    return inputBuffer
                } catch {
                    inputReadError = error
                    endOfInput = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
            }
            if let inputReadError { throw inputReadError }
            if let conversionError { throw conversionError }
            if outputBuffer.frameLength > 0 { try output.write(from: outputBuffer) }
            if status == .error { throw TranscribeError.invalidAudioFormat }
        }
        keepOutput = true
        return outputURL
    }
}

private extension ChannelSelection {
    var fileSuffix: String {
        switch self { case .channel(let value): "channel-\(value)"; case .mixdown: "mixdown" }
    }
}

public enum TextCleaner {
    public static func clean(_ text: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"<\|[^|]*\|>"#) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let stripped = expression.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        return stripped.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

public enum VocabularyPrompt {
    public static func make(terms: [String]) -> String? {
        var accepted: [String] = []
        var seen: Set<String> = []
        for rawTerm in terms {
            let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = term.lowercased()
            guard !term.isEmpty, seen.insert(key).inserted else { continue }
            let candidate = "Vocabulary: \((accepted + [term]).joined(separator: ", "))."
            guard candidate.count <= 224 else { break }
            accepted.append(term)
        }
        return accepted.isEmpty ? nil : "Vocabulary: \(accepted.joined(separator: ", "))."
    }
}

public enum TranscriptMerger {
    private struct LabeledSegment {
        var segment: TranscriptSegment
        var ordering: Int
    }

    public static func merge(me: [RawSegment], them: [RawSegment]) -> [TranscriptSegment] {
        let combined = me.map { ($0, Speaker.me, 0) } + them.map { ($0, Speaker.them, 1) }
        let labeled: [LabeledSegment] = combined.enumerated().compactMap { index, item in
            let text = cleanedSegmentText(item.0.text)
            guard !text.isEmpty else { return nil }
            return LabeledSegment(segment: TranscriptSegment(start: item.0.start, end: item.0.end, text: text, speaker: item.1), ordering: index)
        }
        return labeled.sorted {
            if $0.segment.start != $1.segment.start { return $0.segment.start < $1.segment.start }
            if $0.segment.speaker != $1.segment.speaker { return $0.segment.speaker == .me }
            return $0.ordering < $1.ordering
        }.map(\.segment)
    }

    public static func unlabeled(_ segments: [RawSegment]) -> [TranscriptSegment] {
        segments.enumerated().compactMap { index, segment -> (Int, TranscriptSegment)? in
            let text = cleanedSegmentText(segment.text)
            guard !text.isEmpty else { return nil }
            return (index, TranscriptSegment(start: segment.start, end: segment.end, text: text))
        }.sorted {
            if $0.1.start != $1.1.start { return $0.1.start < $1.1.start }
            return $0.0 < $1.0
        }.map(\.1)
    }

    private static func cleanedSegmentText(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

public struct HallucinationFilter: Sendable {
    public var maxConsecutiveRepeats = 2
    public var phantomPhrases: Set<String> = ["thank you", "thanks for watching", "thank you for watching", "subtitles by the amara.org community", "you", "bye", "please subscribe", "like and subscribe"]
    public init() {}

    public func apply(_ segments: [RawSegment], isSilent: @Sendable (_ start: Double, _ end: Double) -> Bool) -> [RawSegment] {
        var results: [RawSegment] = []
        var previous: String?
        var repeatCount = 0
        for segment in segments {
            let normalized = Self.normalize(segment.text)
            if isSilent(segment.start, segment.end), phantomPhrases.contains(normalized) { continue }
            if normalized == previous { repeatCount += 1 } else { previous = normalized; repeatCount = 1 }
            if repeatCount <= max(0, maxConsecutiveRepeats) { results.append(segment) }
        }
        return results
    }

    private static func normalize(_ text: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"[^\p{L}\p{N} ]+"#) else { return text.lowercased() }
        let lower = text.lowercased()
        let stripped = expression.stringByReplacingMatches(in: lower, range: NSRange(lower.startIndex..., in: lower), withTemplate: " ")
        return stripped.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

public struct SilenceMap: Sendable {
    private let windowSeconds: Double
    private let silentWindows: [Bool]

    private init(windowSeconds: Double, silentWindows: [Bool]) {
        self.windowSeconds = windowSeconds
        self.silentWindows = silentWindows
    }

    public static func build(from wav16kMono: URL, windowSeconds: Double = 0.1, thresholdDBFS: Double = -50) throws -> SilenceMap {
        guard windowSeconds > 0, let file = try? AVAudioFile(forReading: wav16kMono, commonFormat: .pcmFormatFloat32, interleaved: false),
              file.processingFormat.channelCount > 0, file.processingFormat.sampleRate > 0 else {
            throw TranscribeError.silenceReadFailed("invalid audio file")
        }
        let framesPerWindow = max(1, Int((windowSeconds * file.processingFormat.sampleRate).rounded()))
        let windowCount = Int((Double(file.length) / Double(framesPerWindow)).rounded(.up))
        var squares = [Double](repeating: 0, count: windowCount)
        var counts = [Int](repeating: 0, count: windowCount)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(framesPerWindow)) else {
            throw TranscribeError.silenceReadFailed("could not allocate audio buffer")
        }
        var samplesRead = 0
        while samplesRead < file.length {
            do { try file.read(into: buffer) }
            catch { throw TranscribeError.silenceReadFailed(error.localizedDescription) }
            if buffer.frameLength == 0 { break }
            guard let samples = buffer.floatChannelData else { throw TranscribeError.silenceReadFailed("audio samples unavailable") }
            let frameCount = Int(buffer.frameLength)
            let startFrame = samplesRead
            samplesRead += frameCount
            for frame in 0..<frameCount {
                let index = min(windowCount - 1, (startFrame + frame) / framesPerWindow)
                for channel in 0..<Int(file.processingFormat.channelCount) {
                    let sample = Double(samples[channel][frame])
                    squares[index] += sample * sample
                    counts[index] += 1
                }
            }
        }
        let silent = squares.indices.map { index -> Bool in
            let rms = sqrt(squares[index] / Double(max(1, counts[index])))
            let dbfs = 20 * log10(max(rms, 1e-12))
            return dbfs < thresholdDBFS
        }
        return SilenceMap(windowSeconds: windowSeconds, silentWindows: silent)
    }

    public func isSilent(_ start: Double, _ end: Double) -> Bool {
        guard !silentWindows.isEmpty, end > start else { return false }
        let first = max(0, Int(floor(start / windowSeconds)))
        let last = min(silentWindows.count, Int(ceil(end / windowSeconds)))
        guard last > first else { return false }
        let range = silentWindows[first..<last]
        return Double(range.filter { $0 }.count) / Double(range.count) >= 0.9
    }
}

public actor WhisperEngine: TranscriptionEngine {
    public let modelName: String
    private var kit: WhisperKit?

    public init(modelName: String) { self.modelName = modelName }

    public func transcribe(audioFile: URL, vocabulary: [String], onProgress: @escaping @Sendable (Double) -> Void) async throws -> [RawSegment] {
        let engine = try await load()
        var options = DecodingOptions(wordTimestamps: false, chunkingStrategy: .vad)
        if let prompt = VocabularyPrompt.make(terms: vocabulary), let tokenizer = engine.tokenizer {
            options.promptTokens = tokenizer.encode(text: " " + prompt)
        }
        let audioDuration: Double
        if let file = try? AVAudioFile(forReading: audioFile) {
            audioDuration = Double(file.length) / file.processingFormat.sampleRate
        } else { audioDuration = 0 }
        let windowCount = max(1, Int(ceil(audioDuration / 30)))
        onProgress(0)
        let results = try await engine.transcribe(audioPath: audioFile.path, decodeOptions: options) { progress in
            let fraction = min(1, Double(progress.windowId + 1) / Double(windowCount))
            onProgress(fraction)
            return nil
        }
        onProgress(1)
        return results.flatMap { $0.segments }.compactMap { segment in
            let text = TextCleaner.clean(segment.text)
            return text.isEmpty ? nil : RawSegment(start: Double(segment.start), end: Double(segment.end), text: text)
        }
    }

    public func unload() { kit = nil }

    private func load() async throws -> WhisperKit {
        if let kit { return kit }
        let loaded = try await WhisperKit(WhisperKitConfig(model: modelName))
        kit = loaded
        return loaded
    }
}

public enum ModelCatalog {
    public static let all: [(name: String, approxMB: Int)] = [("tiny", 66), ("base", 145), ("small", 480), ("large-v3-v20240930_626MB", 626)]
}

public struct TranscribeOrchestrator: Sendable {
    private let engine: any TranscriptionEngine
    public init(engine: any TranscriptionEngine) { self.engine = engine }

    public func transcribe(audioFile: URL, mode: CaptureMode, tempDirectory: URL, vocabulary: [String] = [], onProgress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> [TranscriptSegment] {
        let selections: [ChannelSelection] = mode == .appAndMic ? [.channel(0), .channel(1)] : [.channel(0)]
        var extracted: [URL] = []
        defer { for url in extracted { try? FileManager.default.removeItem(at: url) } }
        var outputs: [[RawSegment]] = []
        for (index, selection) in selections.enumerated() {
            let channelFile = try ChannelExtractor.extract(selection, from: audioFile, into: tempDirectory)
            extracted.append(channelFile)
            do {
                let segments = try await engine.transcribe(audioFile: channelFile, vocabulary: vocabulary) { fraction in
                    onProgress((Double(index) + min(1, max(0, fraction))) / Double(selections.count))
                }
                outputs.append(segments)
            } catch {
                throw TranscribeError.engineFailed(stage: "transcribing")
            }
        }
        onProgress(1)
        if mode == .appAndMic { return TranscriptMerger.merge(me: outputs[0], them: outputs[1]) }
        return TranscriptMerger.unlabeled(outputs[0])
    }
}
