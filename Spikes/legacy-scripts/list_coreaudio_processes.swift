import Foundation
import CoreAudio
import AppKit

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

print("Active CoreAudio processes:")
for objID in processIDs {
    var pidAddress = AudioObjectPropertyAddress(
        mSelector: kAudioProcessPropertyPID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var pid: pid_t = 0
    var pidSize = UInt32(MemoryLayout<pid_t>.size)
    if AudioObjectGetPropertyData(objID, &pidAddress, 0, nil, &pidSize, &pid) == noErr {
        let app = NSRunningApplication(processIdentifier: pid)
        let name = app?.localizedName ?? "PID \(pid)"
        let bundleID = app?.bundleIdentifier ?? "no-bundle"
        print("  ObjectID: \(objID), PID: \(pid), Name: \(name), BundleID: \(bundleID)")
    }
}
