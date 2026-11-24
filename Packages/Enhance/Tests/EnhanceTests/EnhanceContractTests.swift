import Testing
import Foundation
import os
@testable import Enhance
import Core
import CoreTestSupport

@Suite struct EnhanceContractTests {
    private static func segment(_ text: String, start: Double = 0, speaker: Speaker? = .me) -> TranscriptSegment {
        TranscriptSegment(start: start, end: start + 1, text: text, speaker: speaker)
    }
    private static func digest(_ value: String = "digest") -> ChunkDigest {
        ChunkDigest(topics: [value], decisions: [], actionItems: [], questions: [], keyPoints: [])
    }
    private static func pipeline(_ generator: FakeNotesGenerator, budget: TokenBudget = .init()) -> NotesPipeline {
        NotesPipeline(generator: generator, counter: CharTokenCounter(perToken: 4), budget: budget, sleep: { _ in })
    }

    @Test func tokenBudgetAndPrompts() {
        let budget = TokenBudget()
        #expect(budget.chunkTokens == 1196)
        let scaled = budget.scaled(toWindow: 8192)
        #expect(scaled.window == 8192)
        #expect(abs(scaled.chunkTokens - 2392) <= 2)
        for instruction in [Prompts.digestInstructions, Prompts.mergeInstructions, Prompts.finalInstructions] {
            #expect(instruction.count <= 900)
            #expect(instruction.contains("Do not invent") || instruction.contains("Only use names"))
        }
    }

    @Test func appleIntelligenceUnavailableReasonMapping() {
        #expect(FoundationNotesGenerator.reasonString(for: .deviceNotEligible).contains("eligible"))
        #expect(FoundationNotesGenerator.reasonString(for: .appleIntelligenceNotEnabled).contains("not enabled"))
        #expect(FoundationNotesGenerator.reasonString(for: .modelNotReady).contains("not ready"))
    }

    @Test func lineFormatting() {
        #expect(Chunker.line(Self.segment("Hello", start: 12)) == "[00:12] Me: Hello")
        #expect(Chunker.line(Self.segment("x", start: 3725, speaker: nil)) == "[1:02:05] x")
        #expect(Chunker.line(TranscriptSegment(start: 1, end: 2, text: "hi", speaker: .them)) == "[00:01] Them: hi")
    }

    @Test func emptyAndCoverageBudgetAndOrder() async throws {
        let counter = CharTokenCounter(perToken: 4)
        #expect(try await Chunker.chunk([], maxTokens: 200, counter: counter).isEmpty)
        var random: UInt64 = 0xCAFE
        var segments: [TranscriptSegment] = []
        for index in 0..<300 {
            random = random &* 6364136223846793005 &+ 1
            let size = 20 + Int(random % 381)
            segments.append(Self.segment(String(repeating: "word ", count: size / 5), start: Double(index * 4)))
        }
        let chunks = try await Chunker.chunk(segments, maxTokens: 200, counter: counter)
        for chunk in chunks {
            let tokens = try await counter.tokens(in: chunk.text)
            #expect(tokens <= 200)
        }
        for index in segments.indices { #expect(chunks.contains { $0.firstSegment <= index && $0.lastSegment >= index }) }
        #expect(chunks.first?.firstSegment == 0)
        #expect(chunks.last?.lastSegment == segments.count - 1)
        for index in 1..<chunks.count {
            #expect(chunks[index].firstSegment > chunks[index - 1].firstSegment)
            #expect(chunks[index].lastSegment >= chunks[index - 1].lastSegment)
        }
    }

    @Test func overlapCanBeDisabled() async throws {
        let source = (0..<30).map { Self.segment("short \($0)", start: Double($0)) }
        let chunks = try await Chunker.chunk(source, maxTokens: 40, overlapFraction: 0, counter: CharTokenCounter())
        for index in 1..<chunks.count { #expect(chunks[index].firstSegment == chunks[index - 1].lastSegment + 1) }
    }

    @Test func defaultOverlapReusesTrailingLines() async throws {
        let source = (0..<80).map { Self.segment("short \($0)", start: Double($0)) }
        let chunks = try await Chunker.chunk(source, maxTokens: 80, counter: CharTokenCounter())
        #expect(chunks.count > 1)
        for index in 1..<chunks.count { #expect(chunks[index].firstSegment <= chunks[index - 1].lastSegment) }
    }

    @Test func oversizedLineSplitsWithinBudget() async throws {
        let words = (0..<1200).map { "w\($0)" }
        let result = try await Chunker.chunk([Self.segment(words.joined(separator: " "))], maxTokens: 100,
            overlapFraction: 0, counter: CharTokenCounter())
        #expect(result.count > 1)
        for chunk in result {
            let tokens = try await CharTokenCounter().tokens(in: chunk.text)
            #expect(tokens <= 100)
        }
        let reconstructed = result.flatMap { $0.text.components(separatedBy: " ") }.filter { !$0.hasPrefix("[") && $0 != "Me:" }
        #expect(reconstructed == words)
    }

    @Test func scaleProducesBoundedChunkCount() async throws {
        let segments = (0..<720).map { Self.segment(String(repeating: "x", count: 50), start: Double($0 * 4)) }
        let chunks = try await Chunker.chunk(segments, maxTokens: 1196, counter: CharTokenCounter())
        #expect((10...14).contains(chunks.count))
    }

    @Test func unavailableStopsPipeline() async {
        let generator = FakeNotesGenerator()
        generator.onDigest = { _ in throw GeneratorError.unavailable("off") }
        let result = await Self.pipeline(generator).run(segments: [Self.segment("hello")], userNotes: "", onProgress: { _ in })
        #expect(generator.digestInputs.count == 1)
        #expect(result.notes == nil && result.warnings.contains { $0.contains("off") })
    }

    @Test func contextExceededSplitsAndMergesAtLines() async {
        let generator = FakeNotesGenerator()
        generator.onDigest = { text in
            if text.contains("first") && text.contains("second") { throw GeneratorError.contextExceeded }
            return Self.digest(text)
        }
        let result = await Self.pipeline(generator).run(segments: [Self.segment("first"), Self.segment("second", start: 2)], userNotes: "", onProgress: { _ in })
        #expect(generator.digestInputs.count == 3)
        #expect(generator.mergeInputs.last?.count == 2)
        #expect(result.notes != nil)
    }

    @Test func refusedChunkIsSkippedWithRangeWarning() async {
        let generator = FakeNotesGenerator()
        generator.onDigest = { [unowned generator] text in
            if generator.digestInputs.count == 3 { throw GeneratorError.refused }
            return Self.digest(text)
        }
        let source = (0..<720).map { Self.segment(String(repeating: "x", count: 50), start: Double($0 * 4)) }
        let result = await Self.pipeline(generator).run(segments: source, userNotes: "", onProgress: { _ in })
        #expect(result.notes != nil)
        #expect(result.digests.filter(\.unavailable).count == 1)
        #expect(result.warnings.count == 1 && result.warnings[0].contains("Chunk 3 (") && result.warnings[0].contains("–"))
    }

    @Test func rateLimitRetriesThenSucceeds() async {
        let generator = FakeNotesGenerator()
        generator.onDigest = { [unowned generator] text in
            if generator.digestInputs.count < 3 { throw GeneratorError.rateLimited }
            return Self.digest(text)
        }
        let result = await Self.pipeline(generator).run(segments: [Self.segment("hello")], userNotes: "", onProgress: { _ in })
        #expect(generator.digestInputs.count == 3)
        #expect(result.notes != nil && result.warnings.isEmpty)
    }

    @Test func repeatedRateLimitBecomesUnavailableChunk() async {
        let generator = FakeNotesGenerator()
        generator.onDigest = { _ in throw GeneratorError.rateLimited }
        let result = await Self.pipeline(generator).run(segments: [Self.segment("hello")], userNotes: "", onProgress: { _ in })
        #expect(generator.digestInputs.count == 4)
        #expect(result.notes == nil && result.warnings.contains("No chunk could be summarized."))
    }

    @Test func reductionMergesTokenBoundedBatchesToOneDigest() async throws {
        let generator = FakeNotesGenerator()
        generator.onDigest = { _ in
            ChunkDigest(topics: [], decisions: [], actionItems: [], questions: [], keyPoints: [String(repeating: "z", count: 800)])
        }
        let source = (0..<720).map { Self.segment(String(repeating: "x", count: 50), start: Double($0 * 4)) }
        let result = await Self.pipeline(generator).run(segments: source, userNotes: "", onProgress: { _ in })
        #expect(result.notes != nil)
        #expect(generator.finalizeInputs.count == 1)
        #expect(generator.mergeInputs.count >= 2)
        for batch in generator.mergeInputs {
            let input = batch.flatMap { $0.topics + $0.decisions + $0.actionItems + $0.questions + $0.keyPoints }.joined(separator: "\n")
            #expect(try await CharTokenCounter().tokens(in: input) <= TokenBudget().chunkTokens)
        }
    }

    @Test func longNotesTrimAtLineBoundaryAndFinalizeContextRetries() async {
        let generator = FakeNotesGenerator()
        generator.onDigest = { Self.digest($0) }
        let longNotes = (0..<1000).map { "line \($0)" }.joined(separator: "\n")
        let result = await Self.pipeline(generator).run(segments: [Self.segment("hello")], userNotes: longNotes, onProgress: { _ in })
        #expect(result.notes != nil)
        #expect(generator.finalizeInputs.first?.notes.hasPrefix("line 0") == true)
        #expect(generator.finalizeInputs.first?.notes.split(separator: "\n").count ?? 0 < 500)
        #expect(result.warnings.contains { $0.contains("first") })

        let retry = FakeNotesGenerator()
        retry.onDigest = { Self.digest($0) }
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        retry.onFinalize = { notes, _ in
            let attempt = attempts.withLock { value -> Int in value += 1; return value }
            if attempt == 1 { throw GeneratorError.contextExceeded }
            return MeetingNotesResult(summary: "ok", decisions: [], actionItems: [], openQuestions: [], expandedNotes: notes)
        }
        let retryResult = await Self.pipeline(retry).run(segments: [Self.segment("hello")], userNotes: "brief", onProgress: { _ in })
        #expect(retry.finalizeInputs.map(\.notes) == ["brief", ""])
        #expect(retryResult.notes != nil && retryResult.warnings.count == 1)
    }

    @Test func emptyTranscriptMakesNoCalls() async {
        let generator = FakeNotesGenerator()
        let result = await Self.pipeline(generator).run(segments: [], userNotes: "notes", onProgress: { _ in })
        #expect(result.notes == nil)
        #expect(result.warnings == ["No transcript to summarize."])
        #expect(generator.digestInputs.isEmpty)
    }

    @Test func preCancelledPipelineReturnsPromptly() async {
        let generator = FakeNotesGenerator()
        generator.onDigest = { _ in
            if Task.isCancelled { throw CancellationError() }
            return Self.digest()
        }
        let task = Task {
            await Self.pipeline(generator).run(segments: [Self.segment("cancel me")], userNotes: "", onProgress: { _ in })
        }
        task.cancel()
        let result = await task.value
        #expect(result.notes == nil && result.warnings == ["Cancelled."])
    }
}
