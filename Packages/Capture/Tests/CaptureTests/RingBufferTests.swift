import Testing
import Foundation
import os
@testable import Capture

@Suite struct RingBufferTests {
    @Test func orderPreserved() {
        let ring = RingBuffer(capacity: 16)
        let input: [Float] = [1, 2, 3, 4, 5]
        let written = input.withUnsafeBufferPointer { ptr in
            ring.write(from: ptr.baseAddress!, count: ptr.count)
        }
        #expect(written == 5)
        var output = [Float](repeating: 0, count: 5)
        let read = output.withUnsafeMutableBufferPointer { ptr in
            ring.read(into: ptr.baseAddress!, max: 5)
        }
        #expect(read == 5)
        #expect(output == input)
    }

    @Test func wraparound() {
        let ring = RingBuffer(capacity: 8)
        let w1: [Float] = [1, 2, 3, 4, 5, 6]
        _ = w1.withUnsafeBufferPointer { ring.write(from: $0.baseAddress!, count: $0.count) }

        var r1 = [Float](repeating: 0, count: 4)
        _ = r1.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, max: 4) }
        #expect(r1 == [1, 2, 3, 4])

        let w2: [Float] = [1, 2, 3, 4, 5, 6]
        _ = w2.withUnsafeBufferPointer { ring.write(from: $0.baseAddress!, count: $0.count) }

        var r2 = [Float](repeating: 0, count: 8)
        let readCount = r2.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, max: 8) }
        #expect(readCount == 8)
        #expect(r2 == [5, 6, 1, 2, 3, 4, 5, 6])
    }

    @Test func overrunDropsNewestAndCounts() {
        let ring = RingBuffer(capacity: 4)
        let input: [Float] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        let written = input.withUnsafeBufferPointer { ring.write(from: $0.baseAddress!, count: $0.count) }
        #expect(written == 4)
        #expect(ring.droppedSamples == 6)

        var output = [Float](repeating: 0, count: 4)
        let read = output.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, max: 4) }
        #expect(read == 4)
        #expect(output == [1, 2, 3, 4])
    }

    @Test func readEmptyReturnsZero() {
        let ring = RingBuffer(capacity: 8)
        var output = [Float](repeating: 0, count: 4)
        let read = output.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, max: 4) }
        #expect(read == 0)
    }

    @Test func zeroCountWriteIsNoop() {
        let ring = RingBuffer(capacity: 8)
        let dummy: [Float] = [1]
        let written = dummy.withUnsafeBufferPointer { ring.write(from: $0.baseAddress!, count: 0) }
        #expect(written == 0)
        #expect(ring.availableToRead == 0)
    }

    @Test func spscStress() {
        for _ in 0..<5 {
            let ring = RingBuffer(capacity: 4096)
            let total = 200_000
            let done = OSAllocatedUnfairLock(initialState: false)
            nonisolated(unsafe) var received: [Float] = []
            received.reserveCapacity(total)

            let consumer = Thread {
                var chunk = [Float](repeating: 0, count: 1024)
                while true {
                    let isDone = done.withLock { $0 }
                    let n = chunk.withUnsafeMutableBufferPointer { ptr in
                        ring.read(into: ptr.baseAddress!, max: ptr.count)
                    }
                    if n > 0 {
                        received.append(contentsOf: chunk[0..<n])
                    } else if isDone && ring.availableToRead == 0 {
                        break
                    } else {
                        Thread.sleep(forTimeInterval: 0.0001)
                    }
                }
            }
            consumer.start()

            var sent = 0
            while sent < total {
                let chunkSize = min(Int.random(in: 1...512), total - sent)
                let values = (sent..<(sent + chunkSize)).map { Float($0) }
                _ = values.withUnsafeBufferPointer { ptr in
                    ring.write(from: ptr.baseAddress!, count: ptr.count)
                }
                sent += chunkSize
            }
            done.withLock { $0 = true }

            while !consumer.isFinished {
                Thread.sleep(forTimeInterval: 0.001)
            }

            // Assert strictly increasing
            for i in 1..<received.count {
                #expect(received[i] > received[i - 1])
            }
            #expect(received.count + ring.droppedSamples == total)
        }
    }
}
