import Foundation
import CoreAudio

public func verifyAggregateAPIs() {
    let outUID = "BuiltInSpeakerDevice"
    let dict: [String: Any] = [
        kAudioAggregateDeviceNameKey: "AppleRecorder Tap",
        kAudioAggregateDeviceUIDKey: UUID().uuidString,
        kAudioAggregateDeviceMainSubDeviceKey: outUID,
        kAudioAggregateDeviceIsPrivateKey: true,
        kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outUID]],
        kAudioAggregateDeviceTapListKey: [[
            kAudioSubTapDriftCompensationKey: true,
            kAudioSubTapUIDKey: UUID().uuidString
        ]]
    ]
    var aggID = AudioObjectID(kAudioObjectUnknown)
    _ = AudioHardwareCreateAggregateDevice(dict as CFDictionary, &aggID)
    
    var procID: AudioDeviceIOProcID?
    let queue = DispatchQueue(label: "test.tap.queue")
    let block: AudioDeviceIOBlock = { _, _, _, _, _ in }
    _ = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, queue, block)
    if let p = procID {
        _ = AudioDeviceStart(aggID, p)
        _ = AudioDeviceStop(aggID, p)
        _ = AudioDeviceDestroyIOProcID(aggID, p)
    }
    _ = AudioHardwareDestroyAggregateDevice(aggID)
}
