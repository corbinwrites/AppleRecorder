import Foundation

public enum CapsuleState: Equatable, Sendable {
    case idle, armed, recording, stopped, processing(ProcessingStage), done, failed(String)
}

public func capsuleState(session: SessionState, stage: ProcessingStage?, failedStage: String?) -> CapsuleState {
    switch session {
    case .idle: .idle
    case .armed: .armed
    case .recording: .recording
    case .stopped: .stopped
    case .processing: .processing(stage ?? .loadingModel)
    case .done: .done
    case .failed: .failed(failedStage ?? "unknown")
    }
}
