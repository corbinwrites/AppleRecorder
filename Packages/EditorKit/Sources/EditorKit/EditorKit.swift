import Foundation

public enum MDKind: Equatable, Sendable {
    case heading(Int), headingMarker, bold, italic, boldItalic, strike, highlight, inlineCode, marker
    case codeBlock, fence, listMarker, taskBox(checked: Bool), quoteMarker, quote
    case linkText, linkURL, tag, frontmatter, rule
}

public struct MDSpan: Equatable, Sendable {
    public var kind: MDKind
    public var range: NSRange
    public init(kind: MDKind, range: NSRange) { self.kind = kind; self.range = range }
}

public enum MarkdownTokenizer {
    private struct Line { var range: NSRange; var text: String }

    public static func tokenize(_ text: String) -> [MDSpan] {
        let source = text as NSString
        let lines = makeLines(source)
        var spans: [MDSpan] = []
        var lineIndex = 0
        if text.hasPrefix("---\n") || text.hasPrefix("---\r\n") {
            if let close = lines.indices.dropFirst().first(where: { lines[$0].text == "---" }) {
                let end = NSMaxRange(lines[close].range)
                spans.append(MDSpan(kind: .frontmatter, range: NSRange(location: 0, length: end)))
                lineIndex = close + 1
            }
        }
        var inFence = false
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            let content = line.text
            let leading = content.prefix(while: { $0 == " " || $0 == "\t" }).count
            let trimmed = String(content.dropFirst(leading))
            if trimmed.hasPrefix("```") {
                spans.append(MDSpan(kind: .fence, range: NSRange(location: line.range.location, length: line.range.length)))
                inFence.toggle()
                lineIndex += 1
                continue
            }
            if inFence {
                if !content.isEmpty { spans.append(MDSpan(kind: .codeBlock, range: line.range)) }
                lineIndex += 1
                continue
            }
            let fullRange = line.range
            let nsLine = content as NSString
            if let heading = match(#"^(#{1,6})( +)(.*)$"#, in: content), heading.numberOfRanges == 4 {
                let count = nsLine.substring(with: heading.range(at: 1)).count
                let markerRange = NSRange(location: heading.range(at: 1).location, length: heading.range(at: 1).length + heading.range(at: 2).length)
                spans.append(MDSpan(kind: .headingMarker, range: shifted(markerRange, by: fullRange.location)))
                let body = heading.range(at: 3)
                if body.length > 0 { spans.append(MDSpan(kind: .heading(count), range: shifted(body, by: fullRange.location))) }
                lineIndex += 1
                continue
            }
            if match(#"^\s*(?:---+|\*\*\*+|___+)\s*$"#, in: content) != nil {
                spans.append(MDSpan(kind: .rule, range: fullRange)); lineIndex += 1; continue
            }
            if let list = match(#"^( *)([-*+]|\d+[.)]) (.*)$"#, in: content) {
                let marker = list.range(at: 2)
                spans.append(MDSpan(kind: .listMarker, range: shifted(NSRange(location: marker.location, length: marker.length + 1), by: fullRange.location)))
                let remainder = nsLine.substring(from: NSMaxRange(marker) + 1)
                let remainderStart = NSMaxRange(marker) + 1
                if let task = match(#"^\[([ xX])\](?: |$)"#, in: remainder) {
                    let value = (remainder as NSString).substring(with: task.range(at: 1))
                    spans.append(MDSpan(kind: .taskBox(checked: value.lowercased() == "x"), range: shifted(NSRange(location: task.range(at: 0).location, length: 3), by: fullRange.location + remainderStart)))
                }
                _ = list
            }
            if let quote = match(#"^(> ?)(.*)$"#, in: content) {
                spans.append(MDSpan(kind: .quoteMarker, range: shifted(quote.range(at: 1), by: fullRange.location)))
                if quote.range(at: 2).length > 0 { spans.append(MDSpan(kind: .quote, range: shifted(quote.range(at: 2), by: fullRange.location))) }
            }
            spans.append(contentsOf: inlineSpans(content, offset: fullRange.location))
            lineIndex += 1
        }
        return spans.filter { $0.range.location >= 0 && $0.range.length > 0 && NSMaxRange($0.range) <= source.length }.sorted {
            $0.range.location == $1.range.location ? $0.range.length < $1.range.length : $0.range.location < $1.range.location
        }
    }

    private static func makeLines(_ source: NSString) -> [Line] {
        var result: [Line] = [], start = 0
        while start < source.length {
            let newline = source.range(of: "\n", options: [], range: NSRange(location: start, length: source.length - start))
            let rawEnd = newline.location == NSNotFound ? source.length : newline.location
            var end = rawEnd
            if end > start, source.character(at: end - 1) == 13 { end -= 1 }
            let range = NSRange(location: start, length: end - start)
            result.append(Line(range: range, text: source.substring(with: range)))
            if newline.location == NSNotFound { start = source.length } else { start = NSMaxRange(newline) }
        }
        return result
    }

    private static func match(_ pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func shifted(_ range: NSRange, by offset: Int) -> NSRange { NSRange(location: range.location + offset, length: range.length) }

    private static func inlineSpans(_ line: String, offset: Int) -> [MDSpan] {
        let ns = line as NSString
        var result: [MDSpan] = []
        var occupied: [NSRange] = []
        func isFree(_ range: NSRange) -> Bool { !occupied.contains { NSIntersectionRange($0, range).length > 0 } }
        func scan(_ pattern: String, kind: MDKind, delimiterGroup: Int = 1, contentGroup: Int = 2) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let full = NSRange(location: 0, length: ns.length)
            for match in regex.matches(in: line, range: full) {
                let whole = match.range(at: 0)
                guard isFree(whole) else { continue }
                let opening = match.range(at: delimiterGroup), body = match.range(at: contentGroup)
                let closing = NSRange(location: NSMaxRange(body), length: whole.length - (NSMaxRange(body) - whole.location))
                result.append(MDSpan(kind: .marker, range: shifted(opening, by: offset)))
                result.append(MDSpan(kind: kind, range: shifted(body, by: offset)))
                result.append(MDSpan(kind: .marker, range: shifted(closing, by: offset)))
                occupied.append(whole)
            }
        }
        scan(#"(`)([^`]+)(`)"#, kind: .inlineCode, delimiterGroup: 1, contentGroup: 2)
        scan(#"(\*\*\*|___)(\S(?:.*?\S)?)(\*\*\*|___)"#, kind: .boldItalic)
        scan(#"(\*\*|__)(\S(?:.*?\S)?)(\*\*|__)"#, kind: .bold)
        scan(#"(~~)(\S(?:.*?\S)?)(~~)"#, kind: .strike)
        scan(#"(==)(\S(?:.*?\S)?)(==)"#, kind: .highlight)
        scan(#"(\*)(\S(?:.*?\S)?)(\*)"#, kind: .italic)
        scan(#"(?<![\w])(_)(\S(?:.*?\S)?)(_)(?![\w])"#, kind: .italic, delimiterGroup: 1, contentGroup: 2)
        if let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#) {
            for match in regex.matches(in: line, range: NSRange(location: 0, length: ns.length)) where isFree(match.range(at: 0)) {
                let open = NSRange(location: match.range(at: 0).location, length: 1)
                let text = match.range(at: 1)
                let closeOpen = NSRange(location: NSMaxRange(text), length: 2)
                let url = match.range(at: 2)
                let close = NSRange(location: NSMaxRange(url), length: 1)
                result += [MDSpan(kind: .marker, range: shifted(open, by: offset)), MDSpan(kind: .linkText, range: shifted(text, by: offset)), MDSpan(kind: .marker, range: shifted(closeOpen, by: offset)), MDSpan(kind: .linkURL, range: shifted(url, by: offset)), MDSpan(kind: .marker, range: shifted(close, by: offset))]
                occupied.append(match.range(at: 0))
            }
        }
        if let regex = try? NSRegularExpression(pattern: #"(?<![\w#])#[\p{L}][\w/-]*"#) {
            for match in regex.matches(in: line, range: NSRange(location: 0, length: ns.length)) where isFree(match.range) {
                result.append(MDSpan(kind: .tag, range: shifted(match.range, by: offset)))
            }
        }
        return result
    }
}

public enum ListAction: Equatable, Sendable { case insert(String), exitList, none }
public enum ListContinuation {
    public static func onEnter(line: String) -> ListAction {
        if line == ">" || line == "> " { return .exitList }
        if line.range(of: #"^( *)([-*+]|\d+[.)]) (?:\[[ xX]\] )?$"#, options: .regularExpression) != nil { return .exitList }
        guard let match = line.range(of: #"^( *)([-*+]|(\d+)([.)])) (?:\[[ xX]\] )?.+$"#, options: .regularExpression) else {
            if line.range(of: #"^> .+$"#, options: .regularExpression) != nil { return .insert("\n> ") }
            return .none
        }
        let prefix = String(line[match])
        let indent = String(prefix.prefix(while: { $0 == " " }))
        let markerRange = prefix.range(of: #"[-*+]|\d+[.)]"#, options: .regularExpression)
        guard let markerRange else { return .none }
        let marker = String(prefix[markerRange])
        let itemPrefix: String
        if marker.first?.isNumber == true, let number = Int(marker.dropLast()) {
            itemPrefix = "\(number + 1)\(marker.last ?? ".") "
        } else { itemPrefix = "\(marker) " }
        let task = prefix.contains("[ ]") || prefix.contains("[x]") || prefix.contains("[X]") ? "[ ] " : ""
        return .insert("\n\(indent)\(itemPrefix)\(task)")
    }
    public static func indent(_ line: String) -> String { "  " + line }
    public static func outdent(_ line: String) -> String {
        if line.hasPrefix("\t") { return String(line.dropFirst()) }
        if line.hasPrefix("  ") { return String(line.dropFirst(2)) }
        if line.hasPrefix(" ") { return String(line.dropFirst()) }
        return line
    }
}

public enum TaskToggle {
    public static func toggle(line: String) -> String {
        if let range = line.range(of: #"(?<=^| )\[([ xX])\](?= |$)"#, options: .regularExpression) {
            let value = line[range]
            return line.replacingCharacters(in: range, with: value.lowercased().contains("x") ? "[ ]" : "[x]")
        }
        if let marker = line.range(of: #"^ *(?:[-*+] |\d+[.)] )"#, options: .regularExpression) {
            return line.replacingCharacters(in: marker, with: String(line[marker]) + "[ ] ")
        }
        return "- [ ] \(line)"
    }
}

public enum HeadingScale {
    private static let proportional = [2.0, 1.6, 1.37, 1.25, 1.12, 1.12]
    private static let monospacedValues = [1.75, 1.5, 1.25, 1.1, 1.0, 1.0]
    public static func scale(level: Int, monospaced: Bool) -> Double {
        let values = monospaced ? monospacedValues : proportional
        return values[min(6, max(1, level)) - 1]
    }
    public static func isBold(level: Int, monospaced: Bool) -> Bool { !monospaced || level <= 5 }
}
