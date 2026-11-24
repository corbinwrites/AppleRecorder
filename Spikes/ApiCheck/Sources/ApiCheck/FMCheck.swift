import Foundation
import FoundationModels

@Generable
public struct TestDigest: Sendable {
    @Guide(description: "Topics") public var topics: [String]
    @Guide(description: "Summary") public var summary: String
}

public func verifyFMAPIs() async throws {
    let model = SystemLanguageModel.default
    let avail = model.availability
    switch avail {
    case .available:
        break
    case .unavailable(let reason):
        switch reason {
        case .deviceNotEligible:
            break
        case .appleIntelligenceNotEnabled:
            break
        case .modelNotReady:
            break
        @unknown default:
            break
        }
    }
    
    let contextSize = model.contextSize
    _ = contextSize
    
    if #available(macOS 26.4, *) {
        let tokens = try await model.tokenCount(for: "test text")
        _ = tokens
    }
    
    let session = LanguageModelSession(instructions: "Test instructions")
    let response = try await session.respond(to: "Test prompt", generating: TestDigest.self)
    _ = response.content
    
    do {
        _ = try await session.respond(to: "Another prompt")
    } catch let error as LanguageModelSession.GenerationError {
        switch error {
        case .exceededContextWindowSize:
            break
        case .guardrailViolation:
            break
        case .rateLimited:
            break
        case .refusal:
            break
        case .assetsUnavailable:
            break
        case .unsupportedGuide:
            break
        case .unsupportedLanguageOrLocale:
            break
        case .decodingFailure:
            break
        case .concurrentRequests:
            break
        @unknown default:
            break
        }
    }
}
