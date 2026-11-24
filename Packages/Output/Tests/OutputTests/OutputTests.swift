import Foundation
import Testing
import Core
@testable import Output

@Suite struct FileNamingTests {
    @Test func sanitizesNames() {
        let cases = [("Weekly sync", "Weekly sync"), ("Q4: plan/review", "Q4- plan-review"), ("  spaced   out  ", "spaced out"), ("a\\b", "a-b"), ("x*y?", "x-y-"), ("", "Untitled"), ("   ", "Untitled"), ("...", "Untitled"), (".hidden", "hidden"), ("tab\there", "tab here"), ("emoji 🎙️ ok", "emoji 🎙️ ok")]
        for (input, expected) in cases { #expect(FileNaming.sanitize(input) == expected) }
        #expect(FileNaming.sanitize(String(repeating: "a", count: 200)) == String(repeating: "a", count: 120))
    }

    @Test func dateNameAndUniqueURL() {
        let date = ISO8601DateFormatter().date(from: "2026-11-18T18:30:00Z")!
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let base = FileNaming.baseName(created: date, title: "Weekly sync", timeZone: zone)
        #expect(base == "2026-11-18 1030 Weekly sync")
        var calls = 0
        let url = FileNaming.uniqueURL(in: URL(fileURLWithPath: "/tmp"), baseName: "base", ext: "m4a") { _ in calls += 1; return calls < 3 }
        #expect(url.lastPathComponent == "base 3.m4a")
    }
}

@Suite struct PathAndYAMLTests {
    @Test func relativePaths() {
        let rows: [(String, String, String?)] = [
            ("/Users/me/Notes", "/Users/me/Audio/x.m4a", "../Audio/x.m4a"),
            ("/Users/me/Notes", "/Users/me/Notes/x.m4a", "x.m4a"),
            ("/Users/me/Notes", "/Users/me/Notes/Audio/x.m4a", "Audio/x.m4a"),
            ("/Users/me/a/b/c", "/Users/me/x.m4a", "../../../x.m4a"),
            ("/Users/me/Notes/", "/Users/me/Audio/x.m4a", "../Audio/x.m4a"),
            ("/Users/me/Notes", "/Volumes/Ext/Audio/x.m4a", nil),
        ]
        for (from, to, expected) in rows { #expect(PathMath.relativePath(from: URL(fileURLWithPath: from), to: URL(fileURLWithPath: to)) == expected) }
        #expect(PathMath.encodeLinkTarget("../Audio/2026-11-18 1030 Weekly sync.m4a") == "../Audio/2026-11-18%201030%20Weekly%20sync.m4a")
        #expect(PathMath.encodeLinkTarget("a (1).m4a") == "a%20%281%29.m4a")
    }

    @Test func yamlScalars() {
        let rows = [("Weekly sync", "Weekly sync"), ("Q4: plan", "\"Q4: plan\""), ("- item", "\"- item\""), ("true", "\"true\""), ("123", "\"123\""), ("", "\"\""), ("He said \"hi\"", "\"He said \\\"hi\\\"\""), ("C #notes", "\"C #notes\""), ("C# notes", "C# notes"), ("a#b", "a#b"), ("1:1 sync", "\"1:1 sync\""), ("trailing ", "\"trailing \""), ("line1\nline2", "\"line1\\nline2\"")]
        for (input, expected) in rows { #expect(YAML.scalar(input) == expected) }
    }
}

@Suite struct MarkdownRendererTests {
    private func sample() -> NoteDocument {
        let date = ISO8601DateFormatter().date(from: "2026-11-18T18:30:00Z")!
        let notes = MeetingNotesResult(summary: "We agreed on Q1 scope.", decisions: ["Drop advanced search to Q1"], actionItems: ["Sarah: talk to revenue"], openQuestions: ["Who owns the runbook?"], expandedNotes: "Expanded paragraph.")
        return NoteDocument(title: "Weekly sync", created: date, timeZone: TimeZone(identifier: "America/Los_Angeles")!, durationSeconds: 2530, sourceApp: "Discord", mode: .appAndMic, audio: .relative("../Audio/2026-11-18 1030 Weekly sync.m4a"), transcriptionModel: "whisperkit-small", notesModel: "apple-foundation-models", tags: ["meeting"], notes: notes, userNotes: "- [ ] Q1 scope\n- [x] Hiring update", transcript: [TranscriptSegment(start: 12, end: 13, text: "Hello everyone.", speaker: .me), TranscriptSegment(start: 19, end: 20, text: "Hi.", speaker: .them)])
    }

    @Test func goldenDocument() {
        let expected = """
        ---
        title: Weekly sync
        created: 2026-11-18T10:30:00
        duration: "00:42:10"
        source_app: Discord
        capture_mode: app+mic
        audio: "../Audio/2026-11-18 1030 Weekly sync.m4a"
        transcription_model: whisperkit-small
        notes_model: apple-foundation-models
        tags: [meeting]
        ---

        # Weekly sync

        Recording: [2026-11-18 1030 Weekly sync.m4a](../Audio/2026-11-18%201030%20Weekly%20sync.m4a)

        ## Summary
        We agreed on Q1 scope.

        ## Decisions
        - Drop advanced search to Q1

        ## Action items
        - [ ] Sarah: talk to revenue

        ## Open questions
        - Who owns the runbook?

        ## Notes
        Expanded paragraph.

        ## My notes (original)
        - [ ] Q1 scope
        - [x] Hiring update

        ## Transcript
        **[00:00:12] Me:** Hello everyone.
        **[00:00:19] Them:** Hi.
        """
        #expect(MarkdownRenderer.render(sample()) == expected + "\n")
    }

    @Test func renderingOptionsAndEmptyBlocks() {
        var document = sample()
        document.options.frontmatter = false
        #expect(MarkdownRenderer.render(document).hasPrefix("# Weekly sync\n"))
        document.options.linkStyle = .wikiEmbed
        #expect(MarkdownRenderer.render(document).contains("Recording: ![[2026-11-18 1030 Weekly sync.m4a]]"))
        #expect(!MarkdownRenderer.render(document).contains("]("))
        document.mode = .micOnly
        document.notes = nil
        document.userNotes = " \n  "
        document.transcript = [TranscriptSegment(start: 12, end: 13, text: "héllo\n日本語")]
        let rendered = MarkdownRenderer.render(document)
        #expect(rendered.contains("**[00:00:12]** héllo 日本語"))
        #expect(!rendered.contains("## Decisions") && !rendered.contains("## My notes (original)"))
    }

    @Test func warningAndAbsoluteAudio() {
        var document = sample()
        document.notes = nil
        document.enhancementWarning = "Notes enhancement unavailable: Apple Intelligence is not enabled. Your transcript and original notes are below."
        document.audio = .absolute(URL(fileURLWithPath: "/Volumes/Ext/Audio/a b.m4a"))
        let rendered = MarkdownRenderer.render(document)
        #expect(rendered.contains("audio: \"file:///Volumes/Ext/Audio/a%20b.m4a\""))
        #expect(rendered.contains("> ⚠️ Notes enhancement unavailable"))
        #expect(!rendered.contains("## Summary"))
    }
}

@Suite struct OutputIOTests {
    @Test func atomicWriterReplacesAndLeavesNoTemporaryFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("note.md")
        try AtomicWriter.write(Data("old".utf8), to: url)
        try AtomicWriter.write(Data("new content".utf8), to: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "new content")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)
        #expect(throws: (any Error).self) { try AtomicWriter.write(Data(), to: directory.appendingPathComponent("missing/file.md")) }
    }

    @Test func folderStatus() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(FolderCheck.status(of: directory) == .ok)
        let file = directory.appendingPathComponent("file"); try Data().write(to: file)
        #expect(FolderCheck.status(of: file) == .notADirectory)
        #expect(FolderCheck.status(of: directory.appendingPathComponent("missing")) == .missing)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        #expect(FolderCheck.status(of: directory) == .notWritable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
    }

    @Test func exporterResolvesRelativeAndAbsoluteAudioLinksAndVersionsNames() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let notesFolder = root.appendingPathComponent("Notes", isDirectory: true)
        let audioFolder = root.appendingPathComponent("Audio", isDirectory: true)
        try FileManager.default.createDirectory(at: notesFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: audioFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let audio = audioFolder.appendingPathComponent("2026-11-18 1030 Weekly sync.m4a")
        try Data([1]).write(to: audio)
        let date = Date(timeIntervalSince1970: 0)
        let document = NoteDocument(title: "Weekly sync", created: date, durationSeconds: 10, mode: .micOnly, transcriptionModel: "small")
        let settings = AppSettings()
        let first = try SessionExporter.export(document: document, baseName: "Weekly sync", audioFile: audio, notesFolder: notesFolder, settings: settings)
        let second = try SessionExporter.export(document: document, baseName: "Weekly sync", audioFile: audio, notesFolder: notesFolder, settings: settings)
        #expect(first.lastPathComponent == "Weekly sync.md")
        #expect(second.lastPathComponent == "Weekly sync 2.md")
        let markdown = try String(contentsOf: first, encoding: .utf8)
        let target = try #require(markdown.split(separator: "(").dropFirst().first?.split(separator: ")").first)
        let decoded = String(target).removingPercentEncoding
        let resolved = notesFolder.appendingPathComponent(try #require(decoded)).standardizedFileURL
        #expect(resolved.path == audio.standardizedFileURL.path)
        #expect(try String(contentsOf: second, encoding: .utf8) == markdown)

        let foreignAudio = URL(fileURLWithPath: "/Volumes/Nonexistent/Audio/clip.m4a")
        let foreign = try SessionExporter.export(document: document, baseName: "Foreign", audioFile: foreignAudio, notesFolder: notesFolder, settings: settings)
        let foreignText = try String(contentsOf: foreign, encoding: .utf8)
        #expect(foreignText.contains("Recording: [clip.m4a](file:///Volumes/Nonexistent/Audio/clip.m4a)"))
    }
}
