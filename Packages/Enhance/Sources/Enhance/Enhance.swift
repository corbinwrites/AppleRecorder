import Foundation
import Core

public struct TokenBudget: Sendable, Equatable {
    public var window = 4096
    public var instructions = 300
    public var userNotes = 500
    public var output = 800
    public var margin = 1300

    public init(window: Int = 4096, instructions: Int = 300, userNotes: Int = 500, output: Int = 800, margin: Int = 1300) {
        self.window = window; self.instructions = instructions; self.userNotes = userNotes
        self.output = output; self.margin = margin
    }

    public var chunkTokens: Int { window - instructions - userNotes - output - margin }

    public func scaled(toWindow newWindow: Int) -> TokenBudget {
        var copy = self
        let scale = Double(newWindow) / Double(window)
        copy.window = newWindow
        copy.instructions = Int((Double(instructions) * scale).rounded())
        copy.userNotes = Int((Double(userNotes) * scale).rounded())
        copy.output = Int((Double(output) * scale).rounded())
        copy.margin = Int((Double(margin) * scale).rounded())
        return copy
    }
}

public enum Prompts {
    public static let digestInstructions = """
    You summarize one segment of a meeting transcript. Use only facts that appear in the text. Do not invent names, dates, numbers, or owners. If a list has no items, return an empty list. Keep every item under 25 words.
    """
    public static let mergeInstructions = """
    You combine several partial meeting summaries into one. Remove duplicates. Keep only items present in the input. Do not invent names, dates, numbers, or owners.
    """
    public static let finalInstructions = """
    You write meeting notes. Combine the person's own notes with the summary of the transcript. Keep the person's wording where possible. Only use names that appear in the input. Action items must say who and what only if the input says so.
    """
    public static func digestPrompt(_ chunk: String) -> String { "Transcript segment:\n\(chunk)" }
}

public struct Chunk: Sendable, Equatable {
    public var text: String
    public var firstSegment: Int
    public var lastSegment: Int
    public var startSeconds: Double
    public var endSeconds: Double
    public init(text: String, firstSegment: Int, lastSegment: Int, startSeconds: Double, endSeconds: Double) {
        self.text = text; self.firstSegment = firstSegment; self.lastSegment = lastSegment
        self.startSeconds = startSeconds; self.endSeconds = endSeconds
    }
}

public enum Chunker {
    private struct Line: Sendable {
        var text: String
        var index: Int
        var start: Double
        var end: Double
        var cost: Int
    }

    public static func line(_ segment: TranscriptSegment) -> String {
        let raw = max(0, Int(segment.start.isFinite ? segment.start : 0))
        let h = raw / 3600
        let time = h > 0 ? String(format: "%d:%02d:%02d", h, (raw / 60) % 60, raw % 60) : String(format: "%02d:%02d", raw / 60, raw % 60)
        let speaker = segment.speaker.map { "\($0.rawValue): " } ?? ""
        return "[\(time)] \(speaker)\(segment.text)"
    }

    public static func chunk(_ segments: [TranscriptSegment], maxTokens: Int, overlapFraction: Double = 0.1,
                             counter: any TokenCounter) async throws -> [Chunk] {
        guard !segments.isEmpty, maxTokens > 0 else { return [] }
        let overlapLimit = max(0, Int((Double(maxTokens) * max(0, overlapFraction)).rounded(.down)))
        var lines: [Line] = []
        for (index, segment) in segments.enumerated() {
            let rendered = line(segment)
            let cost = try await counter.tokens(in: rendered)
            if cost <= maxTokens {
                lines.append(Line(text: rendered, index: index, start: segment.start, end: segment.end, cost: cost))
            } else {
                let timePrefix = "[\(String(rendered.dropFirst().prefix(while: { $0 != "]" })))] "
                let prefix = timePrefix + (segment.speaker.map { "\($0.rawValue): " } ?? "")
                let body = segment.text
                let pieces = try await split(body, prefix: prefix, maxTokens: maxTokens, counter: counter)
                lines.append(contentsOf: pieces.map { Line(text: $0, index: index, start: segment.start, end: segment.end, cost: 0) })
                // Recount pieces outside the non-throwing map.
                for pieceIndex in (lines.count - pieces.count)..<lines.count {
                    lines[pieceIndex].cost = try await counter.tokens(in: lines[pieceIndex].text)
                }
            }
        }

        var chunks: [Chunk] = []
        var cursor = 0
        var firstChunk = true
        while cursor < lines.count {
            var start = cursor
            if !firstChunk, overlapLimit > 0 {
                var overlapCost = 0
                while start > 0 {
                    let candidate = lines[start - 1].cost + (start < cursor ? 1 : 0)
                    if overlapCost + candidate > overlapLimit { break }
                    overlapCost += candidate
                    start -= 1
                }
                if start < cursor, start < lines.count, overlapCost + lines[cursor].cost + 1 > maxTokens { start = cursor }
            }
            var end = start
            var cost = 0
            while end < lines.count {
                let added = lines[end].cost + (end > start ? 1 : 0)
                if cost + added > maxTokens { break }
                cost += added; end += 1
            }
            if end == start { end += 1 }
            let selected = Array(lines[start..<end])
            chunks.append(Chunk(text: selected.map(\.text).joined(separator: "\n"), firstSegment: selected[0].index,
                lastSegment: selected[selected.count - 1].index, startSeconds: selected[0].start, endSeconds: selected[selected.count - 1].end))
            cursor = end
            firstChunk = false
        }
        return chunks
    }

    private static func split(_ text: String, prefix: String, maxTokens: Int, counter: any TokenCounter) async throws -> [String] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var pieces: [String] = []
        var current = ""
        for word in words {
            let candidate = current.isEmpty ? word : current + " " + word
            if try await counter.tokens(in: prefix + candidate) <= maxTokens {
                current = candidate
            } else {
                if !current.isEmpty { pieces.append(prefix + current); current = "" }
                if try await counter.tokens(in: prefix + word) <= maxTokens {
                    current = word
                } else {
                    var fragment = ""
                    for char in word {
                        if try await counter.tokens(in: prefix + fragment + String(char)) > maxTokens, !fragment.isEmpty {
                            pieces.append(prefix + fragment)
                            fragment = ""
                        }
                        fragment.append(char)
                    }
                    if !fragment.isEmpty { pieces.append(prefix + fragment) }
                }
            }
        }
        if !current.isEmpty { pieces.append(prefix + current) }
        return pieces
    }
}

public struct PipelineProgress: Sendable, Equatable {
    public var stage: String; public var done: Int; public var total: Int
    public init(stage: String, done: Int, total: Int) { self.stage = stage; self.done = done; self.total = total }
}
public struct PipelineResult: Sendable, Equatable {
    public var notes: MeetingNotesResult?; public var warnings: [String]; public var digests: [ChunkDigest]
    public init(notes: MeetingNotesResult?, warnings: [String], digests: [ChunkDigest]) {
        self.notes = notes; self.warnings = warnings; self.digests = digests
    }
}

public struct NotesPipeline: Sendable {
    private let generator: any NotesGenerator
    private let counter: any TokenCounter
    private let budget: TokenBudget
    private let sleep: @Sendable (Duration) async -> Void

    public init(generator: any NotesGenerator, counter: any TokenCounter, budget: TokenBudget = .init(),
                sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.generator = generator; self.counter = counter; self.budget = budget; self.sleep = sleep
    }

    public func run(segments: [TranscriptSegment], userNotes: String,
                    onProgress: @escaping @Sendable (PipelineProgress) -> Void) async -> PipelineResult {
        guard !segments.isEmpty else { return PipelineResult(notes: nil, warnings: ["No transcript to summarize."], digests: []) }
        do {
            let chunks = try await Chunker.chunk(segments, maxTokens: budget.chunkTokens, counter: counter)
            var digests: [ChunkDigest] = []
            var warnings: [String] = []
            for (index, chunk) in chunks.enumerated() {
                if Task.isCancelled { return PipelineResult(notes: nil, warnings: ["Cancelled."], digests: digests) }
                onProgress(PipelineProgress(stage: "enhancing", done: index + 1, total: chunks.count))
                do { digests.append(try await digest(chunk.text, depth: 0)) }
                catch let error as GeneratorError {
                    switch error {
                    case .unavailable(let reason):
                        return PipelineResult(notes: nil, warnings: ["Apple Intelligence unavailable: \(reason)"], digests: digests)
                    case .refused:
                        digests.append(ChunkDigest(topics: [], decisions: [], actionItems: [], questions: [], keyPoints: [], unavailable: true))
                        warnings.append("Chunk \(index + 1) (\(Self.time(chunk.startSeconds))–\(Self.time(chunk.endSeconds))): summary unavailable.")
                    case .contextExceeded:
                        digests.append(ChunkDigest(topics: [], decisions: [], actionItems: [], questions: [], keyPoints: [], unavailable: true))
                        warnings.append("Chunk \(index + 1) (\(Self.time(chunk.startSeconds))–\(Self.time(chunk.endSeconds))): summary unavailable.")
                    case .rateLimited:
                        digests.append(ChunkDigest(topics: [], decisions: [], actionItems: [], questions: [], keyPoints: [], unavailable: true))
                        warnings.append("Chunk \(index + 1) (\(Self.time(chunk.startSeconds))–\(Self.time(chunk.endSeconds))): summary unavailable.")
                    }
                } catch {
                    return PipelineResult(notes: nil, warnings: ["Apple Intelligence unavailable: \(error.localizedDescription)"], digests: digests)
                }
            }
            let available = digests.filter { !$0.unavailable }
            guard !available.isEmpty else { return PipelineResult(notes: nil, warnings: warnings + ["No chunk could be summarized."], digests: digests) }
            let merged = try await reduce(available)
            let trimmedNotes = try await trimNotes(userNotes, warnings: &warnings)
            let notes: MeetingNotesResult
            do { notes = try await finalize(notes: trimmedNotes, digest: merged) }
            catch GeneratorError.contextExceeded {
                if !warnings.contains(where: { $0.hasPrefix("Your notes were longer") }) {
                    warnings.append("Your notes were longer than the model window; the enhanced notes use the first 0 lines. Your full notes are kept below.")
                }
                notes = try await finalize(notes: "", digest: merged)
            } catch let error as GeneratorError {
                switch error {
                case .refused: return PipelineResult(notes: nil, warnings: warnings + ["The final notes were refused."], digests: digests)
                case .unavailable(let reason): return PipelineResult(notes: nil, warnings: warnings + ["Apple Intelligence unavailable: \(reason)"], digests: digests)
                case .rateLimited, .contextExceeded: return PipelineResult(notes: nil, warnings: warnings + ["The final notes could not be generated."], digests: digests)
                }
            }
            return PipelineResult(notes: notes, warnings: warnings, digests: digests)
        } catch is CancellationError {
            return PipelineResult(notes: nil, warnings: ["Cancelled."], digests: [])
        } catch {
            return PipelineResult(notes: nil, warnings: ["Apple Intelligence unavailable: \(error.localizedDescription)"], digests: [])
        }
    }

    private func digest(_ text: String, depth: Int) async throws -> ChunkDigest {
        if Task.isCancelled { throw CancellationError() }
        do {
            for attempt in 0..<4 {
                if Task.isCancelled { throw CancellationError() }
                do { return try await generator.digest(transcriptChunk: text) }
                catch GeneratorError.rateLimited where attempt < 3 { await sleep(.seconds(1)) }
            }
            throw GeneratorError.refused
        } catch GeneratorError.contextExceeded where depth < 3 {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard lines.count > 1 else { throw GeneratorError.refused }
            let midpoint = lines.count / 2
            let left = try await digest(lines[..<midpoint].joined(separator: "\n"), depth: depth + 1)
            let right = try await digest(lines[midpoint...].joined(separator: "\n"), depth: depth + 1)
            return try await generator.merge(digests: [left, right])
        }
    }

    private func reduce(_ source: [ChunkDigest]) async throws -> ChunkDigest {
        var current = source
        while current.count > 1 {
            var batches: [[ChunkDigest]] = []
            var batch: [ChunkDigest] = []
            var cost = 0
            for digest in current {
                let itemCost = try await counter.tokens(in: Self.digestText(digest))
                if !batch.isEmpty && cost + itemCost + 1 > budget.chunkTokens {
                    batches.append(batch); batch = []; cost = 0
                }
                batch.append(digest); cost += itemCost + (batch.count > 1 ? 1 : 0)
            }
            if !batch.isEmpty { batches.append(batch) }
            if batches.count == current.count { batches = stride(from: 0, to: current.count, by: 2).map { Array(current[$0..<min($0 + 2, current.count)]) } }
            current = try await withThrowingTaskGroup(of: (Int, ChunkDigest).self) { group in
                for (index, values) in batches.enumerated() {
                    group.addTask { (index, try await generator.merge(digests: values)) }
                }
                var results = Array<ChunkDigest?>(repeating: nil, count: batches.count)
                for try await (index, value) in group { results[index] = value }
                return results.compactMap { $0 }
            }
        }
        return current[0]
    }

    private func trimNotes(_ notes: String, warnings: inout [String]) async throws -> String {
        guard try await counter.tokens(in: notes) > budget.userNotes else { return notes }
        var kept: [String] = []
        for line in notes.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let candidate = (kept + [line]).joined(separator: "\n")
            if try await counter.tokens(in: candidate) > budget.userNotes { break }
            kept.append(line)
        }
        warnings.append("Your notes were longer than the model window; the enhanced notes use the first \(kept.count) lines. Your full notes are kept below.")
        return kept.joined(separator: "\n")
    }

    private func finalize(notes: String, digest: ChunkDigest) async throws -> MeetingNotesResult {
        if Task.isCancelled { throw CancellationError() }
        return try await generator.finalize(userNotes: notes, merged: digest)
    }

    private static func digestText(_ digest: ChunkDigest) -> String {
        (digest.topics + digest.decisions + digest.actionItems + digest.questions + digest.keyPoints).joined(separator: "\n")
    }
    private static func time(_ seconds: Double) -> String { Timecode.string(seconds) }
}
