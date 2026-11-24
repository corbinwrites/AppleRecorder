import Testing
import Foundation
import AVFoundation
@testable import Capture
import CoreTestSupport

@Suite struct CenteredMixTests {
    @Test func stereoTracksMixToMono() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        try writeSine(to: dir / "mic.caf", freq: 440, seconds: 2, sampleRate: 48_000)
        try writeSine(to: dir / "app.caf", freq: 880, seconds: 2, sampleRate: 48_000)
        let stereo = dir / "stereo.m4a"
        _ = try Finalizer.finalize(mic: .init(url: dir / "mic.caf", startNanos: 0), app: .init(url: dir / "app.caf", startNanos: 0), to: stereo)
        let centered = dir / "centered.wav"
        try CenteredMix.write(from: stereo, to: centered)
        let (channels, rate) = try readChannels(centered)
        #expect(channels.count == 1 && rate == 48_000)
        #expect(abs(Double(channels[0].count) / rate - 2) < 0.15)
        #expect(goertzelPower(channels[0][...], freq: 440, rate: rate) > 20 * goertzelPower(channels[0][...], freq: 1500, rate: rate))
        #expect(goertzelPower(channels[0][...], freq: 880, rate: rate) > 20 * goertzelPower(channels[0][...], freq: 1500, rate: rate))
    }

    @Test func monoSourcePassesThrough() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir / "mono.caf"
        try writeSine(to: source, freq: 440, seconds: 1, sampleRate: 48_000)
        let output = dir / "mono.wav"
        try CenteredMix.write(from: source, to: output)
        let (channels, rate) = try readChannels(output)
        let (inputChannels, _) = try readChannels(source)
        #expect(rate == 48_000 && channels.count == 1)
        #expect(channels[0].count == inputChannels[0].count)
        for index in channels[0].indices { #expect(abs(channels[0][index] - inputChannels[0][index]) < 1e-4) }
    }

    @Test func missingFileThrows() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        #expect(throws: (any Error).self) { try CenteredMix.write(from: dir / "missing.caf", to: dir / "out.wav") }
    }
}
