import Testing
import Foundation
import AVFoundation
@testable import Capture
import CoreTestSupport

@Suite struct FinalizerTests {
    @Test func appStartsFirst() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        try writeSine(to: dir/"app.caf", freq: 880, seconds: 2.0, sampleRate: 48_000)
        try writeSine(to: dir/"mic.caf", freq: 440, seconds: 2.0, sampleRate: 48_000)
        // app starts 0.25s BEFORE mic
        let r = try Finalizer.finalize(mic: .init(url: dir/"mic.caf", startNanos: 1_250_000_000),
                                       app: .init(url: dir/"app.caf", startNanos: 1_000_000_000),
                                       to: dir/"out.m4a")
        let (ch, _) = try readChannels(dir/"out.m4a")
        #expect(ch.count == 2)
        #expect(rms(ch[0][0..<(48_000 * 2 / 10)]) < 0.01) // ch0 (mic) silent for first 0.2 s
        #expect(rms(ch[1][0..<(48_000 * 2 / 10)]) > 0.1)  // ch1 (app) loud from start
        #expect(r.mic?.isSilent == false && r.app?.isSilent == false)
    }

    @Test func micOnlyIsMono() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        try writeSine(to: dir/"mic.caf", freq: 440, seconds: 2.0, sampleRate: 48_000)
        let r = try Finalizer.finalize(mic: .init(url: dir/"mic.caf", startNanos: 0), app: nil, to: dir/"out.m4a")
        let (ch, rate) = try readChannels(dir/"out.m4a")
        #expect(ch.count == 1 && rate == 48_000)
        #expect(abs(r.durationSeconds - 2.0) < 0.15)
        #expect(goertzelPower(ch[0][...], freq: 440, rate: 48_000) > 100 * goertzelPower(ch[0][...], freq: 880, rate: 48_000))
    }

    @Test func appOnlyIsMono() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        try writeSine(to: dir/"app.caf", freq: 880, seconds: 2.0, sampleRate: 48_000)
        let r = try Finalizer.finalize(mic: nil, app: .init(url: dir/"app.caf", startNanos: 0), to: dir/"out.m4a")
        let (ch, rate) = try readChannels(dir/"out.m4a")
        #expect(ch.count == 1 && rate == 48_000)
        #expect(abs(r.durationSeconds - 2.0) < 0.15)
        #expect(goertzelPower(ch[0][...], freq: 880, rate: 48_000) > 100 * goertzelPower(ch[0][...], freq: 440, rate: 48_000))
    }

    @Test func noInputThrows() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        #expect(throws: FinalizeError.noInput) {
            try Finalizer.finalize(mic: nil, app: nil, to: dir.appendingPathComponent("out.m4a"))
        }
    }

    @Test func silentTrackIsReportedNotFatal() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        try writeSilence(to: dir/"mic.caf", seconds: 2.0, sampleRate: 48_000)
        try writeSine(to: dir/"app.caf", freq: 880, seconds: 2.0, sampleRate: 48_000)
        let r = try Finalizer.finalize(mic: .init(url: dir/"mic.caf", startNanos: 0),
                                       app: .init(url: dir/"app.caf", startNanos: 0),
                                       to: dir/"out.m4a")
        #expect(r.mic?.isSilent == true)
        #expect(r.app?.isSilent == false)
    }

    @Test func missingFileThrowsCannotRead() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let nonExistent = dir / "does_not_exist.caf"
        #expect(throws: FinalizeError.self) {
            try Finalizer.finalize(mic: .init(url: nonExistent, startNanos: 0), app: nil, to: dir / "out.m4a")
        }
    }

    @Test func noPartialFileLeftOnFailure() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let nonExistent = dir / "missing.caf"
        let out = dir / "out.m4a"
        let partial = dir / "out.m4a.partial"
        do {
            _ = try Finalizer.finalize(mic: .init(url: nonExistent, startNanos: 0), app: nil, to: out)
        } catch {
            // expected
        }
        #expect(!FileManager.default.fileExists(atPath: out.path))
        #expect(!FileManager.default.fileExists(atPath: partial.path))
    }

    @Test func longTrackStreams() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let mic = dir / "long_mic.caf"
        try writeSine(to: mic, freq: 440, seconds: 75.0, sampleRate: 48_000)
        let out = dir / "long_out.m4a"
        let r = try Finalizer.finalize(mic: .init(url: mic, startNanos: 0), app: nil, to: out)
        #expect(abs(r.durationSeconds - 75.0) < 0.15)

        let (ch, _) = try readChannels(out)
        let samples = ch[0]
        var maxJump: Float = 0
        for i in 1..<samples.count {
            let jump = abs(samples[i] - samples[i - 1])
            if jump > maxJump { maxJump = jump }
        }
        #expect(maxJump <= 0.1)
    }

    @Test func outputIsAAC() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        try writeSine(to: dir/"mic.caf", freq: 440, seconds: 3.0, sampleRate: 48_000)
        try writeSine(to: dir/"app.caf", freq: 880, seconds: 3.0, sampleRate: 48_000)
        let out = dir / "out.m4a"
        _ = try Finalizer.finalize(mic: .init(url: dir/"mic.caf", startNanos: 0),
                                   app: .init(url: dir/"app.caf", startNanos: 0),
                                   to: out)
        let f = try AVAudioFile(forReading: out)
        #expect(f.fileFormat.sampleRate == 48_000)
        let attrs = try FileManager.default.attributesOfItem(atPath: out.path)
        let size = attrs[.size] as? Int64 ?? 0
        #expect(size >= 30 * 1024 && size <= 90 * 1024)
    }
}
