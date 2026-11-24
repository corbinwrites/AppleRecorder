import Foundation
import Synchronization
import Core

public final class RingBuffer: @unchecked Sendable {
    private let storage: UnsafeMutablePointer<Float>
    public let capacity: Int
    private let head = Atomic<Int>(0)
    private let tail = Atomic<Int>(0)
    private let dropped = Atomic<Int>(0)

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }

    deinit { storage.deallocate() }

    public func write(from src: UnsafePointer<Float>, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let currentHead = head.load(ordering: .relaxed)
        let currentTail = tail.load(ordering: .acquiring)
        let written = min(count, capacity - (currentHead - currentTail))
        if written < count { _ = dropped.wrappingAdd(count - written, ordering: .relaxed) }
        if written > 0 {
            let start = currentHead % capacity
            let firstChunk = min(written, capacity - start)
            (storage + start).update(from: src, count: firstChunk)
            if written > firstChunk { storage.update(from: src + firstChunk, count: written - firstChunk) }
            head.store(currentHead + written, ordering: .releasing)
        }
        return written
    }

    public func read(into dst: UnsafeMutablePointer<Float>, max: Int) -> Int {
        guard max > 0 else { return 0 }
        let currentTail = tail.load(ordering: .relaxed)
        let currentHead = head.load(ordering: .acquiring)
        let readCount = min(max, currentHead - currentTail)
        if readCount > 0 {
            let start = currentTail % capacity
            let firstChunk = min(readCount, capacity - start)
            dst.update(from: storage + start, count: firstChunk)
            if readCount > firstChunk { (dst + firstChunk).update(from: storage, count: readCount - firstChunk) }
            tail.store(currentTail + readCount, ordering: .releasing)
        }
        return readCount
    }

    public var droppedSamples: Int {
        dropped.load(ordering: .relaxed)
    }

    public var availableToRead: Int {
        head.load(ordering: .acquiring) - tail.load(ordering: .relaxed)
    }
}
