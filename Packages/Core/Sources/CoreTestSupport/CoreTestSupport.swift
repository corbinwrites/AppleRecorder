import Foundation
import Core

public struct CharTokenCounter: TokenCounter {             // deterministic: ceil(chars / perToken)
    public let perToken: Int
    public init(perToken: Int = 4) { self.perToken = perToken }
    public func tokens(in text: String) async throws -> Int { (text.count + perToken - 1) / perToken }
}

public final class FakeNotesGenerator: NotesGenerator, @unchecked Sendable {
    private let lock = NSLock()
    private var _digests: [String] = [], _merges: [[ChunkDigest]] = [], _finals: [(notes: String, merged: ChunkDigest)] = []
    public var onDigest: @Sendable (String) throws -> ChunkDigest = { _ in .empty }
    public var onMerge: @Sendable ([ChunkDigest]) throws -> ChunkDigest = { _ in .empty }
    public var onFinalize: @Sendable (String, ChunkDigest) throws -> MeetingNotesResult = { _, _ in
        MeetingNotesResult(summary: "S", decisions: [], actionItems: [], openQuestions: [], expandedNotes: "") }
    public init() {}
    public var digestInputs: [String] { lock.withLock { _digests } }
    public var mergeInputs: [[ChunkDigest]] { lock.withLock { _merges } }
    public var finalizeInputs: [(notes: String, merged: ChunkDigest)] { lock.withLock { _finals } }
    public func digest(transcriptChunk: String) async throws -> ChunkDigest {
        lock.withLock { _digests.append(transcriptChunk) }          // record first, then run the closure outside the lock
        return try onDigest(transcriptChunk)
    }
    public func merge(digests: [ChunkDigest]) async throws -> ChunkDigest {
        lock.withLock { _merges.append(digests) }
        return try onMerge(digests)
    }
    public func finalize(userNotes: String, merged: ChunkDigest) async throws -> MeetingNotesResult {
        lock.withLock { _finals.append((userNotes, merged)) }
        return try onFinalize(userNotes, merged)
    }
}

public struct FakeTranscriptionEngine: TranscriptionEngine {
    public var result: [RawSegment]; public var error: (any Error)?
    public init(result: [RawSegment] = [], error: (any Error)? = nil) { self.result = result; self.error = error }
    public func transcribe(audioFile: URL, vocabulary: [String], onProgress: @escaping @Sendable (Double) -> Void) async throws -> [RawSegment] {
        onProgress(0.5); if let error { throw error }; onProgress(1); return result
    }
}

public func temporaryDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("ar-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
public func / (lhs: URL, rhs: String) -> URL { lhs.appendingPathComponent(rhs) }       // used by tests: dir/"mic.caf"
