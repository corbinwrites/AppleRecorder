import Foundation
import Core

public struct TrackInput: Sendable {
    public var url: URL
    public var startNanos: UInt64
    public init(url: URL, startNanos: UInt64) {
        self.url = url
        self.startNanos = startNanos
    }
}

public struct ChannelReport: Sendable, Equatable {
    public var peak: Float
    public var rms: Float
    public var isSilent: Bool

    public init(peak: Float, rms: Float, isSilent: Bool) {
        self.peak = peak
        self.rms = rms
        self.isSilent = isSilent
    }
}

public struct FinalizeReport: Sendable, Equatable {
    public var durationSeconds: Double
    public var channels: Int
    public var mic: ChannelReport?
    public var app: ChannelReport?

    public init(durationSeconds: Double, channels: Int, mic: ChannelReport? = nil, app: ChannelReport? = nil) {
        self.durationSeconds = durationSeconds
        self.channels = channels
        self.mic = mic
        self.app = app
    }
}

public enum FinalizeError: Error, Sendable, Equatable {
    case noInput
    case cannotRead(String)
    case verificationFailed(String)
}

public enum Finalizer {
    public static let sampleRate = 48_000.0

    /// mic -> channel 0, app -> channel 1 when both exist; otherwise a single mono channel.
    public static func finalize(mic: TrackInput?, app: TrackInput?, to output: URL) throws -> FinalizeReport {
        throw TODO.notImplemented
    }
}
