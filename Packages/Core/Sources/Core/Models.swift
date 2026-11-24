import Foundation

public enum CaptureMode: String, Codable, Sendable, CaseIterable {
    case appAndMic, micOnly, appOnly
    public var hasMic: Bool { self != .appOnly }
    public var hasApp: Bool { self != .micOnly }
    public var channelCount: Int { self == .appAndMic ? 2 : 1 }
    public var labelsSpeakers: Bool { self == .appAndMic }
    public var frontmatterValue: String {
        switch self { case .appAndMic: "app+mic"; case .micOnly: "mic"; case .appOnly: "app" }
    }
}

public enum SessionState: String, Codable, Sendable, CaseIterable {
    case idle, armed, recording, stopped, processing, done, failed

    public static let allowed: [SessionState: Set<SessionState>] = [
        .idle:       [.armed, .stopped],        // .stopped directly = imported audio
        .armed:      [.recording, .idle],
        .recording:  [.stopped, .failed],
        .stopped:    [.processing, .idle],      // .idle = discard
        .processing: [.done, .failed],
        .failed:     [.processing, .idle],      // retry or discard
        .done:       [.processing, .idle],      // re-transcribe or discard
    ]
    public func canTransition(to next: SessionState) -> Bool { Self.allowed[self]?.contains(next) ?? false }
}

public enum Speaker: String, Codable, Sendable { case me = "Me", them = "Them" }

public struct TranscriptSegment: Codable, Sendable, Equatable {
    public var start: Double        // seconds from recording start
    public var end: Double
    public var text: String
    public var speaker: Speaker?    // nil unless mode == .appAndMic

    public init(start: Double, end: Double, text: String, speaker: Speaker? = nil) {
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
    }
}

public struct TrackTiming: Codable, Sendable, Equatable {
    public var firstHostNanos: UInt64   // host time of first sample, in nanoseconds
    public var sampleRate: Double
    public var frames: Int64
    public var tempFileName: String     // e.g. "mic.caf" inside <session>/recording/

    public init(firstHostNanos: UInt64, sampleRate: Double, frames: Int64, tempFileName: String) {
        self.firstHostNanos = firstHostNanos
        self.sampleRate = sampleRate
        self.frames = frames
        self.tempFileName = tempFileName
    }
}

public struct Gap: Codable, Sendable, Equatable {
    public var atSeconds: Double
    public var reason: String

    public init(atSeconds: Double, reason: String) {
        self.atSeconds = atSeconds
        self.reason = reason
    }
}

public struct FailureInfo: Codable, Sendable, Equatable {
    public var stage: String
    public var message: String

    public init(stage: String, message: String) {
        self.stage = stage
        self.message = message
    }
}

public struct Session: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var mode: CaptureMode
    public var sourceAppName: String?
    public var sourceBundleID: String?
    public var state: SessionState
    public var durationSeconds: Double?
    public var audioPath: String?        // absolute path of canonical .m4a
    public var notesPath: String?        // absolute path of exported .md
    public var micTrack: TrackTiming?
    public var appTrack: TrackTiming?
    public var gaps: [Gap]
    public var transcriptionModel: String?
    public var notesModel: String?
    public var failure: FailureInfo?
    public var recoveredFromCrash: Bool

    public init(title: String, mode: CaptureMode) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.mode = mode
        self.sourceAppName = nil
        self.sourceBundleID = nil
        self.state = .idle
        self.durationSeconds = nil
        self.audioPath = nil
        self.notesPath = nil
        self.micTrack = nil
        self.appTrack = nil
        self.gaps = []
        self.transcriptionModel = nil
        self.notesModel = nil
        self.failure = nil
        self.recoveredFromCrash = false
    }

    public init(
        id: UUID,
        title: String,
        createdAt: Date,
        mode: CaptureMode,
        sourceAppName: String? = nil,
        sourceBundleID: String? = nil,
        state: SessionState = .idle,
        durationSeconds: Double? = nil,
        audioPath: String? = nil,
        notesPath: String? = nil,
        micTrack: TrackTiming? = nil,
        appTrack: TrackTiming? = nil,
        gaps: [Gap] = [],
        transcriptionModel: String? = nil,
        notesModel: String? = nil,
        failure: FailureInfo? = nil,
        recoveredFromCrash: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.mode = mode
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
        self.state = state
        self.durationSeconds = durationSeconds
        self.audioPath = audioPath
        self.notesPath = notesPath
        self.micTrack = micTrack
        self.appTrack = appTrack
        self.gaps = gaps
        self.transcriptionModel = transcriptionModel
        self.notesModel = notesModel
        self.failure = failure
        self.recoveredFromCrash = recoveredFromCrash
    }
}
