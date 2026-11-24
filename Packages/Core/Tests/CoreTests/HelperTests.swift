import Testing
import Foundation
@testable import Core
import CoreTestSupport

@Suite struct SessionGroupingTests {
    static var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }
    static let now = ISO8601DateFormatter().date(from: "2026-11-18T18:30:00Z")!        // 10:30 PST
    func session(_ iso: String) -> Session {
        var s = Session(title: iso, mode: .micOnly); s.createdAt = ISO8601DateFormatter().date(from: iso)!; return s
    }
    @Test func groups() {
        let a = session("2026-11-18T18:00:00Z")      // 10:00 today
        let b = session("2026-11-18T08:00:00Z")      // 00:00 today (boundary)
        let c = session("2026-11-18T07:59:00Z")      // 23:59 yesterday
        let d = session("2026-11-16T20:00:00Z")      // two days ago
        let g = SessionGrouping.group([d, c, b, a], now: Self.now, calendar: Self.cal)
        #expect(g.map(\.title) == ["Today", "Yesterday", "Earlier"])
        #expect(g[0].sessions.map(\.id) == [a.id, b.id])
        #expect(g[1].sessions.map(\.id) == [c.id] && g[2].sessions.map(\.id) == [d.id])
    }
    @Test func emptyGroupsOmitted() {
        let g = SessionGrouping.group([session("2026-11-10T20:00:00Z")], now: Self.now, calendar: Self.cal)
        #expect(g.map(\.title) == ["Earlier"])
        #expect(SessionGrouping.group([], now: Self.now, calendar: Self.cal).isEmpty)
    }
    @Test func futureCountsAsToday() {
        #expect(SessionGrouping.group([session("2026-11-19T20:00:00Z")], now: Self.now, calendar: Self.cal).first?.title == "Today")
    }
}
@Suite struct HelperTests {
    @Test func timecode() {
        let cases: [(Double, String, String)] = [(0, "00:00", "00:00:00"), (12.9, "00:12", "00:00:12"), (59, "00:59", "00:00:59"),
            (60, "01:00", "00:01:00"), (3599, "59:59", "00:59:59"), (3600, "1:00:00", "01:00:00"), (3661, "1:01:01", "01:01:01"), (-5, "00:00", "00:00:00")]
        for (s, a, b) in cases { #expect(Timecode.string(s) == a); #expect(Timecode.hms(s) == b) }
    }
    @Test func meterGlyphs() {
        let cases: [(Float, Character)] = [(1.0, "█"), (0.5, "▇"), (0.25, "▆"), (0.125, "▅"), (0.0625, "▄"), (0.01, "▃"), (0.002, "▂"), (0.0005, "▁"), (0, "▁")]
        for (p, g) in cases { #expect(MeterGlyph.glyph(forPeak: p) == g, "peak \(p)") }
    }
    @Test func progressBar() {
        #expect(ProgressBar.text(fraction: 0) == "[░░░░░░░░░░] 0%")
        #expect(ProgressBar.text(fraction: 0.62) == "[██████░░░░] 62%")
        #expect(ProgressBar.text(fraction: 1) == "[██████████] 100%")
        #expect(ProgressBar.text(fraction: 7) == "[██████████] 100%" && ProgressBar.text(fraction: -1) == "[░░░░░░░░░░] 0%")
        #expect(ProgressBar.text(fraction: .nan) == "[░░░░░░░░░░] 0%")
        #expect(ProgressBar.text(fraction: 0.5, cells: 4) == "[██░░] 50%")
    }
    @Test func stageTitles() { for s in ProcessingStage.allCases { #expect(!s.title.isEmpty) } }
}
