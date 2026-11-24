import Foundation
import Core
import Enhance
import Output

public struct ProcessingDependencies: Sendable {
    public var transcribe: @Sendable (_ audio: URL, _ mode: CaptureMode, _ vocabulary: [String],
        _ progress: @escaping @Sendable (Double) -> Void) async throws -> [TranscriptSegment]
    public var unloadTranscriber: @Sendable () async -> Void
    public var enhance: @Sendable (_ segments: [TranscriptSegment], _ userNotes: String,
        _ progress: @escaping @Sendable (PipelineProgress) -> Void) async -> PipelineResult
    public var writeMarkdown: @Sendable (_ doc: NoteDocument) async throws -> URL
    public var loadTranscript: @Sendable (_ id: UUID) async -> [TranscriptSegment]?
    public var saveTranscript: @Sendable (_ id: UUID, _ segs: [TranscriptSegment]) async throws -> Void

    public init(
        transcribe: @escaping @Sendable (URL, CaptureMode, [String], @escaping @Sendable (Double) -> Void) async throws -> [TranscriptSegment],
        unloadTranscriber: @escaping @Sendable () async -> Void,
        enhance: @escaping @Sendable ([TranscriptSegment], String, @escaping @Sendable (PipelineProgress) -> Void) async -> PipelineResult,
        writeMarkdown: @escaping @Sendable (NoteDocument) async throws -> URL,
        loadTranscript: @escaping @Sendable (UUID) async -> [TranscriptSegment]?,
        saveTranscript: @escaping @Sendable (UUID, [TranscriptSegment]) async throws -> Void
    ) {
        self.transcribe = transcribe; self.unloadTranscriber = unloadTranscriber; self.enhance = enhance
        self.writeMarkdown = writeMarkdown; self.loadTranscript = loadTranscript; self.saveTranscript = saveTranscript
    }
}

public enum CoordinatorError: Error, Sendable, Equatable { case invalidState }

public actor ProcessingCoordinator {
    private let store: any SessionStore
    private let settings: AppSettings
    private let deps: ProcessingDependencies
    private let onStage: @Sendable (ProcessingStage) -> Void

    public init(store: any SessionStore, settings: AppSettings, deps: ProcessingDependencies,
                onStage: @escaping @Sendable (ProcessingStage) -> Void) {
        self.store = store; self.settings = settings; self.deps = deps; self.onStage = onStage
    }

    public func run(sessionID: UUID, forceRetranscribe: Bool = false) async throws -> Session {
        var session = try await store.load(id: sessionID)
        guard session.state == .stopped || session.state == .failed || session.state == .done else {
            throw CoordinatorError.invalidState
        }
        if Task.isCancelled {
            session.state = .stopped
            try await store.save(session)
            throw CancellationError()
        }
        session.state = .processing
        session.failure = nil
        try await store.save(session)

        var transcript: [TranscriptSegment]
        let cached = forceRetranscribe ? nil : await deps.loadTranscript(sessionID)
        if let cached {
            transcript = cached
        } else {
            guard let audioPath = session.audioPath else {
                return try await fail(session, stage: "transcribing", error: CoordinatorError.invalidState)
            }
            onStage(.loadingModel)
            onStage(.transcribing)
            do {
                transcript = try await deps.transcribe(URL(fileURLWithPath: audioPath), session.mode, settings.vocabulary) { _ in }
                try Task.checkCancellation()
            } catch {
                if error is CancellationError || Task.isCancelled {
                    session.state = .stopped; session.failure = nil
                    try await store.save(session)
                    throw CancellationError()
                }
                return try await fail(session, stage: "transcribing", error: error)
            }
            onStage(.merging)
            transcript = transcript.map { segment in
                TranscriptSegment(start: segment.start, end: segment.end, text: segment.text,
                                  speaker: session.mode.labelsSpeakers ? .me : nil)
            }
            do { try await deps.saveTranscript(sessionID, transcript) }
            catch { return try await fail(session, stage: "merging", error: error) }
        }

        if Task.isCancelled {
            session.state = .stopped; session.failure = nil
            try await store.save(session)
            throw CancellationError()
        }
        await deps.unloadTranscriber()
        onStage(.loadingNotesModel)
        onStage(.enhancing)
        let userNotes = (try? await store.loadNotes(for: sessionID)) ?? ""
        let result = await deps.enhance(transcript, userNotes) { _ in }

        if Task.isCancelled {
            session.state = .stopped; session.failure = nil
            try await store.save(session)
            throw CancellationError()
        }
        onStage(.writing)
        let audio = session.audioPath.map { AudioReference.absolute(URL(fileURLWithPath: $0)) }
        let document = NoteDocument(title: session.title, created: session.createdAt,
            durationSeconds: session.durationSeconds ?? 0, sourceApp: session.sourceAppName,
            mode: session.mode, audio: audio, transcriptionModel: settings.transcriptionModel,
            notesModel: settings.notesModel, notes: result.notes,
            enhancementWarning: result.notes == nil ? result.warnings.joined(separator: "\n") : nil,
            userNotes: userNotes,
            transcript: transcript.map { segment in
                TranscriptSegment(start: segment.start, end: segment.end, text: segment.text,
                    speaker: session.mode.labelsSpeakers ? segment.speaker : nil)
            })
        do {
            let notesURL = try await deps.writeMarkdown(document)
            try Task.checkCancellation()
            session.notesPath = notesURL.path
            session.transcriptionModel = settings.transcriptionModel
            session.notesModel = settings.notesModel
            session.state = .done
            session.failure = nil
            try await store.save(session)
            return session
        } catch {
            if error is CancellationError || Task.isCancelled {
                session.state = .stopped; session.failure = nil
                try await store.save(session)
                throw CancellationError()
            }
            return try await fail(session, stage: "writing", error: error)
        }
    }

    private func fail(_ session: Session, stage: String, error: any Error) async throws -> Session {
        var failed = session
        failed.state = .failed
        failed.failure = FailureInfo(stage: stage, message: error.localizedDescription)
        try await store.save(failed)
        throw error
    }
}
