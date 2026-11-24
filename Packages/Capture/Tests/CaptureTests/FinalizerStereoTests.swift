import Testing
import Foundation
import AVFoundation
@testable import Capture
import CoreTestSupport

@Suite struct FinalizerStereoTests {
    @Test func stereoChannelsStayPureAndAligned() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        try writeSine(to: dir/"mic.caf", freq: 440, seconds: 3.0, sampleRate: 48_000)
        try writeSine(to: dir/"app.caf", freq: 880, seconds: 2.0, sampleRate: 44_100)        // different rate: forces resampling
        let r = try Finalizer.finalize(mic: .init(url: dir/"mic.caf", startNanos: 1_000_000_000),
                                       app: .init(url: dir/"app.caf", startNanos: 1_500_000_000),   // app starts 0.5 s later
                                       to: dir/"out.m4a")
        let (ch, rate) = try readChannels(dir/"out.m4a")
        #expect(ch.count == 2 && rate == 48_000)
        #expect(abs(r.durationSeconds - 3.0) < 0.15)
        let mid = 48_000 * 1 ..< 48_000 * 2                                   // 1.0–2.0 s: both present
        #expect(goertzelPower(ch[0][mid], freq: 440, rate: 48_000) > 100 * goertzelPower(ch[0][mid], freq: 880, rate: 48_000))
        #expect(goertzelPower(ch[1][mid], freq: 880, rate: 48_000) > 100 * goertzelPower(ch[1][mid], freq: 440, rate: 48_000))
        #expect(rms(ch[1][0..<(48_000 * 4 / 10)]) < 0.01)                      // app silent for its 0.5 s lead-in (checked 0–0.4 s)
        #expect(rms(ch[0][0..<(48_000 * 4 / 10)]) > 0.1)                       // mic present from the start
        #expect(r.mic?.isSilent == false && r.app?.isSilent == false)
    }
}
