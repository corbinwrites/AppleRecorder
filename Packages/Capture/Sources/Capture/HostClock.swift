import Foundation
import Darwin
import Core

public enum HostClock {
    private static let info: mach_timebase_info_data_t = {
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom != 0 else {
            preconditionFailure("Could not read the Mach host timebase")
        }
        return timebase
    }()

    public static func nanos(hostTime: UInt64, numer: UInt32, denom: UInt32) -> UInt64 {
        guard denom != 0 else { preconditionFailure("Mach host timebase denominator must be nonzero") }
        let divisor = UInt64(denom)
        let multiplier = UInt64(numer)
        return (hostTime / divisor) * multiplier + (hostTime % divisor) * multiplier / divisor
    }

    public static func nanos(hostTime: UInt64) -> UInt64 {
        nanos(hostTime: hostTime, numer: info.numer, denom: info.denom)
    }

    /// Frames of leading silence for a track that started `trackStartNanos`, relative to the earliest track.
    public static func startOffsetFrames(trackStartNanos: UInt64, referenceNanos: UInt64, sampleRate: Double) -> Int {
        guard trackStartNanos > referenceNanos else { return 0 }
        return Int((Double(trackStartNanos - referenceNanos) / 1e9 * sampleRate).rounded())
    }
}
