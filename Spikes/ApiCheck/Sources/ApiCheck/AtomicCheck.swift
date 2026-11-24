import Foundation
import Synchronization

public func verifyAtomicAPIs() {
    let atomic = Atomic<Int>(0)
    let val = atomic.load(ordering: .relaxed)
    atomic.store(val + 1, ordering: .relaxed)
    _ = atomic.wrappingAdd(1, ordering: .relaxed)
}
