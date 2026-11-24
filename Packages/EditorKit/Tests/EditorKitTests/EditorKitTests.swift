import Foundation
import Testing
@testable import EditorKit

@Suite struct MarkdownTokenizerTests {
    private func summary(_ text: String) -> [String] {
        let source = text as NSString
        return MarkdownTokenizer.tokenize(text).map { span in
            let name: String
            switch span.kind {
            case .heading(let level): name = "heading(\(level))"
            case .headingMarker: name = "headingMarker"
            case .bold: name = "bold"
            case .italic: name = "italic"
            case .boldItalic: name = "boldItalic"
            case .strike: name = "strike"
            case .highlight: name = "highlight"
            case .inlineCode: name = "inlineCode"
            case .marker: name = "marker"
            case .codeBlock: name = "codeBlock"
            case .fence: name = "fence"
            case .listMarker: name = "listMarker"
            case .taskBox(let checked): name = "taskBox(\(checked))"
            case .quoteMarker: name = "quoteMarker"
            case .quote: name = "quote"
            case .linkText: name = "linkText"
            case .linkURL: name = "linkURL"
            case .tag: name = "tag"
            case .frontmatter: name = "frontmatter"
            case .rule: name = "rule"
            }
            return "\(name):\(source.substring(with: span.range))"
        }
    }

    @Test func tokenizerContractExamples() {
        let rows: [(String, [String])] = [
            ("# Title", ["headingMarker:# ", "heading(1):Title"]),
            ("###### Six", ["headingMarker:###### ", "heading(6):Six"]),
            ("####### Seven", []), ("#tag", ["tag:#tag"]), ("# ", ["headingMarker:# "]),
            ("text #tag more", ["tag:#tag"]),
            ("**bold**", ["marker:**", "bold:bold", "marker:**"]),
            ("*it*", ["marker:*", "italic:it", "marker:*"]),
            ("***bi***", ["marker:***", "boldItalic:bi", "marker:***"]),
            ("~~gone~~", ["marker:~~", "strike:gone", "marker:~~"]),
            ("==hi==", ["marker:==", "highlight:hi", "marker:=="]),
            ("`code`", ["marker:`", "inlineCode:code", "marker:`"]),
            ("`**not bold**`", ["marker:`", "inlineCode:**not bold**", "marker:`"]),
            ("snake_case_name", []), ("2 * 3 * 4", []),
            ("[link](https://x.y)", ["marker:[", "linkText:link", "marker:](", "linkURL:https://x.y", "marker:)"]),
            ("- item", ["listMarker:- "]), ("* item", ["listMarker:* "]), ("+ item", ["listMarker:+ "]),
            ("1. one", ["listMarker:1. "]), ("10) ten", ["listMarker:10) "]),
            ("  - nested", ["listMarker:- "]), ("- [ ] todo", ["listMarker:- ", "taskBox(false):[ ]"]),
            ("- [x] done", ["listMarker:- ", "taskBox(true):[x]"]), ("- [X] done", ["listMarker:- ", "taskBox(true):[X]"]),
            ("> quote", ["quoteMarker:> ", "quote:quote"]), ("para\n---", ["rule:---"]),
            ("---\ntitle: x\n---\n# H", ["frontmatter:---\ntitle: x\n---", "headingMarker:# ", "heading(1):H"]),
            ("```swift\nlet x = 1 // # no\n```", ["fence:```swift", "codeBlock:let x = 1 // # no", "fence:```"]),
            ("```\ncode", ["fence:```", "codeBlock:code"]),
            ("- **b** item", ["listMarker:- ", "marker:**", "bold:b", "marker:**"]),
            ("# héllo 日本語", ["headingMarker:# ", "heading(1):héllo 日本語"]),
            ("**🎙️ x**", ["marker:**", "bold:🎙️ x", "marker:**"]), ("", []),
            ("# A\r\n- b", ["headingMarker:# ", "heading(1):A", "listMarker:- "]), ("a --- b", []), ("##nospace", [])
        ]
        for (input, expected) in rows { #expect(summary(input) == expected, "input: \(input)") }
    }

    @Test func seededRangesAlwaysValidAndSorted() {
        let alphabet = Array("#*_~=\u{0060}[]()>-+ 0123456789abc\n\r\t🎙️")
        var seed: UInt64 = 0xC0FFEE
        for _ in 0..<1_000 {
            seed = seed &* 6364136223846793005 &+ 1
            let length = Int(seed % 201)
            var characters: [Character] = []
            for _ in 0..<length {
                seed = seed &* 6364136223846793005 &+ 1
                characters.append(alphabet[Int(seed % UInt64(alphabet.count))])
            }
            let text = String(characters), utf16Count = (text as NSString).length
            let spans = MarkdownTokenizer.tokenize(text)
            var previous: MDSpan?
            for span in spans {
                #expect(span.range.location >= 0 && span.range.length > 0 && NSMaxRange(span.range) <= utf16Count)
                if let previous {
                    #expect(previous.range.location < span.range.location || (previous.range.location == span.range.location && previous.range.length <= span.range.length))
                }
                previous = span
            }
        }
    }
}

@Suite struct EditingHelpersTests {
    @Test func listContinuation() {
        let rows: [(String, ListAction)] = [
            ("- item", .insert("\n- ")), ("* item", .insert("\n* ")), ("+ item", .insert("\n+ ")),
            ("  - nested", .insert("\n  - ")), ("1. one", .insert("\n2. ")), ("9. nine", .insert("\n10. ")),
            ("3) x", .insert("\n4) ")), ("- [ ] todo", .insert("\n- [ ] ")), ("- [x] done", .insert("\n- [ ] ")),
            ("> quote", .insert("\n> ")), ("- ", .exitList), ("1. ", .exitList), ("- [ ] ", .exitList), ("> ", .exitList),
            ("-", .none), ("plain", .none), ("", .none), ("    four spaces", .none)
        ]
        for (line, expected) in rows { #expect(ListContinuation.onEnter(line: line) == expected) }
    }

    @Test func taskToggleIndentAndHeadingScale() {
        let rows = [("- [ ] a", "- [x] a"), ("- [x] a", "- [ ] a"), ("- [X] a", "- [ ] a"), ("* [ ] a", "* [x] a"), ("1. [ ] a", "1. [x] a"), ("  - [ ] n", "  - [x] n"), ("- a", "- [ ] a"), ("1. a", "1. [ ] a"), ("a", "- [ ] a"), ("", "- [ ] ")]
        for (input, expected) in rows { #expect(TaskToggle.toggle(line: input) == expected) }
        #expect(ListContinuation.indent("- a") == "  - a")
        #expect(ListContinuation.outdent("  - a") == "- a")
        #expect(ListContinuation.outdent("- a") == "- a")
        #expect(ListContinuation.outdent(" - a") == "- a")
        #expect(ListContinuation.outdent("\t- a") == "- a")
        let proportional = [2.0, 1.6, 1.37, 1.25, 1.12, 1.12]
        let mono = [1.75, 1.5, 1.25, 1.1, 1.0, 1.0]
        for index in 0..<6 {
            #expect(HeadingScale.scale(level: index + 1, monospaced: false) == proportional[index])
            #expect(HeadingScale.scale(level: index + 1, monospaced: true) == mono[index])
        }
        #expect(HeadingScale.scale(level: 0, monospaced: false) == 2 && HeadingScale.scale(level: 9, monospaced: false) == 1.12)
        #expect(HeadingScale.isBold(level: 6, monospaced: false) && HeadingScale.isBold(level: 5, monospaced: true) && !HeadingScale.isBold(level: 6, monospaced: true))
    }
}
