import Foundation

struct TimeEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var start: Date
    var end: Date
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

enum LedgerError: LocalizedError {
    case emptyTitle, invalidRange, futureRange
    var errorDescription: String? {
        switch self {
        case .emptyTitle: return "请填写刚刚做了什么。"
        case .invalidRange: return "结束时间必须晚于开始时间。"
        case .futureRange: return "时间记录不能在未来；未来安排请使用待办。"
        }
    }
}

enum Timeline {
    static func validate(_ entry: TimeEntry, now: Date = .now) throws {
        guard !entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LedgerError.emptyTitle
        }
        guard entry.start < entry.end else { throw LedgerError.invalidRange }
        guard entry.end <= now else { throw LedgerError.futureRange }
    }

    static func overlaps(_ entry: TimeEntry, in entries: [TimeEntry]) -> Bool {
        entries.contains { $0.start < entry.end && $0.end > entry.start }
    }

    // Intervals are half-open: [start, end). Replace only the overlapping portion.
    static func inserting(_ entry: TimeEntry, into entries: [TimeEntry]) -> [TimeEntry] {
        var result: [TimeEntry] = []
        for old in entries {
            if old.end <= entry.start || old.start >= entry.end {
                result.append(old)
                continue
            }
            if old.start < entry.start {
                result.append(TimeEntry(title: old.title, start: old.start, end: entry.start))
            }
            if old.end > entry.end {
                result.append(TimeEntry(title: old.title, start: entry.end, end: old.end))
            }
        }
        result.append(entry)
        return result.sorted { $0.start < $1.start }
    }

    static func clipped(_ entries: [TimeEntry], from start: Date, to end: Date) -> [TimeEntry] {
        entries.compactMap { entry in
            let a = max(entry.start, start)
            let b = min(entry.end, end)
            guard a < b else { return nil }
            return TimeEntry(id: entry.id, title: entry.title, start: a, end: b)
        }.sorted { $0.start < $1.start }
    }

    static func matching(_ title: String, keyword: String) -> Bool {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || title.localizedStandardContains(query)
    }

    static func dailyTotals(_ entries: [TimeEntry], keyword: String, days: Int,
                            now: Date = .now, calendar: Calendar = .current) -> [DayTotal] {
        guard days > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        let matches = entries.filter { matching($0.title, keyword: keyword) }
        return (0..<days).map { offset in
            let start = calendar.date(byAdding: .day, value: offset - days + 1, to: today)!
            let end = min(calendar.date(byAdding: .day, value: 1, to: start)!, now)
            let seconds = clipped(matches, from: start, to: end).reduce(0) { $0 + $1.duration }
            return DayTotal(day: start, seconds: seconds)
        }
    }

    static func csv(_ entries: [TimeEntry]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        func escaped(_ value: String) -> String {
            // Prevent spreadsheet applications interpreting activity names as formulas.
            let leading = value.trimmingCharacters(in: .whitespacesAndNewlines).first
            let safe = leading.map { "=+-@".contains($0) } == true ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let rows = entries.sorted { $0.start < $1.start }.map {
            [escaped($0.title), formatter.string(from: $0.start), formatter.string(from: $0.end),
             String(format: "%.2f", $0.duration / 60)].joined(separator: ",")
        }
        return "\u{FEFF}事项,开始时间,结束时间,分钟\r\n" + rows.joined(separator: "\r\n")
    }
}

struct DayTotal: Identifiable {
    var day: Date
    var seconds: TimeInterval
    var id: Date { day }
    var hours: Double { seconds / 3600 }
}

func durationText(_ seconds: TimeInterval) -> String {
    if seconds <= 0 { return "0 分钟" }
    let minutes = Int(seconds / 60)
    if minutes == 0 { return "不足 1 分钟" }
    return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分" : "\(minutes) 分钟"
}
