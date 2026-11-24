import Testing
import Foundation
@testable import Capture

@Suite struct HostClockTests {
    @Test func nanosMath() {
        #expect(HostClock.nanos(hostTime: 3000, numer: 125, denom: 3) == 125_000)
        #expect(HostClock.nanos(hostTime: 42, numer: 1, denom: 1) == 42)
    }

    @Test func overflowSafe() {
        let hostTime: UInt64 = 10_000_000_000_000_000 // 10^16
        let numer: UInt32 = 125
        let denom: UInt32 = 3
        let expected = UInt64((UInt128(10_000_000_000_000_000) * 125) / 3)
        #expect(HostClock.nanos(hostTime: hostTime, numer: numer, denom: denom) == expected)
    }

    @Test func startOffsets() {
        #expect(HostClock.startOffsetFrames(trackStartNanos: 1_000_000_000, referenceNanos: 1_000_000_000, sampleRate: 48_000) == 0)
        #expect(HostClock.startOffsetFrames(trackStartNanos: 1_500_000_000, referenceNanos: 1_000_000_000, sampleRate: 48_000) == 24_000)
        #expect(HostClock.startOffsetFrames(trackStartNanos: 2_000_000_000, referenceNanos: 1_000_000_000, sampleRate: 44_100) == 44_100)
        #expect(HostClock.startOffsetFrames(trackStartNanos: 1_000_001_000, referenceNanos: 1_000_000_000, sampleRate: 48_000) == 0) // +1 µs @ 48 kHz rounds to 0
        #expect(HostClock.startOffsetFrames(trackStartNanos: 1_010_500_000, referenceNanos: 1_000_000_000, sampleRate: 48_000) == 504) // +10.5 ms @ 48 kHz
        #expect(HostClock.startOffsetFrames(trackStartNanos: 500_000_000, referenceNanos: 1_000_000_000, sampleRate: 48_000) == 0) // earlier than reference -> 0
    }
}
