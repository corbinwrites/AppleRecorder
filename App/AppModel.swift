import Foundation
import Observation

@Observable
@MainActor
public final class AppModel {
    public var isRecording: Bool = false

    public init() {}
}
