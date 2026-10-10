import AppKit
import SwiftUI
import YuzuHarness

enum AppTheme: String, CaseIterable, Sendable {
    case system
    case dark
    case light

    var palette: Tokens.Palette {
        switch self {
        case .dark:
            return Tokens.dark
        case .light:
            return Tokens.light
        case .system:
            let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark ? Tokens.dark : Tokens.light
        }
    }
}

struct ThemeColors {
    let palette: Tokens.Palette

    var canvas: Color { Color(hex: palette.canvas) }
    var side: Color { Color(hex: palette.side) }
    var surface: Color { Color(hex: palette.surface) }
    var surfaceHover: Color { Color(hex: palette.surfaceHover) }
    var selected: Color { Color(hex: palette.selected) }
    var line: Color { Color(hex: palette.line) }
    var text: Color { Color(hex: palette.text) }
    var muted: Color { Color(hex: palette.muted) }
    var dim: Color { Color(hex: palette.dim) }
    var accent: Color { Color(hex: palette.accent) }
    var focus: Color { Color(hex: palette.focus) }

    private var isDark: Bool { palette.canvas == Tokens.dark.canvas }
    private func tone(_ dark: String, _ light: String) -> Color { Color(hex: isDark ? dark : light) }

    /// `--tone-e1e5e3`
    var softText: Color { tone("#E1E5E3", "#27392E") }
    /// `--tone-aab2b4`
    var subtle: Color { tone("#AAB2B4", "#52665A") }
    /// `--tone-292d30`
    var preview: Color { tone("#292D30", "#E9EEE9") }
    /// `--tone-394b43`, the idle `.thread-send`.
    var sendIdle: Color { tone("#394B43", "#C1D5C7") }
    /// `--tone-93ab9d`
    var sendIdleText: Color { tone("#93AB9D", "#50735E") }
    /// The ready `.thread-send` glyph.
    var onAccent: Color { tone("#1B1D20", "#FFFFFF") }
    /// `--tone-729885`, `.code-heatmap .level-1`.
    var heatLow: Color { tone("#729885", "#9DB8A6") }
    /// `--tone-2a4037`, the pressed `.thread-layout`.
    var toggleOn: Color { tone("#2A4037", "#DDEAE0") }
    var toggleOnText: Color { tone("#B9D3C4", "#456B55") }
    /// `--tone-596265`
    var stepBorder: Color { tone("#596265", "#9AADA0") }
}

/// Colors for code in the transcript and the Settings previews.
/// The GitHub palettes are the handoff's `.settings-preview` colors.
enum CodeTheme: String, CaseIterable, Sendable {
    case githubLight = "GitHub Light"
    case defaultLight = "Default Light"
    case githubDark = "GitHub Dark"
    case defaultDark = "Default Dark"

    static let light: [CodeTheme] = [.githubLight, .defaultLight]
    static let dark: [CodeTheme] = [.githubDark, .defaultDark]

    struct Palette {
        let background: String
        let text: String
        let number: String
        let function: String
        let string: String
        let keyword: String
        let template: String
        let removedBackground: String
        let removedText: String
        let addedBackground: String
        let addedText: String
    }

    var palette: Palette {
        switch self {
        case .githubLight:
            Palette(
                background: "#ffffff", text: "#24292f", number: "#57646D",
                function: "#ea3850", string: "#1948a5", keyword: "#ef3d37", template: "#2b679e",
                removedBackground: "#f9e9ec", removedText: "#dd242e",
                addedBackground: "#e9f5e9", addedText: "#1a9b41"
            )
        case .defaultLight:
            Palette(
                background: "#f7f7f7", text: "#1f1f1f", number: "#6e7781",
                function: "#795e26", string: "#a31515", keyword: "#0000ff", template: "#a31515",
                removedBackground: "#fbe4e4", removedText: "#a1260d",
                addedBackground: "#e3f2e1", addedText: "#116329"
            )
        case .githubDark:
            Palette(
                background: "#242a31", text: "#d7dfe8", number: "#9DA5A6",
                function: "#f08d94", string: "#a8bdff", keyword: "#f88787", template: "#8ac8e6",
                removedBackground: "#52383e", removedText: "#ee7282",
                addedBackground: "#2b4b3a", addedText: "#54d67b"
            )
        case .defaultDark:
            Palette(
                background: "#1e1e1e", text: "#d4d4d4", number: "#858585",
                function: "#dcdcaa", string: "#ce9178", keyword: "#569cd6", template: "#ce9178",
                removedBackground: "#4b1818", removedText: "#f48771",
                addedBackground: "#373d29", addedText: "#89d185"
            )
        }
    }
}

/// The handoff's four-line `greet` diff, drawn in one code theme.
struct CodeThemePreview: View {
    let theme: CodeTheme
    let codeFont: String

    var body: some View {
        let palette = theme.palette
        VStack(alignment: .leading, spacing: 0) {
            line("1", palette: palette, background: nil) {
                Text(verbatim: "function").foregroundColor(Color(hex: palette.function))
                    + Text(verbatim: " ")
                    + Text(verbatim: "greet").foregroundColor(Color(hex: palette.function))
                    + Text(verbatim: "(")
                    + Text(verbatim: "name").foregroundColor(Color(hex: palette.function))
                    + Text(verbatim: ": ")
                    + Text(verbatim: "string").foregroundColor(Color(hex: palette.string))
                    + Text(verbatim: ") {")
            }
            line("2 -", palette: palette, background: palette.removedBackground) {
                Text(verbatim: "return").foregroundColor(Color(hex: palette.keyword))
                    + Text(verbatim: " ")
                    + Text(verbatim: "\"Hello, \"").foregroundColor(Color(hex: palette.string))
                    + Text(verbatim: " + name;").foregroundColor(Color(hex: palette.removedText))
            }
            line("2 +", palette: palette, background: palette.addedBackground) {
                Text(verbatim: "return").foregroundColor(Color(hex: palette.keyword))
                    + Text(verbatim: " ")
                    + Text(verbatim: "`Hello, ${name}!`").foregroundColor(Color(hex: palette.template))
                    + Text(verbatim: ";").foregroundColor(Color(hex: palette.addedText))
            }
            line("3", palette: palette, background: nil) { Text(verbatim: "}") }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112, alignment: .topLeading)
        .background(Color(hex: palette.background))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(hex: "#373d40"), lineWidth: 1))
    }

    private func line(
        _ number: String,
        palette: CodeTheme.Palette,
        background: String?,
        @ViewBuilder code: () -> Text
    ) -> some View {
        HStack(spacing: 0) {
            Text(number)
                .foregroundColor(Color(hex: palette.number))
                .frame(width: 41, alignment: .trailing)
                .padding(.trailing, 6)
            // An overlay clips long lines without widening the column, as the handoff's `text-overflow: clip`.
            Color.clear
                .overlay(alignment: .leading) {
                    code()
                        .foregroundColor(Color(hex: background == palette.removedBackground ? palette.removedText
                            : background == palette.addedBackground ? palette.addedText : palette.text))
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.leading, 27)
                }
                .clipped()
        }
        .font(YuzuFonts.code(codeFont, size: 15))
        .frame(height: 23)
        .background(background.map { Color(hex: $0) } ?? .clear)
    }
}

/// A fenced code block in the transcript, in the user's code font and theme.
struct CodeBlockView: View {
    let code: String
    let theme: CodeTheme
    let codeFont: String
    let size: CGFloat

    var body: some View {
        let palette = theme.palette
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code)
                .font(YuzuFonts.code(codeFont, size: size))
                .foregroundColor(Color(hex: palette.text))
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
                .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: palette.background))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(hex: "#373d40"), lineWidth: 1))
    }
}

/// Splits assistant text into prose and fenced code segments.
enum FencedText {
    enum Segment: Equatable {
        case prose(String)
        case code(String)
    }

    static func segments(_ text: String) -> [Segment] {
        var segments: [Segment] = []
        var prose: [Substring] = []
        var code: [Substring]?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if let open = code {
                    segments.append(.code(open.joined(separator: "\n")))
                    code = nil
                } else {
                    let joined = prose.joined(separator: "\n").trimmingCharacters(in: .newlines)
                    if !joined.isEmpty { segments.append(.prose(joined)) }
                    prose = []
                    code = []
                }
            } else if code != nil {
                code?.append(line)
            } else {
                prose.append(line)
            }
        }
        if let open = code {
            segments.append(.code(open.joined(separator: "\n")))
        }
        let rest = prose.joined(separator: "\n").trimmingCharacters(in: .newlines)
        if !rest.isEmpty { segments.append(.prose(rest)) }
        return segments
    }
}

struct AppearanceSettings: Codable {
    var theme: String
    var chatFont: String
    var motionSetting: String
    var codeFont: String
    var interfaceFont: String
    var transcriptSize: String
    var transcriptWidth: String
    var transcriptView: String
    var lightCodeTheme: String
    var darkCodeTheme: String
}

enum MotionTiming {
    static func durations(reduceMotion: Bool) -> (hoverMs: Int, drawerMs: Int) {
        if reduceMotion {
            return (0, 0)
        }
        return (Tokens.hoverDurationMs, Tokens.drawerDurationMs)
    }

    static func animation(reduceMotion: Bool, drawer: Bool = false) -> Animation? {
        let ms = drawer ? durations(reduceMotion: reduceMotion).drawerMs : durations(reduceMotion: reduceMotion).hoverMs
        if ms == 0 { return nil }
        let ease = Tokens.ease
        return .timingCurve(ease.x1, ease.y1, ease.x2, ease.y2, duration: Double(ms) / 1000)
    }
}

enum YuzuFonts {
    static let interfaceChoices = ["Inter", "System", "OpenDyslexic"]
    static let chatChoices = ["Source Serif", "System"]

    /// Inter, Source Serif 4 and OpenDyslexic ship in the bundle's `Fonts` folder under the SIL OFL.
    static func interfaceFamily(_ choice: String) -> String {
        switch choice {
        case "Inter": return "Inter"
        case "OpenDyslexic": return "OpenDyslexic"
        default: return ""
        }
    }

    static func chatFamily(_ choice: String) -> String {
        choice == "System" ? "" : "Source Serif 4"
    }

    static func chat(_ choice: String, size: CGFloat) -> Font {
        let family = chatFamily(choice)
        return family.isEmpty ? .system(size: size) : .custom(family, size: size)
    }

    static func codeFamily(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : trimmed
    }

    static func interface(_ choice: String, size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let family = interfaceFamily(choice)
        if family.isEmpty {
            return .system(size: size, weight: weight)
        }
        return .custom(family, size: size).weight(weight)
    }

    static func code(_ name: String, size: CGFloat) -> Font {
        let family = codeFamily(name)
        if family.isEmpty {
            return .system(size: size, design: .monospaced)
        }
        return .custom(family, size: size)
    }
}

extension Color {
    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
