import AppKit

enum AccountName {
    static var firstName: String {
        let full = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !full.isEmpty else { return "User" }
        let part = full.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        return part.isEmpty ? "User" : part
    }
}
