import Foundation

public struct SessionGroup: Equatable, Sendable {
    public var title: String
    public var sessions: [Session]

    public init(title: String, sessions: [Session]) {
        self.title = title
        self.sessions = sessions
    }
}

public enum SessionGrouping {
    public static func group(_ sessions: [Session], now: Date, calendar: Calendar) -> [SessionGroup] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let buckets = Dictionary(grouping: sessions) { session -> String in
            let day = calendar.startOfDay(for: session.createdAt)
            if day >= today { return "Today" }
            if day >= yesterday { return "Yesterday" }
            return "Earlier"
        }
        return ["Today", "Yesterday", "Earlier"].compactMap { title in
            guard let values = buckets[title], !values.isEmpty else { return nil }
            return SessionGroup(title: title, sessions: values.sorted { $0.createdAt > $1.createdAt })
        }
    }
}

public enum Timecode {
    public static func string(_ seconds: Double) -> String {
        let value = seconds.isFinite ? max(0, Int(seconds)) : 0
        let hours = value / 3600
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, (value / 60) % 60, value % 60) : String(format: "%02d:%02d", value / 60, value % 60)
    }
    public static func hms(_ seconds: Double) -> String {
        let value = seconds.isFinite ? max(0, Int(seconds)) : 0
        return String(format: "%02d:%02d:%02d", value / 3600, (value / 60) % 60, value % 60)
    }
}

public enum MeterGlyph {
    public static func glyph(forPeak peak: Float) -> Character {
        let db = 20 * log10(max(Double(peak.isFinite ? peak : 0), 1e-9))
        let levels: [(Double, Character)] = [(-6, "█"), (-12, "▇"), (-18, "▆"), (-24, "▅"), (-36, "▄"), (-48, "▃"), (-60, "▂")]
        return levels.first(where: { db > $0.0 })?.1 ?? "▁"
    }
}

public enum ProgressBar {
    public static func text(fraction: Double, cells: Int = 10) -> String {
        let safeFraction = fraction.isNaN ? 0 : min(1, max(0, fraction))
        let safeCells = max(0, cells)
        let filled = Int(safeFraction * Double(safeCells))
        return "[\(String(repeating: "█", count: filled))\(String(repeating: "░", count: safeCells - filled))] \(Int(safeFraction * 100))%"
    }
}

public enum ProcessingStage: String, Codable, Sendable, CaseIterable {
    case loadingModel, transcribing, merging, loadingNotesModel, enhancing, writing
}

extension ProcessingStage {
    public var title: String {
        switch self {
        case .loadingModel: "Loading model"
        case .transcribing: "Transcribing"
        case .merging: "Merging"
        case .loadingNotesModel: "Loading notes model"
        case .enhancing: "Enhancing notes"
        case .writing: "Writing files"
        }
    }
}
