import Testing
@testable import YuzuHarness

struct TokensTests {
    @Test func V0_tokensMatchHandoff() {
        #expect(Tokens.dark.canvas == "#1B1D20")
        #expect(Tokens.dark.side == "#16181B")
        #expect(Tokens.dark.surface == "#24272A")
        #expect(Tokens.dark.surfaceHover == "#2D3135")
        #expect(Tokens.dark.selected == "#373D40")
        #expect(Tokens.dark.line == "#3A4043")
        #expect(Tokens.dark.lineSoft == "#30373A")
        #expect(Tokens.dark.text == "#F0F2F1")
        #expect(Tokens.dark.muted == "#B9BFC0")
        #expect(Tokens.dark.dim == "#9DA5A6")
        #expect(Tokens.dark.accent == "#B9D3C4")
        #expect(Tokens.dark.focus == "#C8DFD1")

        #expect(Tokens.light.canvas == "#F3F5F2")
        #expect(Tokens.light.side == "#E8ECE8")
        #expect(Tokens.light.surface == "#FFFFFF")
        #expect(Tokens.light.surfaceHover == "#E1E8E2")
        #expect(Tokens.light.selected == "#D9E3DB")
        #expect(Tokens.light.line == "#CBD4CE")
        #expect(Tokens.light.lineSoft == "#D4DFD6")
        #expect(Tokens.light.text == "#1C2923")
        #expect(Tokens.light.muted == "#4F6157")
        #expect(Tokens.light.dim == "#5B6D62")
        #expect(Tokens.light.accent == "#567B64")
        #expect(Tokens.light.focus == "#2E684C")

        #expect(Tokens.sidebarWidth == 256)
        #expect(Tokens.contentWidth == 806)
        #expect(Tokens.hoverDurationMs == 180)
        #expect(Tokens.drawerDurationMs == 220)
        #expect(Tokens.ease == Tokens.Ease(x1: 0.2, y1: 0.8, x2: 0.2, y2: 1))
    }
}
