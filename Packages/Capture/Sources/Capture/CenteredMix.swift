import Foundation
import AVFoundation
import Core

public enum CenteredMix {
    /// Reads any audio file; writes a 48 kHz mono 16-bit WAV (or AAC if `output` ends in .m4a) whose samples are the mean of all channels. Streams in 1 s blocks.
    public static func write(from source: URL, to output: URL) throws {
        guard !FileManager.default.fileExists(atPath: output.path) else { throw CenteredMixError.outputExists }
        let reader = try StreamedMonoReader(url: source, sampleRate: 48_000)
        let isAAC = output.pathExtension.lowercased() == "m4a"
        var settings: [String: Any] = [AVSampleRateKey: 48_000.0, AVNumberOfChannelsKey: 1]
        if isAAC {
            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            settings[AVEncoderBitRateKey] = 64_000
        } else {
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = false
        }
        let writer = try AVAudioFile(forWriting: output, settings: settings)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000),
              let destination = buffer.floatChannelData?[0] else { throw CenteredMixError.invalidFormat }
        while let samples = try reader.read(maxFrames: 48_000), !samples.isEmpty {
            for (index, sample) in samples.enumerated() { destination[index] = sample }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            try writer.write(from: buffer)
        }
    }
}

private enum CenteredMixError: Error { case invalidFormat, outputExists }

/// Bounded-memory file reader that converts any input channel layout and sample rate to mono Float32.
final class StreamedMonoReader {
    private let file: AVAudioFile
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private var ended = false
    private var readError: Error?

    init(url: URL, sampleRate: Double) throws {
        file = try AVAudioFile(forReading: url)
        guard let target = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let converter = AVAudioConverter(from: file.processingFormat, to: target) else {
            throw CenteredMixError.invalidFormat
        }
        outputFormat = target
        self.converter = converter
        converter.downmix = true
    }

    func read(maxFrames: AVAudioFrameCount) throws -> [Float]? {
        guard !ended else { return nil }
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: maxFrames),
              let channel = output.floatChannelData?[0] else { throw CenteredMixError.invalidFormat }
        readError = nil
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { [weak self] requested, inputStatus in
            guard let self, !self.ended else { inputStatus.pointee = .endOfStream; return nil }
            let remaining = max(Int64(0), self.file.length - self.file.framePosition)
            guard remaining > 0 else {
                self.ended = true
                inputStatus.pointee = .endOfStream
                return nil
            }
            let capacity = min(max(AVAudioFrameCount(1), requested), AVAudioFrameCount(remaining))
            guard let input = AVAudioPCMBuffer(pcmFormat: self.file.processingFormat, frameCapacity: capacity) else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            do {
                try self.file.read(into: input, frameCount: capacity)
            } catch {
                self.readError = error
                inputStatus.pointee = .noDataNow
                return nil
            }
            if input.frameLength == 0 {
                self.ended = true
                inputStatus.pointee = .endOfStream
                return nil
            }
            inputStatus.pointee = .haveData
            return input
        }
        if let readError { throw readError }
        if let conversionError { throw conversionError }
        if status == .error { throw CenteredMixError.invalidFormat }
        if output.frameLength == 0 { ended = true; return nil }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}
