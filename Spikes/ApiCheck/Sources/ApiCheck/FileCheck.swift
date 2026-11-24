import Foundation
import AVFoundation

public func verifyFileAPIs() throws {
    let tempCAF = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test.caf")
    let cafSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 48000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false
    ]
    _ = try AVAudioFile(forWriting: tempCAF, settings: cafSettings)
    
    let tempM4A = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test.m4a")
    let m4aSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 48000.0,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 128000
    ]
    _ = try AVAudioFile(forWriting: tempM4A, settings: m4aSettings)
    
    let inFormat = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1)!
    let outFormat = AVAudioFormat(standardFormatWithSampleRate: 48000.0, channels: 1)!
    _ = AVAudioConverter(from: inFormat, to: outFormat)
}
