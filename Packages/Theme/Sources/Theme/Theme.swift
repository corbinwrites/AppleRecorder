import Foundation

public struct RGB: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
}

public func parseHex(_ string: String) -> RGB? {
    let value = string.hasPrefix("#") ? String(string.dropFirst()) : string
    guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
    return RGB(r: Double((number >> 16) & 0xff) / 255, g: Double((number >> 8) & 0xff) / 255, b: Double(number & 0xff) / 255)
}

public func hexString(_ color: RGB) -> String {
    let r = Int((min(1, max(0, color.r)) * 255).rounded())
    let g = Int((min(1, max(0, color.g)) * 255).rounded())
    let b = Int((min(1, max(0, color.b)) * 255).rounded())
    return String(format: "#%02X%02X%02X", r, g, b)
}

public func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
    RGB(r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t)
}

public func luminance(_ color: RGB) -> Double {
    func linear(_ value: Double) -> Double { value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
    return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
}

public func contrastRatio(_ a: RGB, _ b: RGB) -> Double {
    let first = luminance(a), second = luminance(b)
    return (max(first, second) + 0.05) / (min(first, second) + 0.05)
}

public struct Theme: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var isDark: Bool
    public var canvas: String
    public var ink: String
    public var mutedInk: String
    public var accent: String
    public var selection: String
    public var codeBg: String
    public var link: String
    public var quote: String
    public var tag: String
    public var strong: String
    public var marker: String
    public var headings: [String]

    public init(id: String, name: String, isDark: Bool, canvas: String, ink: String, mutedInk: String, accent: String, selection: String, codeBg: String, link: String, quote: String, tag: String, strong: String, marker: String, headings: [String]) {
        self.id = id; self.name = name; self.isDark = isDark; self.canvas = canvas; self.ink = ink; self.mutedInk = mutedInk; self.accent = accent
        self.selection = selection; self.codeBg = codeBg; self.link = link; self.quote = quote; self.tag = tag; self.strong = strong; self.marker = marker; self.headings = headings
    }

    public static func make(id: String, name: String, isDark: Bool, canvas: String, ink: String, mutedInk: String, accent: String, headings: [String]) -> Theme {
        let selection = "\(accent.uppercased())59"
        let code = parseHex(canvas).flatMap { c in parseHex(ink).map { hexString(mix(c, $0, 0.06)) } } ?? canvas
        return Theme(id: id, name: name, isDark: isDark, canvas: canvas, ink: ink, mutedInk: mutedInk, accent: accent, selection: selection, codeBg: code, link: accent, quote: mutedInk, tag: accent, strong: ink, marker: mutedInk, headings: headings)
    }
}

public enum SystemTheme { public static let id = "system" }

public enum BuiltInThemes {
    public static let all: [Theme] = [
        Theme.make(id: "sacred", name: "Sacred", isDark: true, canvas: "#000000", ink: "#F2F2F2", mutedInk: "#B8B8B8", accent: "#FF7A00", headings: ["#F2F2F2", "#F2F2F2", "#F2F2F2", "#F2F2F2", "#B8B8B8", "#B8B8B8"]),
        Theme.make(id: "gruvbox-dark", name: "Gruvbox Dark", isDark: true, canvas: "#282828", ink: "#EBDBB2", mutedInk: "#928374", accent: "#FE8019", headings: ["#FB4934", "#FE8019", "#FABD2F", "#B8BB26", "#83A598", "#D3869B"]),
        Theme.make(id: "gruvbox-light", name: "Gruvbox Light", isDark: false, canvas: "#FBF1C7", ink: "#3C3836", mutedInk: "#7C6F64", accent: "#AF3A03", headings: ["#9D0006", "#AF3A03", "#B57614", "#79740E", "#076678", "#8F3F71"]),
        Theme.make(id: "dracula", name: "Dracula", isDark: true, canvas: "#282A36", ink: "#F8F8F2", mutedInk: "#6272A4", accent: "#BD93F9", headings: ["#FF79C6", "#BD93F9", "#8BE9FD", "#50FA7B", "#FFB86C", "#F1FA8C"]),
        Theme.make(id: "nord", name: "Nord", isDark: true, canvas: "#2E3440", ink: "#D8DEE9", mutedInk: "#616E88", accent: "#88C0D0", headings: ["#88C0D0", "#81A1C1", "#8FBCBB", "#A3BE8C", "#EBCB8B", "#B48EAD"]),
        Theme.make(id: "tokyo-night", name: "Tokyo Night", isDark: true, canvas: "#1A1B26", ink: "#C0CAF5", mutedInk: "#565F89", accent: "#7AA2F7", headings: ["#7AA2F7", "#BB9AF7", "#7DCFFF", "#9ECE6A", "#E0AF68", "#F7768E"]),
        Theme.make(id: "catppuccin-mocha", name: "Catppuccin Mocha", isDark: true, canvas: "#1E1E2E", ink: "#CDD6F4", mutedInk: "#6C7086", accent: "#CBA6F7", headings: ["#F38BA8", "#FAB387", "#F9E2AF", "#A6E3A1", "#89B4FA", "#CBA6F7"]),
        Theme.make(id: "solarized-dark", name: "Solarized Dark", isDark: true, canvas: "#002B36", ink: "#93A1A1", mutedInk: "#657B83", accent: "#CB4B16", headings: ["#CB4B16", "#B58900", "#859900", "#268BD2", "#6C71C4", "#D33682"]),
        Theme.make(id: "solarized-light", name: "Solarized Light", isDark: false, canvas: "#FDF6E3", ink: "#586E75", mutedInk: "#93A1A1", accent: "#CB4B16", headings: ["#CB4B16", "#B58900", "#859900", "#268BD2", "#6C71C4", "#D33682"])
    ]
    public static func theme(id: String) -> Theme? { all.first { $0.id == id } }
}

public enum ThemeLoader {
    public static func validate(_ theme: Theme) -> [String] {
        var warnings: [String] = []
        let colors = [theme.canvas, theme.ink, theme.mutedInk, theme.accent, theme.selection, theme.codeBg, theme.link, theme.quote, theme.tag, theme.strong, theme.marker] + theme.headings
        if colors.contains(where: { parseHex($0) == nil && !($0.count == 9 && $0.hasPrefix("#") && UInt32($0.dropFirst(), radix: 16) != nil) }) { warnings.append("Invalid color") }
        guard let canvas = parseHex(theme.canvas) else { return warnings }
        func ratio(_ hex: String) -> Double { parseHex(hex).map { contrastRatio($0, canvas) } ?? 0 }
        if ratio(theme.ink) < 4.5 { warnings.append("Ink contrast is below 4.5") }
        if ratio(theme.accent) < 3 { warnings.append("Accent contrast is below 3.0") }
        if theme.headings.count != 6 { warnings.append("Theme must have six headings") }
        if theme.headings.contains(where: { ratio($0) < 2.5 }) { warnings.append("Heading contrast is below 2.5") }
        if ratio(theme.mutedInk) < 2 { warnings.append("Muted ink contrast is below 2.0") }
        return warnings
    }

    public static func load(from directory: URL) -> (themes: [Theme], warnings: [String]) {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var themes: [Theme] = [], warnings: [String] = []
        for url in urls.filter({ $0.pathExtension.lowercased() == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let theme = try JSONDecoder().decode(Theme.self, from: Data(contentsOf: url))
                themes.append(theme)
                if !validate(theme).isEmpty { warnings.append("\(url.lastPathComponent): \(validate(theme).joined(separator: ", "))") }
            } catch { warnings.append("\(url.lastPathComponent): invalid theme") }
        }
        return (themes, warnings)
    }
}
