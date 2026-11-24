import Testing
import Foundation
import AVFoundation
import os
@testable import Capture
import CoreTestSupport

@Suite struct TrackWriterTests {
    @Test func writeSineAndStopAndFlush() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir / "test.caf"
        let ring = RingBuffer(capacity: 96000 * 2)
        let writer = try TrackWriter(ring: ring, channels: 1, sampleRate: 48_000, url: url)
        writer.start()

        let total = 96000
        var samples = [Float](repeating: 0, count: total)
        for i in 0..<total {
            samples[i] = 0.5 * Float(sin(2 * .pi * 440.0 * Double(i) / 48000.0))
        }

        var sent = 0
        while sent < total {
            let chunk = min(Int.random(in: 128...2048), total - sent)
            samples[sent..<(sent + chunk)].withContiguousStorageIfAvailable { ptr in
                _ = ring.write(from: ptr.baseAddress!, count: chunk)
            }
            sent += chunk
            Thread.sleep(forTimeInterval: 0.001)
        }

        let written = try writer.stopAndFlush()
        #expect(written == 96_000)

        let file = try AVAudioFile(forReading: url)
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buf)
        let readSamples = Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
        #expect(readSamples.count == 96_000)
        for i in 0..<total {
            #expect(abs(readSamples[i] - samples[i]) <= (1.0 / 32768.0) * 2.0)
        }
    }

    @Test func stereoInterleavedMeanDownmix() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir / "stereo.caf"
        let ring = RingBuffer(capacity: 4096)
        let writer = try TrackWriter(ring: ring, channels: 2, sampleRate: 48_000, url: url)
        writer.start()

        var stereo = [Float](repeating: 0, count: 2000)
        for i in 0..<1000 {
            stereo[2 * i] = 1.0     // L
            stereo[2 * i + 1] = 0.0 // R
        }
        stereo.withUnsafeBufferPointer { ptr in
            _ = ring.write(from: ptr.baseAddress!, count: ptr.count)
        }

        let written = try writer.stopAndFlush()
        #expect(written == 1000)

        let file = try AVAudioFile(forReading: url)
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buf)
        let readSamples = Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
        for s in readSamples {
            #expect(abs(s - 0.5) <= 0.01)
        }
    }

    @Test func onBlockSilent() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir / "silent.caf"
        let ring = RingBuffer(capacity: 9600)
        let totalFramesSeen = OSAllocatedUnfairLock(initialState: 0)
        let writer = try TrackWriter(ring: ring, channels: 1, sampleRate: 48_000, url: url) { peak, frames in
            #expect(peak == 0)
            totalFramesSeen.withLock { $0 += frames }
        }
        writer.start()

        let zeros = [Float](repeating: 0, count: 4800)
        zeros.withUnsafeBufferPointer { ptr in
            _ = ring.write(from: ptr.baseAddress!, count: ptr.count)
        }

        let written = try writer.stopAndFlush()
        #expect(written == 4800)
        #expect(totalFramesSeen.withLock { $0 } == 4800)
    }

    @Test func stopAndFlushIdempotent() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir / "idempotent.caf"
        let ring = RingBuffer(capacity: 4096)
        let writer = try TrackWriter(ring: ring, channels: 1, sampleRate: 48_000, url: url)
        writer.start()

        let samples = [Float](repeating: 0.1, count: 500)
        samples.withUnsafeBufferPointer { ptr in
            _ = ring.write(from: ptr.baseAddress!, count: ptr.count)
        }

        let count1 = try writer.stopAndFlush()
        let count2 = try writer.stopAndFlush()
        #expect(count1 == 500)
        #expect(count2 == 500)
    }

    @Test func droppedSamplesCounted() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir / "tiny.caf"
        let ring = RingBuffer(capacity: 64)
        let writer = try TrackWriter(ring: ring, channels: 1, sampleRate: 48_000, url: url)
        // Do not start immediately so producer overflows ring
        let produced = 1000
        let samples = [Float](repeating: 0.2, count: produced)
        samples.withUnsafeBufferPointer { ptr in
            _ = ring.write(from: ptr.baseAddress!, count: ptr.count)
        }
        writer.start()
        Thread.sleep(forTimeInterval: 0.05)
        let written = try writer.stopAndFlush()
        #expect(writer.droppedSamples > 0)
        #expect(Int(written) + writer.droppedSamples == produced)
    }
}
