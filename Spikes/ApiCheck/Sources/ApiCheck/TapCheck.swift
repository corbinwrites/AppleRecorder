import Foundation
import CoreAudio
import Darwin

public func verifyTimebaseAPI() {
    var tb = mach_timebase_info_data_t()
    precondition(mach_timebase_info(&tb) == KERN_SUCCESS && tb.denom != 0)
}

public func verifyTapAPIs() {
    let desc = CATapDescription(monoMixdownOfProcesses: [AudioObjectID(123)])
    desc.uuid = UUID()
    desc.muteBehavior = .unmuted
    desc.isPrivate = true
    
    var tapID = AudioObjectID(kAudioObjectUnknown)
    _ = AudioHardwareCreateProcessTap(desc, &tapID)
    _ = AudioHardwareDestroyProcessTap(tapID)
    
    _ = AudioObjectPropertyAddress(
        mSelector: kAudioTapPropertyFormat,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    _ = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    _ = AudioObjectPropertyAddress(
        mSelector: kAudioProcessPropertyIsRunningOutput,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    _ = AudioObjectPropertyAddress(
        mSelector: kAudioProcessPropertyPID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    _ = AudioObjectPropertyAddress(
        mSelector: kAudioProcessPropertyBundleID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
}
