import Foundation

public enum AudioLinkStyle: String, Codable, Sendable {
    case markdownLink, wikiEmbed
}

public enum ChromeStyle: String, Codable, Sendable {
    case native, terminal
}

public struct AppSettings: Codable, Sendable, Equatable {
    public var notesFolderPath: String? = nil
    public var audioFolderPath: String? = nil
    public var transcriptionModel = "small"
    public var notesModel = "apple-foundation-models"
    public var frontmatter = true
    public var audioLinkStyle: AudioLinkStyle = .markdownLink
    public var exportCenteredMix = false
    public var themeID = "system"
    public var chrome: ChromeStyle = .native
    public var matchWindowToTheme = true
    public var editorFontName: String? = nil      // nil = system
    public var editorFontSize = 15.0
    public var vocabulary: [String] = []
    public var consentAcknowledged = false
    public var defaultMode: CaptureMode = .appAndMic

    public init(
        notesFolderPath: String? = nil,
        audioFolderPath: String? = nil,
        transcriptionModel: String = "small",
        notesModel: String = "apple-foundation-models",
        frontmatter: Bool = true,
        audioLinkStyle: AudioLinkStyle = .markdownLink,
        exportCenteredMix: Bool = false,
        themeID: String = "system",
        chrome: ChromeStyle = .native,
        matchWindowToTheme: Bool = true,
        editorFontName: String? = nil,
        editorFontSize: Double = 15.0,
        vocabulary: [String] = [],
        consentAcknowledged: Bool = false,
        defaultMode: CaptureMode = .appAndMic
    ) {
        self.notesFolderPath = notesFolderPath
        self.audioFolderPath = audioFolderPath
        self.transcriptionModel = transcriptionModel
        self.notesModel = notesModel
        self.frontmatter = frontmatter
        self.audioLinkStyle = audioLinkStyle
        self.exportCenteredMix = exportCenteredMix
        self.themeID = themeID
        self.chrome = chrome
        self.matchWindowToTheme = matchWindowToTheme
        self.editorFontName = editorFontName
        self.editorFontSize = editorFontSize
        self.vocabulary = vocabulary
        self.consentAcknowledged = consentAcknowledged
        self.defaultMode = defaultMode
    }
}

public actor SettingsStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL), let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    public func save(_ s: AppSettings) throws {
        let data = try JSONEncoder().encode(s)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
