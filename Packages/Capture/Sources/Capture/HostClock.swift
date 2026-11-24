import Foundation
import Darwin
import Core

public enum HostClock {
    public static func nanos(hostTime: UInt64, numer: UInt32, denom: UInt32) -> UInt64 {
        fatalError("TODO")
    }

    public static func nanos(hostTime: UInt64) -> UInt64 {
        fatalError("TODO")
    }

    /// Frames of leading silence for a track that started `trackStartNanos`, relative to the earliest track.
    public static func startOffsetFrames(trackStartNanos: UInt64, referenceNanos: UInt64, sampleRate: Double) -> Int {
        fatalError("TODO")
    }
}
