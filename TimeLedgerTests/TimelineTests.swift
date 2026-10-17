import XCTest
@testable import TimeLedger

final class TimelineTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func time(_ seconds: Double) -> Date { base.addingTimeInterval(seconds) }
    private func entry(_ title: String, _ start: Double, _ end: Double) -> TimeEntry {
        TimeEntry(title: title, start: time(start), end: time(end))
    }

    func testManualInsertionSplitsOldRecordWithoutDoubleCounting() {
        let result = Timeline.inserting(entry("午饭", 30, 60), into: [entry("工作", 0, 100)])
        XCTAssertEqual(result.map(\.title), ["工作", "午饭", "工作"])
        XCTAssertEqual(result.map(\.duration), [30, 30, 40])
        XCTAssertEqual(result.reduce(0) { $0 + $1.duration }, 100)
    }

    func testReplacementSpansSeveralRecordsAndGap() {
        let result = Timeline.inserting(entry("阅读", 20, 90), into: [entry("工作", 0, 30), entry("午饭", 50, 100)])
        XCTAssertEqual(result.map(\.duration), [20, 70, 10])
        XCTAssertEqual(result.map(\.title), ["工作", "阅读", "午饭"])
    }

    func testAdjacentRecordsDoNotConflict() {
        XCTAssertFalse(Timeline.overlaps(entry("阅读", 30, 60), in: [entry("工作", 0, 30)]))
    }

    func testCompleteReplacementAndZeroDurationLabel() {
        let result = Timeline.inserting(entry("修正", 0, 100), into: [entry("旧记录", 20, 50)])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.duration, 100)
        XCTAssertEqual(durationText(0), "0 分钟")
    }

    func testBackfillDoesNotMoveLatestEndBackwards() {
        let result = Timeline.inserting(entry("补记", 0, 20), into: [entry("工作", 100, 200)])
        XCTAssertEqual(result.map(\.end).max(), time(200))
    }

    func testCrossMidnightAndZeroDaysInAverage() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let today = calendar.startOfDay(for: base)
        let record = TimeEntry(title: "阅读 Swift", start: today.addingTimeInterval(-3600), end: today.addingTimeInterval(7200))
        let totals = Timeline.dailyTotals([record], keyword: "阅读", days: 3, now: today.addingTimeInterval(10800), calendar: calendar)
        XCTAssertEqual(totals.map(\.seconds), [0, 3600, 7200])
        XCTAssertEqual(totals.reduce(0) { $0 + $1.seconds } / 3, 3600)
    }

    func testDSTUsesCalendarDayRatherThan24Hours() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let record = TimeEntry(title: "旅行", start: start, end: end)
        let totals = Timeline.dailyTotals([record], keyword: "旅行", days: 2, now: end.addingTimeInterval(3600), calendar: calendar)
        XCTAssertEqual(totals.map(\.seconds), [23 * 3600, 0])
    }

    func testInvalidInputRejected() {
        XCTAssertThrowsError(try Timeline.validate(entry(" ", 0, 10), now: time(100)))
        XCTAssertThrowsError(try Timeline.validate(entry("工作", 10, 0), now: time(100)))
        XCTAssertThrowsError(try Timeline.validate(entry("工作", 0, 200), now: time(100)))
    }

    func testKeywordAndCSV() {
        XCTAssertTrue(Timeline.matching("Study Swift", keyword: " swift "))
        XCTAssertFalse(Timeline.matching("午饭", keyword: "阅读"))
        let csv = Timeline.csv([entry("=SUM(1,2)\"\n", 0, 60)])
        XCTAssertTrue(csv.contains("\"'=SUM(1,2)\"\"\n\""))
        XCTAssertTrue(csv.contains("1.00"))
    }
}
