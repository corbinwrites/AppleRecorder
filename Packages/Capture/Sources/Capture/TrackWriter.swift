import Foundation
import Core

public final class TrackWriter: @unchecked Sendable {
    public private(set) var droppedSamples: Int = 0

    public init(ring: RingBuffer, channels: Int, sampleRate: Double, url: URL,
                onBlock: (@Sendable (_ peak: Float, _ frames: Int) -> Void)? = nil) throws {
        throw TODO.notImplemented
    }

    public func start() {
        fatalError("TODO")
    }

    public func stopAndFlush() throws -> Int64 {
        throw TODO.notImplemented
    }
}
