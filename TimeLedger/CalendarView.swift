import SwiftUI
import EventKit
import Combine

@MainActor
final class CalendarStore: ObservableObject {
    private let store = EKEventStore()
    @Published var events: [EKEvent] = []
    @Published var calendars: [EKCalendar] = []
    @Published var authorized = false
    @Published var error: String?
    @Published var busy = false

    func connect() async {
        busy = true
        defer { busy = false }
        do {
            authorized = try await store.requestFullAccessToEvents()
            if authorized { refresh() }
            else { error = "未获得日历权限。请到系统设置中允许时间账本访问日历。" }
        } catch { self.error = error.localizedDescription }
    }

    func refresh() {
        authorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        guard authorized else { events = []; calendars = []; return }
        calendars = store.calendars(for: .event).filter(\.allowsContentModifications)
        let now = Date.now
        let end = Calendar.current.date(byAdding: .day, value: 30, to: now)!
        events = store.events(matching: store.predicateForEvents(withStart: now, end: end, calendars: nil))
            .sorted { $0.startDate < $1.startDate }
    }

    var defaultCalendarID: String? {
        store.defaultCalendarForNewEvents?.calendarIdentifier ?? calendars.first?.calendarIdentifier
    }

    func add(title: String, start: Date, end: Date, notes: String, calendarID: String, reminder: Int) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LedgerError.emptyTitle }
        guard start < end else { throw LedgerError.invalidRange }
        guard let calendar = store.calendar(withIdentifier: calendarID), calendar.allowsContentModifications else {
            throw CalendarFailure.noWritableCalendar
        }
        let event = EKEvent(eventStore: store)
        event.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.startDate = start
        event.endDate = end
        event.notes = notes
        event.calendar = calendar
        if reminder >= 0 { event.addAlarm(EKAlarm(relativeOffset: -Double(reminder) * 60)) }
        try store.save(event, span: .thisEvent, commit: true)
        refresh()
    }
}

enum CalendarFailure: LocalizedError {
    case noWritableCalendar
    var errorDescription: String? { "没有可写入的日历，请先在系统日历中创建或启用一个日历。" }
}

struct CalendarView: View {
    @StateObject private var calendar = CalendarStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("把未来的时间提前安排好").font(.title2.bold())
                    Text("待办保存为系统日历事件；是否跨设备同步取决于你选择的日历账户。日历安排不会自动计入已花费时间。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if !calendar.authorized {
                        Button("连接系统日历") { Task { await calendar.connect() } }
                            .disabled(calendar.busy)
                        Link("打开系统设置", destination: URL(string: UIApplication.openSettingsURLString)!)
                    } else {
                        Button("新建待办安排", systemImage: "plus") { showNew = true }
                            .disabled(calendar.calendars.isEmpty)
                        if calendar.calendars.isEmpty {
                            Text("请先在系统日历中添加可写入的日历。").foregroundStyle(.secondary)
                        }
                    }
                }
                if calendar.authorized {
                    Section("未来 30 天 · 所有系统日历") {
                        if calendar.events.isEmpty { Text("暂无安排").foregroundStyle(.secondary) }
                        ForEach(Array(calendar.events.enumerated()), id: \.offset) { _, event in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(event.title ?? "未命名安排").font(.headline)
                                if event.isAllDay {
                                    Text(event.startDate.formatted(date: .abbreviated, time: .omitted) + " · 全天")
                                } else {
                                    Text(event.startDate.formatted(date: .abbreviated, time: .shortened) + " — " + event.endDate.formatted(date: .abbreviated, time: .shortened))
                                }
                                Text(event.calendar.title).font(.caption).foregroundStyle(.secondary)
                            }.font(.subheadline).padding(.vertical, 3)
                        }
                    }
                }
            }
            .navigationTitle("日历待办")
            .toolbar { if calendar.authorized { Button("刷新") { calendar.refresh() } } }
            .refreshable { calendar.refresh() }
            .onAppear { calendar.refresh() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { calendar.refresh() } }
            .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in calendar.refresh() }
            .sheet(isPresented: $showNew) { NewEventView(calendar: calendar) }
            .alert("日历连接失败", isPresented: Binding(get: { calendar.error != nil }, set: { if !$0 { calendar.error = nil } })) {
                Button("知道了", role: .cancel) {}
            } message: { Text(calendar.error ?? "") }
        }
    }
}

struct NewEventView: View {
    @ObservedObject var calendar: CalendarStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var start = Date.now.addingTimeInterval(3600)
    @State private var end = Date.now.addingTimeInterval(7200)
    @State private var notes = ""
    @State private var calendarID = ""
    @State private var reminder = 10
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("待办事项", text: $title)
                DatePicker("开始", selection: $start)
                DatePicker("结束", selection: $end)
                Picker("写入日历", selection: $calendarID) {
                    ForEach(calendar.calendars, id: \.calendarIdentifier) { item in
                        Text(item.title).tag(item.calendarIdentifier)
                    }
                }
                Picker("提醒", selection: $reminder) {
                    Text("不提醒").tag(-1)
                    Text("开始时").tag(0)
                    Text("提前 10 分钟").tag(10)
                    Text("提前 30 分钟").tag(30)
                    Text("提前 1 小时").tag(60)
                }
                TextField("备注", text: $notes, axis: .vertical)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("新建待办")
            .onAppear { calendarID = calendar.defaultCalendarID ?? "" }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存到日历") {
                        do {
                            try calendar.add(title: title, start: start, end: end, notes: notes, calendarID: calendarID, reminder: reminder)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(calendarID.isEmpty)
                }
            }
        }
    }
}
