import Foundation
import AVFoundation

public func verifyMicAPIs() {
    let engine = AVAudioEngine()
    let mixer = engine.mainMixerNode
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    mixer.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, when in
        _ = when.hostTime
        _ = buffer.floatChannelData
    }
    
    // Selected input device: AudioUnitSetProperty(kAudioOutputUnitProperty_CurrentDevice)
    if let unit = engine.inputNode.audioUnit {
        var deviceID: AudioDeviceID = 0
        _ = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }
}
