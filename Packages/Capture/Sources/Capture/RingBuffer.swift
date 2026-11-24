import Foundation
import Synchronization
import Core

public final class RingBuffer: @unchecked Sendable {
    public let capacity: Int

    public init(capacity: Int) {
        self.capacity = capacity
    }

    public func write(from src: UnsafePointer<Float>, count: Int) -> Int {
        fatalError("TODO")
    }

    public func read(into dst: UnsafeMutablePointer<Float>, max: Int) -> Int {
        fatalError("TODO")
    }

    public var droppedSamples: Int {
        fatalError("TODO")
    }

    public var availableToRead: Int {
        fatalError("TODO")
    }
}
