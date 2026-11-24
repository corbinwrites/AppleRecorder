import Foundation
import FoundationModels
import Core

@Generable
struct FMChunkDigest {
    @Guide(description: "Main topics discussed") var topics: [String]
    @Guide(description: "Decisions that were made") var decisions: [String]
    @Guide(description: "Action items, with owner only if stated") var actionItems: [String]
    @Guide(description: "Open questions") var questions: [String]
    @Guide(description: "Other key points") var keyPoints: [String]
}

@Generable
struct FMMeetingNotes {
    @Guide(description: "Three to five sentence summary") var summary: String
    var decisions: [String]
    var actionItems: [String]
    var openQuestions: [String]
    @Guide(description: "Notes that merge the person's own notes with the transcript summary") var expandedNotes: String
}

public struct FoundationNotesGenerator: NotesGenerator {
    public init() {}

    public static func availability() -> (ok: Bool, reason: String?) {
        switch SystemLanguageModel.default.availability {
        case .available:
            return (true, nil)
        case .unavailable(let reason):
            return (false, reasonString(for: reason))
        }
    }

    public static func reasonString(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible: "This Mac is not eligible for Apple Intelligence."
        case .appleIntelligenceNotEnabled: "Apple Intelligence is not enabled."
        case .modelNotReady: "The Apple Intelligence model is not ready."
        @unknown default: "Apple Intelligence is unavailable."
        }
    }

    public func digest(transcriptChunk: String) async throws -> ChunkDigest {
        do {
            let response = try await LanguageModelSession(instructions: Prompts.digestInstructions)
                .respond(to: Prompts.digestPrompt(transcriptChunk), generating: FMChunkDigest.self)
            return Self.map(response.content)
        } catch {
            throw Self.map(error)
        }
    }

    public func merge(digests: [ChunkDigest]) async throws -> ChunkDigest {
        let body = digests.enumerated().map { index, digest in
            "Summary \(index + 1):\nTopics: \(digest.topics.joined(separator: "; "))\nDecisions: \(digest.decisions.joined(separator: "; "))\nAction items: \(digest.actionItems.joined(separator: "; "))\nQuestions: \(digest.questions.joined(separator: "; "))\nKey points: \(digest.keyPoints.joined(separator: "; "))"
        }.joined(separator: "\n\n")
        do {
            let response = try await LanguageModelSession(instructions: Prompts.mergeInstructions)
                .respond(to: body, generating: FMChunkDigest.self)
            return Self.map(response.content)
        } catch {
            throw Self.map(error)
        }
    }

    public func finalize(userNotes: String, merged: ChunkDigest) async throws -> MeetingNotesResult {
        let digest = "Topics: \(merged.topics.joined(separator: "; "))\nDecisions: \(merged.decisions.joined(separator: "; "))\nAction items: \(merged.actionItems.joined(separator: "; "))\nQuestions: \(merged.questions.joined(separator: "; "))\nKey points: \(merged.keyPoints.joined(separator: "; "))"
        let prompt = "Person's own notes:\n\(userNotes)\n\nTranscript summary:\n\(digest)"
        do {
            let response = try await LanguageModelSession(instructions: Prompts.finalInstructions)
                .respond(to: prompt, generating: FMMeetingNotes.self)
            let result = response.content
            return MeetingNotesResult(summary: result.summary, decisions: result.decisions,
                actionItems: result.actionItems, openQuestions: result.openQuestions, expandedNotes: result.expandedNotes)
        } catch {
            throw Self.map(error)
        }
    }

    private static func map(_ digest: FMChunkDigest) -> ChunkDigest {
        ChunkDigest(topics: digest.topics, decisions: digest.decisions, actionItems: digest.actionItems,
                    questions: digest.questions, keyPoints: digest.keyPoints)
    }

    private static func map(_ error: any Error) -> GeneratorError {
        if #available(macOS 27.0, *) {
            if let modelError = error as? LanguageModelError {
                switch modelError {
                case .contextSizeExceeded: return .contextExceeded
                case .guardrailViolation, .refusal: return .refused
                case .rateLimited: return .rateLimited
                case .unsupportedCapability, .unsupportedTranscriptContent, .unsupportedGenerationGuide,
                     .unsupportedLanguageOrLocale, .timeout:
                    return .unavailable(error.localizedDescription)
                @unknown default:
                    return .unavailable(error.localizedDescription)
                }
            }
            if let modelError = error as? SystemLanguageModel.Error {
                switch modelError {
                case .assetsUnavailable: return .unavailable("Apple Intelligence model assets are unavailable.")
                @unknown default: return .unavailable(error.localizedDescription)
                }
            }
        }
        if let error = error as? LanguageModelSession.GenerationError {
            return switch error {
            case .exceededContextWindowSize: GeneratorError.contextExceeded
            case .guardrailViolation, .refusal: GeneratorError.refused
            case .rateLimited: GeneratorError.rateLimited
            case .assetsUnavailable: GeneratorError.unavailable("Apple Intelligence model assets are unavailable.")
            case .unsupportedGuide, .unsupportedLanguageOrLocale, .decodingFailure, .concurrentRequests:
                GeneratorError.unavailable(error.localizedDescription)
            @unknown default: GeneratorError.unavailable(error.localizedDescription)
            }
        } else {
            return .unavailable(error.localizedDescription)
        }
    }
}

public struct FMTokenCounter: TokenCounter {
    public init() {}

    public func tokens(in text: String) async throws -> Int {
        if #available(macOS 26.4, *) {
            do { return try await SystemLanguageModel.default.tokenCount(for: text) }
            catch { return Int(ceil(Double(text.count) / 3.0)) }
        }
        return Int(ceil(Double(text.count) / 3.0))
    }
}
