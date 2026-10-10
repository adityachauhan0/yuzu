import AppKit

enum AccountName {
    static var firstName: String {
        let full = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !full.isEmpty else { return "User" }
        let part = full.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        return part.isEmpty ? "User" : part
    }

    static var timeOfDayGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good Morning"
        case 12..<17: return "Good Afternoon"
        default: return "Good Evening"
        }
    }
}
