import Foundation
import Core

public struct ZeroRunDetector: Sendable {
    public let sampleRate: Double, thresholdSeconds: Double
    public private(set) var tripped = false

    public init(sampleRate: Double, thresholdSeconds: Double = 3.0) {
        self.sampleRate = sampleRate
        self.thresholdSeconds = thresholdSeconds
    }

    /// peak = max |sample| of the block. Returns true exactly once per run, the moment the run reaches the threshold.
    public mutating func feed(peak: Float, frames: Int, outputRunning: Bool) -> Bool {
        fatalError("TODO")
    }
}
