import SwiftUI

/// Block structure for assistant markdown. Inline emphasis stays in each block's text.
enum MarkdownBlocks {
    enum Block: Equatable {
        case heading(level: Int, text: String)
        case bullet(String)
        case numbered(marker: String, text: String)
        case quote(String)
        case rule
        case paragraph(String)
    }

    static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []

        func flushParagraph() {
            let joined = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                blocks.append(.paragraph(joined))
            }
            paragraph = []
        }

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            if trimmed.allSatisfy({ $0 == "-" || $0 == "*" }) && trimmed.count >= 3 {
                flushParagraph()
                blocks.append(.rule)
                continue
            }
            if let heading = heading(trimmed) {
                flushParagraph()
                blocks.append(heading)
                continue
            }
            if let bullet = bullet(trimmed) {
                flushParagraph()
                blocks.append(.bullet(bullet))
                continue
            }
            if let numbered = numbered(trimmed) {
                flushParagraph()
                blocks.append(numbered)
                continue
            }
            if trimmed.hasPrefix(">") {
                flushParagraph()
                let body = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                blocks.append(.quote(String(body)))
                continue
            }
            paragraph.append(trimmed)
        }
        flushParagraph()
        return blocks
    }

    private static func heading(_ line: String) -> Block? {
        let marks = line.prefix { $0 == "#" }
        guard (1...3).contains(marks.count), line.dropFirst(marks.count).first == " " else { return nil }
        let title = line.dropFirst(marks.count).trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return .heading(level: marks.count, text: title)
    }

    private static func bullet(_ line: String) -> String? {
        guard line.hasPrefix("- ") || line.hasPrefix("* ") else { return nil }
        return String(line.dropFirst(2))
    }

    private static func numbered(_ line: String) -> Block? {
        guard let dot = line.firstIndex(of: "."), dot > line.startIndex else { return nil }
        let marker = line[..<dot]
        guard marker.allSatisfy(\.isNumber), line.index(after: dot) < line.endIndex, line[line.index(after: dot)] == " " else {
            return nil
        }
        let text = line[line.index(dot, offsetBy: 2)...]
        return .numbered(marker: String(marker), text: String(text))
    }
}

/// Assistant prose: headings, lists, quotes, and inline markdown, in the thread's type and colors.
struct MarkdownProse: View {
    let text: String
    let font: Font
    let colors: ThemeColors

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlocks.parse(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlocks.Block) -> some View {
        switch block {
        case .heading(let level, let title):
            inline(title)
                .font(headingFont(level))
                .foregroundStyle(colors.text)
                .padding(.top, level == 1 ? 8 : 4)
        case .bullet(let item):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(font)
                    .foregroundStyle(colors.dim)
                inline(item)
                    .font(font)
                    .foregroundStyle(colors.text)
            }
        case .numbered(let marker, let item):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(marker).")
                    .font(font)
                    .foregroundStyle(colors.dim)
                    .frame(minWidth: 18, alignment: .trailing)
                inline(item)
                    .font(font)
                    .foregroundStyle(colors.text)
            }
        case .quote(let body):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(colors.accent)
                    .frame(width: 2)
                inline(body)
                    .font(font)
                    .foregroundStyle(colors.muted)
            }
        case .rule:
            Rectangle()
                .fill(colors.line)
                .frame(height: 1)
                .padding(.vertical, 4)
        case .paragraph(let body):
            inline(body)
                .font(font)
                .foregroundStyle(colors.text)
                .lineSpacing(4)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .system(size: 22, weight: .semibold)
        case 2: .system(size: 18, weight: .semibold)
        default: .system(size: 16, weight: .semibold)
        }
    }

    private func inline(_ markdown: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        let attributed = (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
        return Text(attributed)
    }
}
