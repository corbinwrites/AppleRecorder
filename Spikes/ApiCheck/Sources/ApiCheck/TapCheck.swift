import Foundation
import CoreAudio

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
