import Foundation
import Testing
@testable import Theme

@Suite struct ThemeTests {
    @Test func colorMathAndHexParsing() throws {
        let black = try #require(parseHex("#000000")), white = try #require(parseHex("FFFFFF"))
        #expect(luminance(black) == 0 && luminance(white) == 1)
        #expect(abs(contrastRatio(black, white) - 21) < 0.01)
        #expect(contrastRatio(black, black) == 1)
        #expect(abs(contrastRatio(try #require(parseHex("#777777")), white) - 4.48) < 0.02)
        #expect(parseHex("#FF7A00") == RGB(r: 1, g: 122.0 / 255, b: 0))
        #expect(parseHex("#FFF") == nil && parseHex("#GG0000") == nil && parseHex("#FF7A0080") == nil && parseHex("") == nil)
        #expect(hexString(mix(black, white, 0.5)) == "#808080")
        for theme in BuiltInThemes.all {
            for color in [theme.canvas, theme.ink, theme.mutedInk, theme.accent] + theme.headings {
                #expect(hexString(try #require(parseHex(color))) == color.uppercased())
            }
        }
    }

    @Test func builtInsValidateAndRoundTrip() throws {
        #expect(BuiltInThemes.all.map(\.id) == ["sacred", "gruvbox-dark", "gruvbox-light", "dracula", "nord", "tokyo-night", "catppuccin-mocha", "solarized-dark", "solarized-light"])
        #expect(Set(BuiltInThemes.all.map(\.id)).count == BuiltInThemes.all.count)
        for theme in BuiltInThemes.all {
            #expect(theme.headings.count == 6)
            #expect(ThemeLoader.validate(theme).isEmpty)
            let data = try JSONEncoder().encode(theme)
            #expect(try JSONDecoder().decode(Theme.self, from: data) == theme)
        }
        let sacred = try #require(BuiltInThemes.theme(id: "sacred"))
        #expect(sacred.codeBg == hexString(mix(try #require(parseHex("#000000")), try #require(parseHex("#F2F2F2")), 0.06)))
        #expect(sacred.selection.hasSuffix("59"))
    }

    @Test func loaderSkipsInvalidAndWarnsOnContrast() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let good = try #require(BuiltInThemes.theme(id: "sacred"))
        try JSONEncoder().encode(good).write(to: directory.appendingPathComponent("valid.json"))
        try Data("{".utf8).write(to: directory.appendingPathComponent("malformed.json"))
        var short = good; short.id = "short"; short.headings.removeLast()
        try JSONEncoder().encode(short).write(to: directory.appendingPathComponent("short.json"))
        var badColor = good; badColor.id = "bad"; badColor.canvas = "red"
        try JSONEncoder().encode(badColor).write(to: directory.appendingPathComponent("bad.json"))
        let loaded = ThemeLoader.load(from: directory)
        #expect(loaded.themes.count == 3)
        #expect(loaded.warnings.count == 3)
        var lowContrast = good; lowContrast.ink = "#111111"
        #expect(!ThemeLoader.validate(lowContrast).isEmpty)
    }
}
