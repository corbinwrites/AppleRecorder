import AVFoundation
func writeSine(to url: URL, freq: Double, seconds: Double, sampleRate: Double, amplitude: Float = 0.5) throws {
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
                                   AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
    let file = try AVAudioFile(forWriting: url, settings: settings)
    let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let n = AVAudioFrameCount(seconds * sampleRate)
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n)!; buf.frameLength = n
    for i in 0..<Int(n) { buf.floatChannelData![0][i] = amplitude * Float(sin(2 * .pi * freq * Double(i) / sampleRate)) }
    try file.write(from: buf)
}
func writeSilence(to url: URL, seconds: Double, sampleRate: Double) throws {
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
                                   AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
    let file = try AVAudioFile(forWriting: url, settings: settings)
    let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let n = AVAudioFrameCount(seconds * sampleRate)
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n)!; buf.frameLength = n
    for i in 0..<Int(n) { buf.floatChannelData![0][i] = 0 }
    try file.write(from: buf)
}
func readChannels(_ url: URL) throws -> (channels: [[Float]], sampleRate: Double) {
    let f = try AVAudioFile(forReading: url)
    let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
    try f.read(into: buf)
    let n = Int(buf.frameLength)
    return ((0..<Int(f.processingFormat.channelCount)).map { Array(UnsafeBufferPointer(start: buf.floatChannelData![$0], count: n)) }, f.processingFormat.sampleRate)
}
func goertzelPower(_ x: ArraySlice<Float>, freq: Double, rate: Double) -> Double {
    let k = 2 * cos(2 * .pi * freq / rate); var s1 = 0.0, s2 = 0.0
    for v in x { let s = Double(v) + k * s1 - s2; s2 = s1; s1 = s }
    let n = Double(x.count); return (s1 * s1 + s2 * s2 - k * s1 * s2) / (n * n)
}
func rms(_ x: ArraySlice<Float>) -> Float { sqrt(x.reduce(0) { $0 + $1 * $1 } / Float(max(x.count, 1))) }
