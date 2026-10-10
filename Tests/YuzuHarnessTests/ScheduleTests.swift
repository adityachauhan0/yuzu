import Foundation
import Testing
import YuzuHarness

struct ScheduleTests {
    @Test func nextWeekdayMorningSkipsTheWeekend() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let saturday = date(2026, 10, 10, 12, 0, calendar)
        let next = ScheduleClock.nextRun(scheduleText: "Weekdays at 8:00 AM", now: saturday, calendar: calendar)
        #expect(next == date(2026, 10, 12, 8, 0, calendar))
    }

    @Test func dailyTimeLaterTodayStaysToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = date(2026, 10, 10, 7, 0, calendar)
        let next = ScheduleClock.nextRun(scheduleText: "Daily at 9:00 AM", now: morning, calendar: calendar)
        #expect(next == date(2026, 10, 10, 9, 0, calendar))
    }

    @Test func namedWeekdayAdvances() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let saturday = date(2026, 10, 10, 12, 0, calendar)
        let next = ScheduleClock.nextRun(scheduleText: "Every Friday at 4:00 PM", now: saturday, calendar: calendar)
        #expect(next == date(2026, 10, 16, 16, 0, calendar))
    }

    @Test func unrecognizedScheduleIsNil() {
        #expect(ScheduleClock.nextRun(scheduleText: "whenever", now: Date()) == nil)
    }

    @Test func storeRoundTripsASchedule() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("yuzu-schedule-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try HarnessStore(path: root.appendingPathComponent("session.sqlite").path)
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        let task = ScheduledTaskRecord(
            id: "briefing",
            name: "Daily briefing",
            prompt: "What needs attention today?",
            scheduleText: "Weekdays at 8:00 AM",
            nextRun: when
        )
        try store.insertScheduledTask(task)
        let loaded = try store.scheduledTasks()
        #expect(loaded == [task])
        let later = when.addingTimeInterval(86_400)
        try store.updateScheduledTaskNextRun(id: "briefing", nextRun: later)
        #expect(try store.scheduledTasks().first?.nextRun == later)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
