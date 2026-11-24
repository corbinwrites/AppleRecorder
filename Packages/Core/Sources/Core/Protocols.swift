import Foundation

public struct RawSegment: Sendable, Equatable {
    public var start: Double
    public var end: Double
    public var text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

public protocol TranscriptionEngine: Sendable {
    func transcribe(audioFile: URL, vocabulary: [String],
                    onProgress: @escaping @Sendable (Double) -> Void) async throws -> [RawSegment]
}

public protocol TokenCounter: Sendable {
    func tokens(in text: String) async throws -> Int
}

public struct ChunkDigest: Codable, Sendable, Equatable {
    public var topics: [String]
    public var decisions: [String]
    public var actionItems: [String]
    public var questions: [String]
    public var keyPoints: [String]
    public var unavailable: Bool            // true = summary failed for this chunk (placeholder)

    public init(topics: [String], decisions: [String], actionItems: [String], questions: [String], keyPoints: [String], unavailable: Bool = false) {
        self.topics = topics
        self.decisions = decisions
        self.actionItems = actionItems
        self.questions = questions
        self.keyPoints = keyPoints
        self.unavailable = unavailable
    }

    public static let empty = ChunkDigest(topics: [], decisions: [], actionItems: [], questions: [], keyPoints: [], unavailable: false)
}

public struct MeetingNotesResult: Codable, Sendable, Equatable {
    public var summary: String
    public var decisions: [String]
    public var actionItems: [String]
    public var openQuestions: [String]
    public var expandedNotes: String

    public init(summary: String, decisions: [String], actionItems: [String], openQuestions: [String], expandedNotes: String) {
        self.summary = summary
        self.decisions = decisions
        self.actionItems = actionItems
        self.openQuestions = openQuestions
        self.expandedNotes = expandedNotes
    }
}

public enum GeneratorError: Error, Sendable, Equatable {
    case contextExceeded, refused, rateLimited, unavailable(String)
}

public protocol NotesGenerator: Sendable {
    func digest(transcriptChunk: String) async throws -> ChunkDigest
    func merge(digests: [ChunkDigest]) async throws -> ChunkDigest
    func finalize(userNotes: String, merged: ChunkDigest) async throws -> MeetingNotesResult
}
