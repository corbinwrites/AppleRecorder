import Testing
import Foundation
@testable import Core

@Suite struct CapsuleStateTests {
    @Test func idleMapsToIdle() {
        #expect(capsuleState(session: .idle, stage: nil, failedStage: nil) == .idle)
    }

    @Test func armedMapsToArmed() {
        #expect(capsuleState(session: .armed, stage: nil, failedStage: nil) == .armed)
    }

    @Test func recordingMapsToRecording() {
        #expect(capsuleState(session: .recording, stage: nil, failedStage: nil) == .recording)
    }

    @Test func stoppedMapsToStopped() {
        #expect(capsuleState(session: .stopped, stage: nil, failedStage: nil) == .stopped)
    }

    @Test func processingWithStage() {
        #expect(capsuleState(session: .processing, stage: .transcribing, failedStage: nil) == .processing(.transcribing))
    }

    @Test func processingWithNilStageDefaultsToLoadingModel() {
        #expect(capsuleState(session: .processing, stage: nil, failedStage: nil) == .processing(.loadingModel))
    }

    @Test func doneMapsToDone() {
        #expect(capsuleState(session: .done, stage: nil, failedStage: nil) == .done)
    }

    @Test func failedWithStage() {
        #expect(capsuleState(session: .failed, stage: nil, failedStage: "transcribing") == .failed("transcribing"))
    }

    @Test func failedWithNilDefaultsToUnknown() {
        #expect(capsuleState(session: .failed, stage: nil, failedStage: nil) == .failed("unknown"))
    }
}
