import Testing
@testable import Enhance
import Core
import CoreTestSupport

@Suite struct NotesPipelineTests {
    static func segments(_ n: Int) -> [TranscriptSegment] {
        (0..<n).map { TranscriptSegment(start: Double($0 * 4), end: Double($0 * 4 + 3), text: String(repeating: "x", count: 50), speaker: .me) }
    }
    static func digest(_ s: String) -> ChunkDigest {
        ChunkDigest(topics: ["t"], decisions: [], actionItems: [], questions: [], keyPoints: [String(s.prefix(10))], unavailable: false)
    }
    @Test func happyPath() async {
        let gen = FakeNotesGenerator(); gen.onDigest = { Self.digest($0) }
        let p = NotesPipeline(generator: gen, counter: CharTokenCounter(perToken: 4), sleep: { _ in })
        let r = await p.run(segments: Self.segments(720), userNotes: "my notes", onProgress: { _ in })
        #expect(r.notes != nil && r.warnings.isEmpty)
        #expect((10...14).contains(gen.digestInputs.count))
        #expect(gen.finalizeInputs.count == 1 && gen.finalizeInputs[0].notes == "my notes")
    }
    @Test func refusedChunkIsSkipped() async {
        let gen = FakeNotesGenerator()
        gen.onDigest = { [unowned gen] text in
            if gen.digestInputs.count == 3 { throw GeneratorError.refused }
            return Self.digest(text)
        }
        let p = NotesPipeline(generator: gen, counter: CharTokenCounter(perToken: 4), sleep: { _ in })
        let r = await p.run(segments: Self.segments(720), userNotes: "", onProgress: { _ in })
        #expect(r.warnings.count == 1 && r.warnings[0].contains("Chunk 3"))
        #expect(r.notes != nil)
        #expect(r.digests.filter(\.unavailable).count == 1)
    }
}
