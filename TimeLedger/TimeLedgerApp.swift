import SwiftUI

@main
struct TimeLedgerApp: App {
    @StateObject private var ledger = LedgerStore()
    var body: some Scene {
        WindowGroup {
            TabView {
                RecordView().tabItem { Label("记录", systemImage: "bubble.left.and.text.bubble.right") }
                HistoryView().tabItem { Label("总表", systemImage: "tablecells") }
                StatisticsView().tabItem { Label("统计", systemImage: "chart.xyaxis.line") }
                CalendarView().tabItem { Label("待办", systemImage: "calendar") }
            }
            .tint(.teal)
            .environmentObject(ledger)
            .alert("操作未完成", isPresented: Binding(
                get: { ledger.errorMessage != nil },
                set: { if !$0 { ledger.errorMessage = nil } }
            )) { Button("知道了", role: .cancel) {} }
            message: { Text(ledger.errorMessage ?? "") }
        }
    }
}
