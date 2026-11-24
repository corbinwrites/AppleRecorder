// Packages/Capture/Sources/Capture/RealtimeCallback.swift
import CoreAudio

/// Builds the IO block for the tap's aggregate device. `firstHostTime` points to preallocated storage owned by TapSession.
public func makeTapIOBlock(ring: RingBuffer,
                           firstHostTime: UnsafeMutablePointer<UInt64>) -> AudioDeviceIOBlock {
    return { _, inInputData, inInputTime, _, _ in
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
        guard let buffer = list.first, let raw = buffer.mData else { return }
        if firstHostTime.pointee == 0 { firstHostTime.pointee = inInputTime.pointee.mHostTime }
        let samples = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        _ = ring.write(raw.assumingMemoryBound(to: Float.self), count: samples)
    }
}
