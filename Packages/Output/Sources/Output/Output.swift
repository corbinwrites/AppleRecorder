import Foundation
import Core

public enum FileNaming {
    public static func sanitize(_ title: String) -> String {
        let collapsed = title.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let mapped = String(String.UnicodeScalarView(collapsed.unicodeScalars.map { invalid.contains($0) ? "-" : $0 }))
        let trimmed = mapped.trimmingCharacters(in: .whitespaces).drop(while: { $0 == "." })
        let result = String(trimmed.prefix(120))
        return result.isEmpty ? "Untitled" : result
    }

    public static func baseName(created: Date, title: String, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return "\(formatter.string(from: created)) \(sanitize(title))"
    }

    public static func uniqueURL(in dir: URL, baseName: String, ext: String, exists: (URL) -> Bool) -> URL {
        var suffix = 1
        while true {
            let name = suffix == 1 ? baseName : "\(baseName) \(suffix)"
            let url = dir.appendingPathComponent(name).appendingPathExtension(ext)
            if !exists(url) { return url }
            suffix += 1
        }
    }
}

public enum PathMath {
    public static func relativePath(from dir: URL, to file: URL) -> String? {
        let source = dir.standardizedFileURL.pathComponents
        let target = file.standardizedFileURL.pathComponents
        func mountedVolume(_ components: [String]) -> String? {
            guard let index = components.firstIndex(of: "Volumes"), components.indices.contains(index + 1) else { return nil }
            return components[index + 1]
        }
        if mountedVolume(source) != mountedVolume(target), mountedVolume(source) != nil || mountedVolume(target) != nil { return nil }
        if mountedVolume(source) != mountedVolume(target) { return nil }
        guard source.first == target.first else { return nil }
        var common = 0
        while common < min(source.count, target.count), source[common] == target[common] { common += 1 }
        return (Array(repeating: "..", count: source.count - common) + target.dropFirst(common)).joined(separator: "/")
    }

    public static func encodeLinkTarget(_ path: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "()")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }
}

enum YAML {
    static func scalar(_ value: String) -> String {
        let lower = value.lowercased()
        let startsSpecial = value.first.map { "-?:,[]{}#&*!|>'% @`".contains($0) } ?? false
        let numeric = value.range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil
        let quote = value.isEmpty || value != value.trimmingCharacters(in: .whitespaces) || value.contains(":") || value.contains(" #") || value.contains("\"") || value.contains("\n") || startsSpecial || ["true", "false", "yes", "no", "null", "~"].contains(lower) || numeric
        guard quote else { return value }
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}

public enum AudioReference: Sendable, Equatable { case relative(String), absolute(URL) }

public struct RenderOptions: Sendable, Equatable {
    public var frontmatter: Bool
    public var linkStyle: AudioLinkStyle
    public init(frontmatter: Bool = true, linkStyle: AudioLinkStyle = .markdownLink) {
        self.frontmatter = frontmatter
        self.linkStyle = linkStyle
    }
}

public struct NoteDocument: Sendable {
    public var title: String
    public var created: Date
    public var timeZone: TimeZone
    public var durationSeconds: Double
    public var sourceApp: String?
    public var mode: CaptureMode
    public var audio: AudioReference?
    public var transcriptionModel: String
    public var notesModel: String?
    public var tags: [String]
    public var notes: MeetingNotesResult?
    public var enhancementWarning: String?
    public var userNotes: String
    public var transcript: [TranscriptSegment]
    public var options: RenderOptions

    public init(title: String, created: Date, timeZone: TimeZone = .current, durationSeconds: Double, sourceApp: String? = nil, mode: CaptureMode, audio: AudioReference? = nil, transcriptionModel: String, notesModel: String? = nil, tags: [String] = [], notes: MeetingNotesResult? = nil, enhancementWarning: String? = nil, userNotes: String = "", transcript: [TranscriptSegment] = [], options: RenderOptions = RenderOptions()) {
        self.title = title; self.created = created; self.timeZone = timeZone; self.durationSeconds = durationSeconds
        self.sourceApp = sourceApp; self.mode = mode; self.audio = audio; self.transcriptionModel = transcriptionModel
        self.notesModel = notesModel; self.tags = tags; self.notes = notes; self.enhancementWarning = enhancementWarning
        self.userNotes = userNotes; self.transcript = transcript; self.options = options
    }
}

public enum MarkdownRenderer {
    public static func render(_ document: NoteDocument) -> String {
        var blocks: [String] = []
        if document.options.frontmatter {
            var lines = ["---", "title: \(YAML.scalar(document.title))"]
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = document.timeZone; formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            lines.append("created: \(formatter.string(from: document.created))")
            lines.append("duration: \"\(Timecode.hms(document.durationSeconds))\"")
            if let source = document.sourceApp { lines.append("source_app: \(YAML.scalar(source))") }
            lines.append("capture_mode: \(document.mode.frontmatterValue)")
            if let audio = document.audio { lines.append("audio: \"\(frontmatterAudio(audio).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\"") }
            lines.append("transcription_model: \(YAML.scalar(document.transcriptionModel))")
            if let model = document.notesModel { lines.append("notes_model: \(YAML.scalar(model))") }
            lines.append("tags: [\(document.tags.map(YAML.scalar).joined(separator: ", "))]")
            lines.append("---")
            blocks.append(lines.joined(separator: "\n"))
        }
        blocks.append("# \(document.title)")
        if let warning = document.enhancementWarning { blocks.append("> ⚠️ \(warning)") }
        if let audio = document.audio { blocks.append(recordingLine(audio, style: document.options.linkStyle)) }
        if let notes = document.notes {
            appendSection("Summary", body: notes.summary, to: &blocks)
            appendSection("Decisions", body: list(notes.decisions), to: &blocks)
            appendSection("Action items", body: notes.actionItems.map { "- [ ] \($0)" }.joined(separator: "\n"), to: &blocks)
            appendSection("Open questions", body: list(notes.openQuestions), to: &blocks)
            appendSection("Notes", body: notes.expandedNotes, to: &blocks)
        }
        if !document.userNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append("## My notes (original)\n\(document.userNotes)")
        }
        if !document.transcript.isEmpty {
            let lines = document.transcript.map { segment -> String in
                let stamp = Timecode.hms(segment.start)
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
                if let speaker = segment.speaker { return "**[\(stamp)] \(speaker.rawValue):** \(text)" }
                return "**[\(stamp)]** \(text)"
            }
            blocks.append("## Transcript\n\(lines.joined(separator: "\n"))")
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    private static func appendSection(_ title: String, body: String, to blocks: inout [String]) {
        guard !body.isEmpty else { return }
        blocks.append("## \(title)\n\(body)")
    }
    private static func list(_ items: [String]) -> String { items.map { "- \($0)" }.joined(separator: "\n") }
    private static func frontmatterAudio(_ audio: AudioReference) -> String {
        switch audio { case .relative(let path): path; case .absolute(let url): url.absoluteString }
    }
    private static func recordingLine(_ audio: AudioReference, style: AudioLinkStyle) -> String {
        let name: String
        let target: String
        switch audio {
        case .relative(let path): name = URL(fileURLWithPath: path).lastPathComponent; target = PathMath.encodeLinkTarget(path)
        case .absolute(let url): name = url.lastPathComponent; target = url.absoluteString
        }
        switch style {
        case .markdownLink: return "Recording: [\(name)](\(target))"
        case .wikiEmbed: return "Recording: ![[\(name)]]"
        }
    }
}

public enum AtomicWriter {
    public static func write(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: temporary)
        do {
            if FileManager.default.fileExists(atPath: url.path) { _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary) }
            else { try FileManager.default.moveItem(at: temporary, to: url) }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}

public enum FolderStatus: Sendable, Equatable { case ok, missing, notADirectory, notWritable }
public enum FolderCheck {
    public static func status(of url: URL) -> FolderStatus {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return .missing }
        guard isDirectory.boolValue else { return .notADirectory }
        let permissions = (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0
        return permissions & 0o222 == 0 ? .notWritable : .ok
    }
}

public enum SessionExporter {
    public static func export(document: NoteDocument, baseName: String, audioFile: URL?, notesFolder: URL, settings: AppSettings) throws -> URL {
        var exportDocument = document
        exportDocument.options.frontmatter = settings.frontmatter
        exportDocument.options.linkStyle = settings.audioLinkStyle
        if let audioFile {
            if let relative = PathMath.relativePath(from: notesFolder, to: audioFile) { exportDocument.audio = .relative(relative) }
            else { exportDocument.audio = .absolute(audioFile) }
        } else { exportDocument.audio = nil }
        let destination = FileNaming.uniqueURL(in: notesFolder, baseName: baseName, ext: "md") { FileManager.default.fileExists(atPath: $0.path) }
        try AtomicWriter.write(Data(MarkdownRenderer.render(exportDocument).utf8), to: destination)
        return destination
    }
}
