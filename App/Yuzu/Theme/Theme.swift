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
    static func interfaceFamily(_ choice: String) -> String {
        switch choice {
        case "Serif": return "Georgia"
        case "OpenDyslexic": return "OpenDyslexic"
        default: return ""
        }
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
