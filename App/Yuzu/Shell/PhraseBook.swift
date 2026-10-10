import Foundation

/// What a rotating line is for. Each list walks in order, one step per visit to that screen.
enum PhraseCategory: Hashable {
    /// Code home title, beside the small cat, above the usage card. The desk, not a hello.
    case codeGreeting
    /// Placeholder in the Code composer. An invitation to name the work.
    case codePrompt
    /// Dim line under the heatmap. Says how many tokens were spent, with a changing yardstick.
    case usageNote
    /// Huge Cowork headline beside the cat. A welcome, not a name tag.
    case coworkGreeting
    /// Placeholder in the Cowork composer, above the idea chips. A general task, not a code task.
    case coworkPrompt
    /// Placeholder at the bottom of a thread. A continuation, not an introduction.
    case threadPrompt
}

enum PhraseBook {
    static func line(_ category: PhraseCategory, index: Int, tokens: Int = 0) -> String {
        let lines = lines(category, tokens: tokens)
        let count = lines.count
        let slot = ((index % count) + count) % count
        return lines[slot]
    }

    private static func lines(_ category: PhraseCategory, tokens: Int) -> [String] {
        switch category {
        case .codeGreeting:
            return [
                "The folder is listening.",
                "What are we changing?",
                "A quiet repo is suspicious.",
                "Start with the annoying bit.",
                "The diff can wait for a sentence.",
                "Local files. Local model. Go.",
            ]
        case .codePrompt:
            return [
                "Describe the change",
                "Paste the error, if you have one",
                "What should this do instead?",
                "Name the file, or just the bug",
                "A refactor, a question, a hunch",
            ]
        case .usageNote:
            return usageLines(tokens: tokens)
        case .coworkGreeting:
            return [
                "\(AccountName.timeOfDayGreeting).",
                "The cat is in.",
                "Blank page. Lucky you.",
                "Back so soon.",
                "One thing. Then the rest.",
                "The lid is open.",
            ]
        case .coworkPrompt:
            return [
                "What needs doing?",
                "A chore, a question, a strange idea",
                "Hand over the boring part",
                "Or steal an idea from below",
                "Say it like a note to yourself",
            ]
        case .threadPrompt:
            return [
                "Write a message…",
                "And then?",
                "What did it miss?",
                "Correct it, or keep going",
                "The next instruction",
            ]
        }
    }

    /// The number is the point. Gatsby is one yardstick among others.
    private static func usageLines(tokens: Int) -> [String] {
        let n = tokens.formatted(.number.grouping(.automatic))
        let pages = max(1, Int((Double(tokens) / 500.0).rounded()))
        let pageWord = pages == 1 ? "page" : "pages"
        let texts = max(1, tokens / 30)
        let textWord = texts == 1 ? "text" : "texts"
        return [
            "\(n) tokens so far. The Great Gatsby is about 62,000.",
            "\(n) tokens. About \(pages) \(pageWord) of prose.",
            "\(n) tokens. A text message is ~30, so this is about \(texts) \(textWord).",
            "\(n) tokens, tallied on this Mac.",
            "\(n) tokens. A sonnet is about 140, for scale.",
        ]
    }
}

/// Hands out the next line in a category when a screen is opened. Does not tick on a timer.
@MainActor
enum PhraseVisits {
    private static var nextIndex: [PhraseCategory: Int] = [:]

    static func claim(_ category: PhraseCategory) -> Int {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return 0
        }
        let current = nextIndex[category] ?? 0
        nextIndex[category] = current + 1
        return current
    }
}
