import Testing
import Foundation
@testable import Capture

@Suite struct ZeroRunDetectorTests {
    private static func checkFeed(_ detector: inout ZeroRunDetector, peak: Float = 0, frames: Int = 4800, outputRunning: Bool = true, expected: Bool) {
        let result = detector.feed(peak: peak, frames: frames, outputRunning: outputRunning)
        #expect(result == expected)
    }

    @Test func thirtyBlocksTrips() {
        var d = ZeroRunDetector(sampleRate: 48_000, thresholdSeconds: 3.0)
        for _ in 0..<29 {
            Self.checkFeed(&d, expected: false)
        }
        Self.checkFeed(&d, expected: true)
        Self.checkFeed(&d, expected: false)
        #expect(d.tripped)
    }

    @Test func outputNotRunningNeverTrips() {
        var d = ZeroRunDetector(sampleRate: 48_000, thresholdSeconds: 3.0)
        for _ in 0..<100 {
            Self.checkFeed(&d, outputRunning: false, expected: false)
        }
        #expect(!d.tripped)
    }

    @Test func nonZeroResetsRun() {
        var d = ZeroRunDetector(sampleRate: 48_000, thresholdSeconds: 3.0)
        for _ in 0..<20 {
            Self.checkFeed(&d, expected: false)
        }
        Self.checkFeed(&d, peak: 0.001, expected: false)
        for _ in 0..<20 {
            Self.checkFeed(&d, expected: false)
        }
        #expect(!d.tripped)
    }

    @Test func untripsOnSignalAndCanRetrip() {
        var d = ZeroRunDetector(sampleRate: 48_000, thresholdSeconds: 3.0)
        for _ in 0..<30 {
            _ = d.feed(peak: 0, frames: 4800, outputRunning: true)
        }
        #expect(d.tripped)
        Self.checkFeed(&d, peak: 0.1, expected: false)
        #expect(!d.tripped)

        for _ in 0..<29 {
            Self.checkFeed(&d, expected: false)
        }
        Self.checkFeed(&d, expected: true)
        #expect(d.tripped)
    }

    @Test func outputNotRunningResetsRun() {
        var d = ZeroRunDetector(sampleRate: 48_000, thresholdSeconds: 3.0)
        for _ in 0..<20 {
            Self.checkFeed(&d, expected: false)
        }
        Self.checkFeed(&d, outputRunning: false, expected: false)
        for _ in 0..<20 {
            Self.checkFeed(&d, expected: false)
        }
        #expect(!d.tripped)
    }

    @Test func tinySignalResetsRun() {
        var d = ZeroRunDetector(sampleRate: 48_000, thresholdSeconds: 3.0)
        for _ in 0..<20 {
            Self.checkFeed(&d, expected: false)
        }
        Self.checkFeed(&d, peak: 1e-9, expected: false)
        for _ in 0..<20 {
            Self.checkFeed(&d, expected: false)
        }
        #expect(!d.tripped)
    }

    @Test func customThresholdAndRate() {
        var d = ZeroRunDetector(sampleRate: 44_100, thresholdSeconds: 1.0)
        for _ in 0..<9 {
            Self.checkFeed(&d, frames: 4410, expected: false)
        }
        Self.checkFeed(&d, frames: 4410, expected: true)
        #expect(d.tripped)
    }
}
