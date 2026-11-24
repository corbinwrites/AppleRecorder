import Foundation
import AVFoundation
import Core

public struct TrackInput: Sendable {
    public var url: URL
    public var startNanos: UInt64
    public init(url: URL, startNanos: UInt64) {
        self.url = url
        self.startNanos = startNanos
    }
}

public struct ChannelReport: Sendable, Equatable {
    public var peak: Float
    public var rms: Float
    public var isSilent: Bool

    public init(peak: Float, rms: Float, isSilent: Bool) {
        self.peak = peak
        self.rms = rms
        self.isSilent = isSilent
    }
}

public struct FinalizeReport: Sendable, Equatable {
    public var durationSeconds: Double
    public var channels: Int
    public var mic: ChannelReport?
    public var app: ChannelReport?

    public init(durationSeconds: Double, channels: Int, mic: ChannelReport? = nil, app: ChannelReport? = nil) {
        self.durationSeconds = durationSeconds
        self.channels = channels
        self.mic = mic
        self.app = app
    }
}

public enum FinalizeError: Error, Sendable, Equatable {
    case noInput
    case cannotRead(String)
    case verificationFailed(String)
}

public enum Finalizer {
    public static let sampleRate = 48_000.0

    /// mic -> channel 0, app -> channel 1 when both exist; otherwise a single mono channel.
    public static func finalize(mic: TrackInput?, app: TrackInput?, to output: URL) throws -> FinalizeReport {
        guard mic != nil || app != nil else { throw FinalizeError.noInput }
        let present = [mic, app].compactMap { $0 }
        let reference = present.map(\.startNanos).min() ?? 0
        let partial = output.appendingPathExtension("partial")
        let manager = FileManager.default
        guard !manager.fileExists(atPath: partial.path), !manager.fileExists(atPath: output.path) else {
            throw FinalizeError.verificationFailed("output exists")
        }
        var createdPartial = false
        do {
            let micReader = try mic.map { try AlignedTrackReader(input: $0, reference: reference) }
            let appReader = try app.map { try AlignedTrackReader(input: $0, reference: reference) }
            let channelCount: AVAudioChannelCount = mic != nil && app != nil ? 2 : 1
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: Int(channelCount), AVEncoderBitRateKey: channelCount == 2 ? 128_000 : 64_000]
            var file: AVAudioFile? = try AVAudioFile(forWriting: partial, settings: settings)
            createdPartial = true
            guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000),
                  let channelData = buffer.floatChannelData else { throw FinalizeError.verificationFailed("format") }
            var stats = Array(repeating: ChannelAccumulator(), count: Int(channelCount))
            var totalFrames = 0
            var micEnded = micReader == nil
            var appEnded = appReader == nil
            while !micEnded || !appEnded {
                let micSamples = try micReader?.read(maxFrames: 48_000) ?? []
                let appSamples = try appReader?.read(maxFrames: 48_000) ?? []
                if micReader != nil && micSamples.isEmpty { micEnded = true }
                if appReader != nil && appSamples.isEmpty { appEnded = true }
                let frames = max(micSamples.count, appSamples.count)
                if frames == 0 { break }
                for frame in 0..<frames {
                    if channelCount == 2 {
                        let m = frame < micSamples.count ? micSamples[frame] : 0
                        let a = frame < appSamples.count ? appSamples[frame] : 0
                        channelData[0][frame] = m
                        channelData[1][frame] = a
                        stats[0].add(m); stats[1].add(a)
                    } else {
                        let value = mic != nil ? (frame < micSamples.count ? micSamples[frame] : 0) : (frame < appSamples.count ? appSamples[frame] : 0)
                        channelData[0][frame] = value
                        stats[0].add(value)
                    }
                }
                buffer.frameLength = AVAudioFrameCount(frames)
                try file?.write(from: buffer)
                totalFrames += frames
            }
            guard totalFrames > 0 else { throw FinalizeError.verificationFailed("duration") }
            let expectedDuration = Double(totalFrames) / sampleRate
            file = nil
            let verified = try AVAudioFile(forReading: partial)
            guard abs(Double(verified.length) / verified.processingFormat.sampleRate - expectedDuration) <= 0.15 else {
                throw FinalizeError.verificationFailed("duration")
            }
            try manager.moveItem(at: partial, to: output)
            func report(_ accumulator: ChannelAccumulator?) -> ChannelReport? { accumulator?.report }
            return FinalizeReport(durationSeconds: Double(verified.length) / verified.processingFormat.sampleRate,
                channels: Int(channelCount), mic: mic == nil ? nil : report(stats[channelCount == 2 ? 0 : 0]),
                app: app == nil ? nil : report(stats[channelCount == 2 ? 1 : 0]))
        } catch {
            if createdPartial && manager.fileExists(atPath: partial.path) { try? manager.removeItem(at: partial) }
            if let error = error as? FinalizeError { throw error }
            throw FinalizeError.cannotRead(error.localizedDescription)
        }
    }
}

private struct ChannelAccumulator {
    var peak: Float = 0
    var sumSquares: Double = 0
    var count = 0
    mutating func add(_ value: Float) { peak = max(peak, abs(value)); sumSquares += Double(value * value); count += 1 }
    var report: ChannelReport { ChannelReport(peak: peak, rms: count == 0 ? 0 : Float(sqrt(sumSquares / Double(count))), isSilent: peak < 0.001) }
}

private final class AlignedTrackReader {
    private let reader: StreamedMonoReader
    private var silenceFrames: Int
    init(input: TrackInput, reference: UInt64) throws {
        reader = try StreamedMonoReader(url: input.url, sampleRate: Finalizer.sampleRate)
        silenceFrames = HostClock.startOffsetFrames(trackStartNanos: input.startNanos, referenceNanos: reference, sampleRate: Finalizer.sampleRate)
    }
    func read(maxFrames: AVAudioFrameCount) throws -> [Float]? {
        let lead = min(silenceFrames, Int(maxFrames))
        silenceFrames -= lead
        if lead == Int(maxFrames) { return [Float](repeating: 0, count: lead) }
        guard let samples = try reader.read(maxFrames: maxFrames - AVAudioFrameCount(lead)) else {
            return lead > 0 ? [Float](repeating: 0, count: lead) : nil
        }
        return [Float](repeating: 0, count: lead) + samples
    }
}
