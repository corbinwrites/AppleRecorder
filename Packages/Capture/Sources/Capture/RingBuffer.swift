import Foundation

public final class RingBuffer: @unchecked Sendable {
    public init() {}
    public func write(_ ptr: UnsafePointer<Float>, count: Int) -> Int { count }
}
