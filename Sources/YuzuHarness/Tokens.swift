/// Visual tokens copied from the product handoff.
/// Dark values are `:root`. Light values are `:root[data-theme="light"]`.
public enum Tokens {
    public struct Palette: Sendable, Equatable {
        public let canvas: String
        public let side: String
        public let surface: String
        public let surfaceHover: String
        public let selected: String
        public let line: String
        public let lineSoft: String
        public let text: String
        public let muted: String
        public let dim: String
        public let accent: String
        public let focus: String
    }

    /// CSS `cubic-bezier(x1, y1, x2, y2)` from `--ease`.
    public struct Ease: Sendable, Equatable {
        public let x1: Double
        public let y1: Double
        public let x2: Double
        public let y2: Double
    }

    public static let dark = Palette(
        canvas: "#1B1D20",
        side: "#16181B",
        surface: "#24272A",
        surfaceHover: "#2D3135",
        selected: "#373D40",
        line: "#3A4043",
        lineSoft: "#30373A",
        text: "#F0F2F1",
        muted: "#B9BFC0",
        dim: "#9DA5A6",
        accent: "#B9D3C4",
        focus: "#C8DFD1"
    )

    public static let light = Palette(
        canvas: "#F3F5F2",
        side: "#E8ECE8",
        surface: "#FFFFFF",
        surfaceHover: "#E1E8E2",
        selected: "#D9E3DB",
        line: "#CBD4CE",
        lineSoft: "#D4DFD6",
        text: "#1C2923",
        muted: "#4F6157",
        dim: "#5B6D62",
        accent: "#567B64",
        focus: "#2E684C"
    )

    /// `--sidebar-width` at desktop.
    public static let sidebarWidth = 256

    /// `--content-width` maximum for the primary column.
    public static let contentWidth = 806

    /// Hover transitions in the handoff, in milliseconds.
    public static let hoverDurationMs = 180

    /// Sidebar drawer transition in the handoff, in milliseconds.
    public static let drawerDurationMs = 220

    public static let ease = Ease(x1: 0.2, y1: 0.8, x2: 0.2, y2: 1)
}
