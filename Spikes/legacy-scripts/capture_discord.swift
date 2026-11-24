import Foundation
import CoreAudio
import AudioToolbox

// L1 Spike: tap all matching process objects (or one `pid:<n>`) and record a sample.
// Run directly with `swift Scripts/capture_discord.swift discord 10 /private/tmp/discord_tap_test.m4a` (no package build).

func findProcessObjectIDs(matching target: String) -> [AudioObjectID] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize)
    let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
    var processIDs = [AudioObjectID](repeating: 0, count: count)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &processIDs)
    var matches: [AudioObjectID] = []
    
    for objID in processIDs {
        var pidAddr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var pid: pid_t = 0; var pidSize = UInt32(MemoryLayout<pid_t>.size)
        if AudioObjectGetPropertyData(objID, &pidAddr, 0, nil, &pidSize, &pid) == noErr {
            var buffer = [CChar](repeating: 0, count: 4096)
            let path = proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : ""
            let matchesPID = target.hasPrefix("pid:") && Int32(target.dropFirst(4)) == pid
            let matchesPath = !target.hasPrefix("pid:") && path.lowercased().contains(target.lowercased())
            if matchesPID || matchesPath {
                print("Found \(target): ObjectID=\(objID), PID=\(pid), path=\(path)")
                matches.append(objID)
            }
        }
    }
    return matches
}

let target = CommandLine.arguments.dropFirst().first ?? "discord"
let durationSeconds = max(1, Int(CommandLine.arguments.dropFirst(2).first ?? "10") ?? 10)
let outputPath = CommandLine.arguments.dropFirst(3).first ?? "/private/tmp/discord_tap_test.m4a"
let processObjectIDs = findProcessObjectIDs(matching: target)
guard !processObjectIDs.isEmpty else {
    print("\(target) not found in CoreAudio process list (not playing audio?)")
    exit(1)
}

// Create tap
let desc = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
var tapID: AudioObjectID = 0
var status = AudioHardwareCreateProcessTap(desc, &tapID)
print("CreateProcessTap: \(status), tapID: \(tapID)")

// Get tap UID
var uidAddress = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var tapUIDCF: Unmanaged<CFString>?
var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
status = AudioObjectGetPropertyData(tapID, &uidAddress, 0, nil, &uidSize, &tapUIDCF)
let tapUID = tapUIDCF!.takeRetainedValue() as String
print("Tap UID: \(tapUID)")

// Create aggregate device
let aggUID = UUID().uuidString
let aggDesc: [String: Any] = [
    kAudioAggregateDeviceNameKey: "DiscordTap",
    kAudioAggregateDeviceUIDKey: aggUID,
    kAudioAggregateDeviceIsPrivateKey: 1,
    kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID]]
]
var aggDeviceID: AudioObjectID = 0
status = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggDeviceID)
print("CreateAggregateDevice: \(status), aggDeviceID: \(aggDeviceID)")

// Setup m4a writer
let outputURL = URL(fileURLWithPath: outputPath)
try? FileManager.default.removeItem(at: outputURL)

var dstFormat = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: 0,
    mBytesPerPacket: 0, mFramesPerPacket: 1024, mBytesPerFrame: 0, mChannelsPerFrame: 2, mBitsPerChannel: 0, mReserved: 0)
var audioFile: ExtAudioFileRef?
status = ExtAudioFileCreateWithURL(outputURL as CFURL, kAudioFileM4AType, &dstFormat, nil, AudioFileFlags.eraseFile.rawValue, &audioFile)
print("ExtAudioFileCreateWithURL: \(status)")

var clientFormat = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
    mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 8,
    mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
status = ExtAudioFileSetProperty(audioFile!, kExtAudioFileProperty_ClientDataFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &clientFormat)

// IOProc: writes audio to file
class RecordingState {
    var audioFile: ExtAudioFileRef?
    var frameCount: Int = 0
    var maxFrames: Int = 48000 * durationSeconds
    var done = false
}
var recState = RecordingState()
recState.audioFile = audioFile

var procID: AudioDeviceIOProcID?
status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggDeviceID, nil) { (_, inInputData, _, _, _) in
    guard !recState.done, let file = recState.audioFile else { return }
    let bufferList = UnsafeMutablePointer(mutating: inInputData)
    let frames = bufferList.pointee.mBuffers.mDataByteSize / 8
    recState.frameCount += Int(frames)
    ExtAudioFileWrite(file, frames, bufferList)
    if recState.frameCount >= recState.maxFrames {
        recState.done = true
    }
}

let startTime = Date()
status = AudioDeviceStart(aggDeviceID, procID!)
print("AudioDeviceStart: \(status)")
print("Recording \(durationSeconds) seconds from \(target)...")

// Wait for recording to complete
while !recState.done {
    Thread.sleep(forTimeInterval: 0.1)
    if Date().timeIntervalSince(startTime) > Double(durationSeconds + 5) {
        print("Timeout — \(target) may not be playing audio")
        break
    }
}

let elapsed = Date().timeIntervalSince(startTime)
print("Captured \(recState.frameCount) frames in \(String(format: "%.1f", elapsed))s")
print("CPU time approx: n/a (need Instruments for accurate measurement)")

AudioDeviceStop(aggDeviceID, procID!)
AudioDeviceDestroyIOProcID(aggDeviceID, procID!)
ExtAudioFileDispose(audioFile!)
AudioHardwareDestroyAggregateDevice(aggDeviceID)
AudioHardwareDestroyProcessTap(tapID)

if let attr = try? FileManager.default.attributesOfItem(atPath: outputURL.path) {
    print("Output: \(outputURL.path), size: \(attr[.size] ?? 0) bytes")
}
