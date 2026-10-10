import Foundation

public struct ScheduledTaskRecord: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var prompt: String
    public var scheduleText: String
    public var nextRun: Date

    public init(id: String, name: String, prompt: String, scheduleText: String, nextRun: Date) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.scheduleText = scheduleText
        self.nextRun = nextRun
    }
}

public enum ScheduleError: Error, Equatable {
    case emptyField
    case unrecognizedSchedule
}

/// Turns the handoff's schedule sentences into the next fire time.
public enum ScheduleClock {
    public static func nextRun(
        scheduleText: String,
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        let text = scheduleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let clock = clockTime(in: text) else { return nil }
        let weekday = weekday(in: text)
        let weekdaysOnly = text.range(of: "weekday", options: .caseInsensitive) != nil && weekday == nil

        var cursor = calendar.startOfDay(for: now)
        for _ in 0..<14 {
            var parts = calendar.dateComponents([.year, .month, .day], from: cursor)
            parts.hour = clock.hour
            parts.minute = clock.minute
            parts.second = 0
            guard let candidate = calendar.date(from: parts) else { return nil }
            let day = calendar.component(.weekday, from: candidate)
            let matchesWeekday = weekday == nil || day == weekday
            let matchesWeekdays = !weekdaysOnly || (day >= 2 && day <= 6)
            if candidate > now, matchesWeekday, matchesWeekdays {
                return candidate
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { return nil }
            cursor = next
        }
        return nil
    }

    private static func clockTime(in text: String) -> (hour: Int, minute: Int)? {
        guard let match = text.range(of: #"(\d{1,2}):(\d{2})\s*([AaPp][Mm])"#, options: .regularExpression) else {
            return nil
        }
        let raw = String(text[match])
        let pieces = raw.split { !$0.isNumber && $0 != ":" }
        let hm = pieces.first?.split(separator: ":") ?? []
        guard hm.count == 2, var hour = Int(hm[0]), let minute = Int(hm[1]), (0...59).contains(minute) else {
            return nil
        }
        let isPM = raw.uppercased().contains("PM")
        if hour == 12 { hour = 0 }
        if isPM { hour += 12 }
        guard (0...23).contains(hour) else { return nil }
        return (hour, minute)
    }

    private static func weekday(in text: String) -> Int? {
        let lowered = text.lowercased()
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        guard let index = names.firstIndex(where: { lowered.contains($0) }) else { return nil }
        return index + 1
    }
}
