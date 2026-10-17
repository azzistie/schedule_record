import Foundation
import Combine

@MainActor
final class LedgerStore: ObservableObject {
    @Published private(set) var entries: [TimeEntry] = []
    @Published var errorMessage: String?
    private var loadFailed = false
    private let fileURL: URL

    init() {
        fileURL = URL.documentsDirectory.appending(path: "time-ledger.json")
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                entries = try JSONDecoder().decode([TimeEntry].self, from: Data(contentsOf: fileURL))
            }
        } catch {
            loadFailed = true
            errorMessage = "读取记录失败，为保护原始文件，已暂停写入：\(error.localizedDescription)"
        }
    }

    @discardableResult
    func add(_ entry: TimeEntry) -> Bool {
        do {
            try Timeline.validate(entry)
            return persist(Timeline.inserting(entry, into: entries))
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(_ entry: TimeEntry) { _ = persist(entries.filter { $0.id != entry.id }) }

    private func persist(_ updated: [TimeEntry]) -> Bool {
        guard !loadFailed else {
            errorMessage = "记录文件读取失败，不能覆盖。请先通过文件共享备份 time-ledger.json。"
            return false
        }
        do {
            let data = try JSONEncoder().encode(updated)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            entries = updated
            return true
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
            return false
        }
    }

    func exportCSV() -> URL? {
        let url = FileManager.default.temporaryDirectory.appending(path: "时间账本.csv")
        do {
            try Timeline.csv(entries).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
            return nil
        }
    }
}
