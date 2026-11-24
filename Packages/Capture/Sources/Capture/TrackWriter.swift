import Foundation
import AVFoundation
import Core

public final class TrackWriter: @unchecked Sendable {
    private let ring: RingBuffer
    private let channels: Int
    private let sampleRate: Double
    private let url: URL
    private let onBlock: @Sendable (Float, Int) -> Void
    private let lock = NSLock()
    private var worker: Thread?
    private var started = false
    private var stopping = false
    private var finished = false
    private var frameCount: Int64 = 0
    private var workerError: Error?
    private var audioFile: AVAudioFile?
    private var pcmBuffer: AVAudioPCMBuffer?
    private var interleaved: [Float] = []
    private var carry: [Float] = []

    public var droppedSamples: Int { ring.droppedSamples }

    public init(ring: RingBuffer, channels: Int, sampleRate: Double, url: URL,
                onBlock: (@Sendable (Float, Int) -> Void)? = nil) throws {
        guard channels > 0, sampleRate > 0 else { throw TrackWriterError.invalidFormat }
        self.ring = ring
        self.channels = channels
        self.sampleRate = sampleRate
        self.url = url
        self.onBlock = onBlock ?? { _, _ in }
        guard !FileManager.default.fileExists(atPath: url.path) else { throw TrackWriterError.outputExists }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false]
        audioFile = try AVAudioFile(forWriting: url, settings: settings)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800) else {
            throw TrackWriterError.invalidFormat
        }
        pcmBuffer = buffer
        interleaved = [Float](repeating: 0, count: 4800 * channels)
    }

    public func start() {
        lock.lock()
        guard !started, !finished else { lock.unlock(); return }
        started = true
        let thread = Thread { [weak self] in self?.consume() }
        thread.name = "AppleRecorder.TrackWriter"
        worker = thread
        lock.unlock()
        thread.start()
    }

    public func stopAndFlush() throws -> Int64 {
        lock.lock()
        if finished {
            let result = frameCount
            let error = workerError
            lock.unlock()
            if let error { throw error }
            return result
        }
        stopping = true
        let hasStarted = started
        lock.unlock()
        if hasStarted {
            while true {
                lock.lock()
                let done = finished
                lock.unlock()
                if done { break }
                Thread.sleep(forTimeInterval: 0.001)
            }
        } else {
            consume()
        }
        lock.lock()
        let result = frameCount
        let error = workerError
        lock.unlock()
        if let error { throw error }
        return result
    }

    private func consume() {
        while true {
            let n = interleaved.withUnsafeMutableBufferPointer { ptr in
                guard let baseAddress = ptr.baseAddress else { return 0 }
                return ring.read(into: baseAddress, max: ptr.count)
            }
            let completeCount = carry.count + n
            let usableCount = completeCount - completeCount % channels
            if usableCount > 0 {
                var samples = carry
                samples.append(contentsOf: interleaved[0..<n])
                let frames = min(usableCount / channels, 4800)
                if frames > 0 {
                    do { try writeFrames(samples, frames: frames) }
                    catch { lock.lock(); workerError = error; stopping = true; lock.unlock() }
                }
                carry = Array(samples[usableCount...])
            } else {
                carry.append(contentsOf: interleaved[0..<n])
            }
            lock.lock()
            let shouldStop = stopping && ring.availableToRead == 0
            lock.unlock()
            if shouldStop {
                if !carry.isEmpty { carry.removeAll(keepingCapacity: true) }
                break
            }
            if n == 0 { Thread.sleep(forTimeInterval: 0.002) }
        }
        audioFile = nil
        lock.lock(); finished = true; lock.unlock()
    }

    private func writeFrames(_ samples: [Float], frames: Int) throws {
        guard let buffer = pcmBuffer, let file = audioFile, let data = buffer.floatChannelData?[0] else {
            throw TrackWriterError.invalidFormat
        }
        var peak: Float = 0
        for frame in 0..<frames {
            var mean: Float = 0
            for channel in 0..<channels { mean += samples[frame * channels + channel] }
            mean /= Float(channels)
            data[frame] = mean
            peak = max(peak, abs(mean))
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        try file.write(from: buffer)
        onBlock(peak, frames)
        lock.lock(); frameCount += Int64(frames); lock.unlock()
    }
}

private enum TrackWriterError: Error { case invalidFormat, outputExists }
