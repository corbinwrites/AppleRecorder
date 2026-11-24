import Testing
import Foundation
@testable import Core
import CoreTestSupport

@Suite struct StateMachineTests {
    static let expected: Set<String> = [                       // spelled out independently of the implementation
        "idle>armed", "idle>stopped", "armed>recording", "armed>idle", "recording>stopped",
        "recording>failed", "stopped>processing", "stopped>idle", "processing>done",
        "processing>failed", "failed>processing", "failed>idle", "done>processing", "done>idle",
    ]
    @Test func fullMatrix() {
        for a in SessionState.allCases { for b in SessionState.allCases {
            #expect(a.canTransition(to: b) == Self.expected.contains("\(a.rawValue)>\(b.rawValue)"), "\(a) -> \(b)")
        } }
    }
    @Test func nothingTransitionsToItself() { for s in SessionState.allCases { #expect(!s.canTransition(to: s)) } }
}

@Suite struct CaptureModeTests {
    @Test func properties() {
        #expect(CaptureMode.appAndMic.channelCount == 2)
        #expect(CaptureMode.micOnly.channelCount == 1 && CaptureMode.appOnly.channelCount == 1)
        #expect(CaptureMode.appAndMic.labelsSpeakers && !CaptureMode.micOnly.labelsSpeakers && !CaptureMode.appOnly.labelsSpeakers)
        #expect(CaptureMode.micOnly.hasMic && !CaptureMode.micOnly.hasApp)
        #expect(CaptureMode.appOnly.hasApp && !CaptureMode.appOnly.hasMic)
        #expect(CaptureMode.appAndMic.frontmatterValue == "app+mic")
        #expect(CaptureMode.micOnly.frontmatterValue == "mic" && CaptureMode.appOnly.frontmatterValue == "app")
    }
}

@Suite struct SessionStoreTests {
    private func writeTrack(_ store: FileSessionStore, _ id: UUID, bytes: Int) throws {
        let rec = store.sessionDirectory(for: id).appendingPathComponent("recording", isDirectory: true)
        try FileManager.default.createDirectory(at: rec, withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: rec / "mic.caf")
    }
    @Test func roundTrip() async throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileSessionStore(root: dir)
        var s = try await store.create(title: "Weekly sync", mode: .appAndMic)
        s.sourceAppName = "Discord"; s.state = .stopped; s.durationSeconds = 12.5
        try await store.save(s)
        #expect(try await store.load(id: s.id) == s)
    }
    @Test func listNewestFirst() async throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileSessionStore(root: dir)
        var ids: [UUID] = []
        for i in 0..<3 {
            var s = try await store.create(title: "S\(i)", mode: .micOnly)
            s.createdAt = Date(timeIntervalSince1970: 1_000 + Double(i) * 100)
            try await store.save(s); ids.append(s.id)
        }
        #expect(try await store.list().map(\.id) == ids.reversed())
    }
    @Test func notesRoundTripUnicode() async throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileSessionStore(root: dir)
        let s = try await store.create(title: "N", mode: .micOnly)
        let text = "héllo ✓ 日本語\n- [ ] x\n"
        try await store.saveNotes(text, for: s.id)
        #expect(try await store.loadNotes(for: s.id) == text)
    }
    @Test func recoverRecordingWithAudio() async throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileSessionStore(root: dir)
        var s = try await store.create(title: "R", mode: .appAndMic); s.state = .recording; try await store.save(s)
        try writeTrack(store, s.id, bytes: 10)
        let recovered = try await store.recoverInterrupted()
        #expect(recovered.count == 1 && recovered[0].state == .stopped && recovered[0].recoveredFromCrash)
        #expect(try await store.load(id: s.id).state == .stopped)
    }
    @Test func recoverRecordingWithoutAudio() async throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileSessionStore(root: dir)
        var s = try await store.create(title: "R", mode: .micOnly); s.state = .recording; try await store.save(s)
        let r = try await store.recoverInterrupted()
        #expect(r[0].state == .failed && r[0].failure?.stage == "recording" && r[0].failure?.message == "No audio was saved")
    }
    @Test func zeroByteTrackCountsAsNoAudio() async throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileSessionStore(root: dir)
        var s = try await store.create(title: "R", mode: .micOnly); s.state = .armed; try await store.save(s)
        try writeTrack(store, s.id, bytes: 0)
        #expect(try await store.recoverInterrupted()[0].state == .failed)
    }
    @Test func recoverProcessing() async throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileSessionStore(root: dir)
        var s = try await store.create(title: "P", mode: .micOnly); s.state = .processing; try await store.save(s)
        let r = try await store.recoverInterrupted()
        #expect(r[0].state == .failed && r[0].failure?.stage == "processing" && r[0].failure?.message == "Interrupted")
    }
    @Test func doneIsUntouched() async throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileSessionStore(root: dir)
        var s = try await store.create(title: "D", mode: .micOnly); s.state = .done; try await store.save(s)
        #expect(try await store.recoverInterrupted().isEmpty)
        #expect(try await store.load(id: s.id) == s)
    }
    @Test func corruptSessionJSONDoesNotCrashList() async throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileSessionStore(root: dir)
        let good = try await store.create(title: "Good", mode: .micOnly)
        let bad = try await store.create(title: "Bad", mode: .micOnly)
        try Data("{not json".utf8).write(to: store.sessionDirectory(for: bad.id) / "session.json")
        #expect(try await store.list().map(\.id) == [good.id])
    }
}

@Suite struct SettingsTests {
    @Test func defaults() {
        let s = AppSettings()
        #expect(s.transcriptionModel == "small" && s.notesModel == "apple-foundation-models")
        #expect(s.frontmatter && s.audioLinkStyle == .markdownLink && !s.exportCenteredMix && !s.consentAcknowledged)
        #expect(s.themeID == "system" && s.chrome == .native && s.defaultMode == .appAndMic)
    }
    @Test func missingOrCorruptFileYieldsDefaults() async throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir / "settings.json"
        #expect(await SettingsStore(fileURL: url).load() == AppSettings())
        try Data("garbage".utf8).write(to: url)
        #expect(await SettingsStore(fileURL: url).load() == AppSettings())
    }
    @Test func roundTrip() async throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = SettingsStore(fileURL: dir / "settings.json")
        var s = AppSettings()
        s.notesFolderPath = "/tmp/n"; s.audioFolderPath = "/tmp/a"; s.transcriptionModel = "large-v3-v20240930_626MB"
        s.frontmatter = false; s.audioLinkStyle = .wikiEmbed; s.exportCenteredMix = true; s.themeID = "dracula"
        s.matchWindowToTheme = false; s.editorFontName = "Geist Mono"; s.editorFontSize = 18
        s.vocabulary = ["Soteriology", "Talbot"]; s.consentAcknowledged = true; s.defaultMode = .micOnly
        try await store.save(s)
        #expect(await store.load() == s)
    }
}
