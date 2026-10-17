import SwiftUI

struct RecordView: View {
    @EnvironmentObject private var ledger: LedgerStore
    @State private var message = ""
    @State private var customStart: Date?
    @State private var showManual = false
    @State private var pending: TimeEntry?
    @State private var showConflict = false
    @FocusState private var typing: Bool

    private var start: Date {
        customStart ?? ledger.entries.map(\.end).max() ?? Calendar.current.startOfDay(for: .now)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("完成一件事，就发一句消息")
                        .font(.title2.bold())
                    Text("从下面的开始时间记到发送时刻。漏记时可补记任意过去的时间段。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    DatePicker("本次开始", selection: Binding(get: { start }, set: { customStart = $0 }), in: ...Date.now)
                    if ledger.entries.isEmpty {
                        Text("第一条默认从今天 00:00 开始，请按实际情况调整。")
                            .font(.caption).foregroundStyle(.orange)
                    } else if customStart != nil {
                        Button("恢复为上一条结束时间") { customStart = nil }
                    }
                    TextField("例如：阅读、写代码、午饭", text: $message, axis: .vertical)
                        .lineLimit(2...4).focused($typing)
                    Button(action: send) {
                        Label("完成并记录到现在", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent)
                        .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let today = Calendar.current.startOfDay(for: context.date)
                    let rows = Timeline.clipped(ledger.entries, from: today, to: context.date)
                    Section("今天 · 已记录 \(durationText(rows.reduce(0) { $0 + $1.duration }))") {
                        EntryTable(entries: rows, windowStart: today, windowEnd: context.date)
                    }
                }
            }
            .navigationTitle("时间账本")
            .toolbar { Button("补记", systemImage: "plus") { showManual = true } }
            .sheet(isPresented: $showManual) { ManualEntryView() }
            .confirmationDialog("这段时间已有记录，是否覆盖重叠部分？", isPresented: $showConflict, titleVisibility: .visible) {
                Button("覆盖重叠部分", role: .destructive) { commit() }
                Button("取消", role: .cancel) { pending = nil }
            } message: { Text("原记录未重叠的部分会保留，统计不会重复计时。") }
        }
    }

    private func send() {
        let entry = TimeEntry(title: message.trimmingCharacters(in: .whitespacesAndNewlines), start: start, end: .now)
        do { try Timeline.validate(entry) }
        catch { ledger.errorMessage = error.localizedDescription; return }
        pending = entry
        if Timeline.overlaps(entry, in: ledger.entries) { showConflict = true }
        else { commit() }
    }

    private func commit() {
        guard let pending else { return }
        if ledger.add(pending) {
            message = ""
            customStart = nil
            typing = false
        }
        self.pending = nil
    }
}

struct ManualEntryView: View {
    @EnvironmentObject private var ledger: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var start = Date.now.addingTimeInterval(-3600)
    @State private var end = Date.now
    @State private var pending: TimeEntry?
    @State private var showConflict = false
    @State private var validationError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("补记或修正") {
                    TextField("做了什么", text: $title)
                    DatePicker("开始", selection: $start, in: ...Date.now)
                    DatePicker("结束", selection: $end, in: ...Date.now)
                    Text("支持跨天。修正已有记录时，填写要替换的时间段和事项即可。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let validationError { Text(validationError).foregroundStyle(.red) }
                }
            }
            .navigationTitle("手动补记")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { prepare() } }
            }
            .confirmationDialog("覆盖已有记录的重叠部分？", isPresented: $showConflict, titleVisibility: .visible) {
                Button("覆盖并保存", role: .destructive) { save() }
                Button("取消", role: .cancel) { pending = nil }
            }
        }
    }

    private func prepare() {
        let entry = TimeEntry(title: title.trimmingCharacters(in: .whitespacesAndNewlines), start: start, end: end)
        do {
            try Timeline.validate(entry)
            validationError = nil
            pending = entry
            if Timeline.overlaps(entry, in: ledger.entries) { showConflict = true }
            else { save() }
        } catch { validationError = error.localizedDescription }
    }

    private func save() {
        guard let pending else { return }
        if ledger.add(pending) { dismiss() }
        else { validationError = ledger.errorMessage }
    }
}

struct EntryTable: View {
    var entries: [TimeEntry]
    var windowStart: Date?
    var windowEnd: Date?

    private var gaps: [TimeEntry] {
        guard let windowStart, let windowEnd, windowStart < windowEnd else { return [] }
        var cursor = windowStart
        var result: [TimeEntry] = []
        for entry in entries.sorted(by: { $0.start < $1.start }) {
            if entry.start > cursor {
                result.append(TimeEntry(title: "未记录", start: cursor, end: entry.start))
            }
            cursor = max(cursor, entry.end)
        }
        if cursor < windowEnd { result.append(TimeEntry(title: "未记录", start: cursor, end: windowEnd)) }
        return result
    }

    var body: some View {
        let unrecorded = gaps
        let rows = (entries + unrecorded).sorted { $0.start < $1.start }
        if rows.isEmpty {
            Text("还没有记录").foregroundStyle(.secondary)
        } else {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    Text("时间段")
                    Text("事项").frame(maxWidth: .infinity, alignment: .leading)
                    Text("时长")
                }.font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(rows) { row in
                    GridRow(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.start, format: .dateTime.hour().minute())
                            Text(row.end, format: .dateTime.hour().minute())
                        }.monospacedDigit()
                        Text(row.title).frame(maxWidth: .infinity, alignment: .leading)
                        Text(durationText(row.duration)).font(.caption)
                    }
                    .foregroundStyle(unrecorded.contains(where: { $0.id == row.id }) ? Color.secondary : Color.primary)
                }
            }.font(.subheadline).padding(.vertical, 6)
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var ledger: LedgerStore
    @State private var keyword = ""
    @State private var selectedDay = Date.now
    @State private var allDays = true
    @State private var showManual = false
    @State private var exportURL: URL?
    @State private var deletion: TimeEntry?

    private var filtered: [TimeEntry] {
        let matches = ledger.entries.filter { Timeline.matching($0.title, keyword: keyword) }
        if allDays { return matches.sorted { $0.start > $1.start } }
        let start = Calendar.current.startOfDay(for: selectedDay)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return Array(Timeline.clipped(matches, from: start, to: end).reversed())
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("显示全部日期", isOn: $allDays)
                    if !allDays { DatePicker("日期", selection: $selectedDay, displayedComponents: .date) }
                    Text("\(filtered.count) 条 · \(durationText(filtered.reduce(0) { $0 + $1.duration }))")
                        .font(.headline)
                }
                Section("事项 / 时间段 / 时长") {
                    if filtered.isEmpty { Text("没有匹配记录").foregroundStyle(.secondary) }
                    ForEach(filtered) { entry in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.title).font(.headline)
                                Text(entry.start.formatted(date: .abbreviated, time: .shortened) + " — " + entry.end.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Text(durationText(entry.duration)).font(.caption).monospacedDigit()
                        }
                        .swipeActions {
                            Button("删除整条", role: .destructive) { deletion = entry }
                        }
                    }
                }
                Section("备份") {
                    Button("生成全部记录 CSV") { exportURL = ledger.exportCSV() }
                    if let exportURL { ShareLink("分享 CSV 表格", item: exportURL) }
                    Text("CSV 包含全部原始记录，可在 Excel 或 Numbers 中打开。每次分享前可重新生成。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .searchable(text: $keyword, prompt: "搜索事项关键词")
            .navigationTitle("时间总表")
            .toolbar { Button("补记") { showManual = true } }
            .sheet(isPresented: $showManual) { ManualEntryView() }
            .confirmationDialog("删除整条原始记录？跨天记录的其他日期也会删除。", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    if let deletion { ledger.delete(deletion) }
                    deletion = nil
                }
                Button("取消", role: .cancel) { deletion = nil }
            }
        }
    }
}
