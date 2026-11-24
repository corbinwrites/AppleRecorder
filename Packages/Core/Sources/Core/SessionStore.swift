import Foundation

public protocol SessionStore: Sendable {
    func create(title: String, mode: CaptureMode) async throws -> Session
    func save(_ s: Session) async throws
    func load(id: UUID) async throws -> Session
    func list() async throws -> [Session]
    func saveNotes(_ markdown: String, for id: UUID) async throws
    func loadNotes(for id: UUID) async throws -> String
    func delete(id: UUID) async throws
    func recoverInterrupted() async throws -> [Session]
    func sessionDirectory(for id: UUID) -> URL
}

public actor FileSessionStore: SessionStore {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public nonisolated func sessionDirectory(for id: UUID) -> URL {
        root.appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func create(title: String, mode: CaptureMode) async throws -> Session {
        let session = Session(title: title, mode: mode)
        let directory = sessionDirectory(for: session.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await save(session)
        return session
    }

    public func save(_ s: Session) async throws {
        let directory = sessionDirectory(for: s.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(s)
        try data.write(to: directory.appendingPathComponent("session.json"), options: .atomic)
    }

    public func load(id: UUID) async throws -> Session {
        let url = sessionDirectory(for: id).appendingPathComponent("session.json")
        return try JSONDecoder().decode(Session.self, from: Data(contentsOf: url))
    }

    public func list() async throws -> [Session] {
        let sessionsDirectory = root.appendingPathComponent("Sessions", isDirectory: true)
        guard let directories = try? FileManager.default.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: nil) else { return [] }
        return directories.compactMap { directory in
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("session.json")) else { return nil }
            return try? JSONDecoder().decode(Session.self, from: data)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    public func saveNotes(_ markdown: String, for id: UUID) async throws {
        let directory = sessionDirectory(for: id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(markdown.utf8).write(to: directory.appendingPathComponent("notes.md"), options: .atomic)
    }

    public func loadNotes(for id: UUID) async throws -> String {
        let url = sessionDirectory(for: id).appendingPathComponent("notes.md")
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func delete(id: UUID) async throws {
        let directory = sessionDirectory(for: id)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    public func recoverInterrupted() async throws -> [Session] {
        var recovered: [Session] = []
        for var session in try await list() {
            switch session.state {
            case .recording, .armed:
                let recording = sessionDirectory(for: session.id).appendingPathComponent("recording", isDirectory: true)
                let tracks = (try? FileManager.default.contentsOfDirectory(at: recording, includingPropertiesForKeys: [.fileSizeKey])) ?? []
                let hasAudio = tracks.contains { url in
                    ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
                }
                session.recoveredFromCrash = true
                if hasAudio {
                    session.state = .stopped
                    session.failure = nil
                } else {
                    session.state = .failed
                    session.failure = FailureInfo(stage: "recording", message: "No audio was saved")
                }
                try await save(session)
                recovered.append(session)
            case .processing:
                session.state = .failed
                session.failure = FailureInfo(stage: "processing", message: "Interrupted")
                session.recoveredFromCrash = true
                try await save(session)
                recovered.append(session)
            case .idle, .stopped, .done, .failed:
                continue
            }
        }
        return recovered
    }
}
