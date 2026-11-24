import Testing
import Foundation
@testable import Enhance
import Core

@Suite struct FoundationNotesIntegrationTests {
    @Test func syntheticFiveMinuteTranscript() async {
        guard ProcessInfo.processInfo.environment["AR_INTEGRATION"] == "1" else { return }
        let availability = FoundationNotesGenerator.availability()
        guard availability.ok else {
            Issue.record("Apple Intelligence unavailable: \(availability.reason ?? "unknown")")
            return
        }
        let lines = [
            "The team reviewed the launch schedule and agreed the first customer preview stays in June.",
            "Sarah will send the revised budget to Alex by Friday.",
            "The mobile team finished the offline sync prototype and needs two days for reliability testing.",
            "The group decided to defer the analytics dashboard until after the preview.",
            "Jordan will confirm the vendor security review before the next planning meeting.",
            "The support team asked for a short troubleshooting guide before inviting customers."
        ]
        let segments = (0..<15).map { index in
            TranscriptSegment(start: Double(index * 20), end: Double(index * 20 + 15), text: lines[index % lines.count], speaker: .them)
        }
        let pipeline = NotesPipeline(generator: FoundationNotesGenerator(), counter: FMTokenCounter())
        let start = Date()
        let result = await pipeline.run(segments: segments, userNotes: "Keep the launch timing and owners clear.", onProgress: { _ in })
        #expect(Date().timeIntervalSince(start) < 120)
        #expect(!(result.notes?.summary.isEmpty ?? true))
        #expect(result.notes?.actionItems.contains { $0.localizedCaseInsensitiveContains("Sarah") } == true)
        #expect(result.warnings.isEmpty)
    }
}
