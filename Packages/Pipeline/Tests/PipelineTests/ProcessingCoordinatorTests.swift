import Testing
import Foundation
import os
@testable import Pipeline
import Core
import Enhance
import Output
import CoreTestSupport

private enum TestFailure: Error { case expected }

private actor AsyncGate {
    private var suspended = false
    private var entered = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    func suspend() { suspended = true }
    func pauseIfSuspended() async {
        guard suspended else { return }
        entered = true
        enteredContinuation?.resume(); enteredContinuation = nil
        await withCheckedContinuation { releaseContinuation = $0 }
    }
    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredContinuation = $0 }
    }
    func release() { suspended = false; releaseContinuation?.resume(); releaseContinuation = nil }
}

private actor PipelineTestStore: SessionStore {
    nonisolated let root: URL
    private var sessions: [UUID: Session] = [:]
    private var notes: [UUID: String] = [:]

    init(root: URL) { self.root = root }
    func seed(_ session: Session) { sessions[session.id] = session }
    func create(title: String, mode: CaptureMode) async throws -> Session {
        let session = Session(title: title, mode: mode); sessions[session.id] = session; return session
    }
    func save(_ session: Session) async throws { sessions[session.id] = session }
    func load(id: UUID) async throws -> Session {
        guard let session = sessions[id] else { throw TestFailure.expected }
        return session
    }
    func list() async throws -> [Session] { Array(sessions.values) }
    func saveNotes(_ markdown: String, for id: UUID) async throws { notes[id] = markdown }
    func loadNotes(for id: UUID) async throws -> String {
        guard let value = notes[id] else { throw CocoaError(.fileReadNoSuchFile) }
        return value
    }
    func delete(id: UUID) async throws { sessions.removeValue(forKey: id); notes.removeValue(forKey: id) }
    func recoverInterrupted() async throws -> [Session] { [] }
    nonisolated func sessionDirectory(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString) }
}

private actor PipelineRecorder {
    private var _calls: [String] = []
    private var _document: NoteDocument?
    private var _transcript: [TranscriptSegment] = []
    private var cached: [TranscriptSegment]?
    private var transcriptError = false
    private var writeError = false
    private var result = PipelineResult(notes: MeetingNotesResult(summary: "Summary", decisions: [], actionItems: [], openQuestions: [], expandedNotes: "Notes"), warnings: [], digests: [])
    private var transcriptValue = [TranscriptSegment(start: 1, end: 2, text: "Words")]
    let transcribeGate = AsyncGate()

    var calls: [String] { _calls }
    var document: NoteDocument? { _document }
    var savedTranscript: [TranscriptSegment] { _transcript }
    func call(_ value: String) { _calls.append(value) }
    func save(_ value: NoteDocument) { _document = value }
    func save(_ value: [TranscriptSegment]) { _transcript = value }
    func setCached(_ value: [TranscriptSegment]?) { cached = value }
    func setTranscriptError(_ value: Bool) { transcriptError = value }
    func setWriteError(_ value: Bool) { writeError = value }
    func setResult(_ value: PipelineResult) { result = value }
    func setTranscript(_ value: [TranscriptSegment]) { transcriptValue = value }
    func loadTranscript() -> [TranscriptSegment]? { cached }
    func transcribe() async throws -> [TranscriptSegment] {
        _calls.append("transcribe")
        await transcribeGate.pauseIfSuspended()
        try Task.checkCancellation()
        if transcriptError { throw TestFailure.expected }
        return transcriptValue
    }
    func enhance(_ segments: [TranscriptSegment], notes: String) -> PipelineResult {
        _calls.append("enhance")
        _calls.append("enhanceNotes:\(notes)")
        _transcript = segments
        return result
    }
    func write(_ document: NoteDocument) throws -> URL {
        _calls.append("writeMarkdown")
        _document = document
        if writeError { throw TestFailure.expected }
        return URL(fileURLWithPath: "/tmp/Test.md")
    }
}

@Suite struct ProcessingCoordinatorTests {
    private func makeSession(mode: CaptureMode = .appAndMic, state: SessionState = .stopped) -> Session {
        Session(id: UUID(), title: "Test", createdAt: Date(timeIntervalSince1970: 1_700_000_000), mode: mode,
            state: state, durationSeconds: 12, audioPath: "/tmp/recording.m4a", notesPath: "/tmp/old.md")
    }

    private func setup(_ session: Session, recorder: PipelineRecorder = PipelineRecorder()) async throws -> (PipelineTestStore, ProcessingCoordinator, PipelineRecorder, OSAllocatedUnfairLock<[ProcessingStage]>) {
        let store = PipelineTestStore(root: URL(fileURLWithPath: "/tmp/ar-pipeline-tests"))
        let stages = OSAllocatedUnfairLock(initialState: [ProcessingStage]())
        await store.seed(session)
        try await store.saveNotes("Original user notes\nKeep exactly", for: session.id)
        let deps = ProcessingDependencies(
            transcribe: { _, _, _, _ in
                try await recorder.transcribe()
            },
            unloadTranscriber: { await recorder.call("unloadTranscriber") },
            enhance: { segments, notes, _ in
                await recorder.enhance(segments, notes: notes)
            },
            writeMarkdown: { document in
                try await recorder.write(document)
            },
            loadTranscript: { _ in await recorder.call("loadTranscript"); return await recorder.loadTranscript() },
            saveTranscript: { _, segments in await recorder.call("saveTranscript"); await recorder.save(segments) }
        )
        let coordinator = ProcessingCoordinator(store: store, settings: AppSettings(transcriptionModel: "whisper-small", notesModel: "apple-fm"), deps: deps) { stage in
            stages.withLock { $0.append(stage) }
        }
        return (store, coordinator, recorder, stages)
    }

    @Test func happyPathStageOrder() async throws {
        let original = makeSession()
        let (store, coordinator, _, stages) = try await setup(original)
        let result = try await coordinator.run(sessionID: original.id)
        #expect(stages.withLock { $0 } == [.loadingModel, .transcribing, .merging, .loadingNotesModel, .enhancing, .writing])
        #expect(result.state == .done && result.notesPath == "/tmp/Test.md")
        #expect(try await store.load(id: original.id).state == .done)
    }

    @Test func whisperUnloadedBeforeEnhancement() async throws {
        let original = makeSession()
        let (_, coordinator, recorder, _) = try await setup(original)
        _ = try await coordinator.run(sessionID: original.id)
        let calls = await recorder.calls
        #expect((calls.firstIndex(of: "transcribe") ?? 99) < (calls.firstIndex(of: "unloadTranscriber") ?? 0))
        #expect((calls.firstIndex(of: "unloadTranscriber") ?? 99) < (calls.firstIndex(of: "enhance") ?? 0))
    }

    @Test func existingTranscriptSkipsTranscriptionUnlessForced() async throws {
        var original = makeSession()
        let (store, coordinator, recorder, stages) = try await setup(original)
        await recorder.setCached([TranscriptSegment(start: 4, end: 5, text: "cached")])
        _ = try await coordinator.run(sessionID: original.id)
        #expect(!(await recorder.calls).contains("transcribe"))
        #expect(stages.withLock { $0 } == [.loadingNotesModel, .enhancing, .writing])

        original.state = .done
        await store.seed(original)
        await recorder.setCached([TranscriptSegment(start: 4, end: 5, text: "cached")])
        await recorder.setTranscript([TranscriptSegment(start: 8, end: 9, text: "fresh")])
        _ = try await coordinator.run(sessionID: original.id, forceRetranscribe: true)
        #expect((await recorder.calls).filter { $0 == "transcribe" }.count == 1)
    }

    @Test func transcribeFailurePersistsStageAndPreservesPaths() async throws {
        let original = makeSession()
        let (store, coordinator, recorder, _) = try await setup(original)
        await recorder.setTranscriptError(true)
        do { _ = try await coordinator.run(sessionID: original.id); Issue.record("expected transcription error") }
        catch is TestFailure {}
        let failed = try await store.load(id: original.id)
        #expect(failed.state == .failed && failed.failure?.stage == "transcribing")
        #expect(failed.audioPath == original.audioPath && failed.notesPath == original.notesPath)
        let calls = await recorder.calls
        #expect(!calls.contains("enhance") && !calls.contains("writeMarkdown"))
    }

    @Test func unavailableEnhancementStillWritesOriginalInputs() async throws {
        let original = makeSession()
        let (store, coordinator, recorder, _) = try await setup(original)
        await recorder.setResult(PipelineResult(notes: nil, warnings: ["Apple Intelligence unavailable: off"], digests: []))
        _ = try await coordinator.run(sessionID: original.id)
        let doc = try #require(await recorder.document)
        #expect(doc.notes == nil && doc.enhancementWarning?.contains("off") == true)
        #expect(doc.userNotes == "Original user notes\nKeep exactly")
        #expect(doc.transcript.map(\.text) == ["Words"])
        #expect((await recorder.calls).contains("enhanceNotes:Original user notes\nKeep exactly"))
        #expect(try await store.load(id: original.id).state == .done)
    }

    @Test func writeFailureAndMicOnlySpeakerLabels() async throws {
        let original = makeSession(mode: .micOnly)
        let (store, coordinator, recorder, _) = try await setup(original)
        await recorder.setWriteError(true)
        do { _ = try await coordinator.run(sessionID: original.id); Issue.record("expected write error") }
        catch is TestFailure {}
        let failed = try await store.load(id: original.id)
        #expect(failed.state == .failed && failed.failure?.stage == "writing")
        #expect(failed.audioPath == original.audioPath && failed.notesPath == original.notesPath)
        #expect(await recorder.document?.transcript.allSatisfy { $0.speaker == nil } == true)
    }

    @Test func invalidStatesAreRejected() async throws {
        for state: SessionState in [.recording, .armed, .idle, .processing] {
            let session = makeSession(state: state)
            let (_, coordinator, _, _) = try await setup(session)
            await #expect(throws: CoordinatorError.invalidState) { try await coordinator.run(sessionID: session.id) }
        }
    }

    @Test func cancellationBeforeWorkStopsAndWritesNoMarkdown() async throws {
        let original = makeSession()
        let (store, coordinator, recorder, _) = try await setup(original)
        let task = Task { try await coordinator.run(sessionID: original.id) }
        task.cancel()
        do { _ = try await task.value; Issue.record("expected cancellation") }
        catch is CancellationError {}
        #expect(try await store.load(id: original.id).state == .stopped)
        #expect(!(await recorder.calls).contains("writeMarkdown"))
    }

    @Test func cancellationDuringTranscriptionStopsWithoutWriting() async throws {
        let original = makeSession()
        let (store, coordinator, recorder, _) = try await setup(original)
        await recorder.transcribeGate.suspend()
        let task = Task { try await coordinator.run(sessionID: original.id) }
        await recorder.transcribeGate.waitUntilEntered()
        task.cancel()
        await recorder.transcribeGate.release()
        do { _ = try await task.value; Issue.record("expected cancellation") }
        catch is CancellationError {}
        let session = try await store.load(id: original.id)
        #expect(session.state == .stopped && session.failure == nil)
        #expect(!(await recorder.calls).contains("writeMarkdown"))
    }
}
