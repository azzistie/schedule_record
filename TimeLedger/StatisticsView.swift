import SwiftUI
import Charts

struct StatisticsView: View {
    @EnvironmentObject private var ledger: LedgerStore
    @State private var keyword = ""
    @State private var days = 7
    @State private var showBars = true

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let totals = Timeline.dailyTotals(ledger.entries, keyword: keyword, days: days, now: context.date)
                let sum = totals.reduce(0) { $0 + $1.seconds }
                List {
                    Section("统计范围") {
                        TextField("关键词，例如：阅读（留空统计全部）", text: $keyword)
                        Picker("常用范围", selection: $days) {
                            ForEach([7, 14, 30, 90, 365], id: \.self) { Text("\($0) 天").tag($0) }
                            if ![7, 14, 30, 90, 365].contains(days) { Text("\(days) 天").tag(days) }
                        }
                        Stepper("过去 \(days) 天", value: $days, in: 1...3650)
                        Text("包括今天，截至现在；无记录的日期计为 0。关键词按包含关系匹配，跨天记录按每天实际时长分摊。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("统计指标") {
                        LabeledContent("总时长", value: durationText(sum))
                        LabeledContent("日均（除以 \(days) 天）", value: durationText(sum / Double(days)))
                        LabeledContent("单日最多", value: durationText(totals.map(\.seconds).max() ?? 0))
                        LabeledContent("有记录天数", value: "\(totals.filter { $0.seconds > 0 }.count) 天")
                    }
                    Section("每日用时 · 小时") {
                        Picker("图表", selection: $showBars) {
                            Text("柱状图").tag(true)
                            Text("曲线图").tag(false)
                        }.pickerStyle(.segmented)
                        Chart(totals) { item in
                            if showBars {
                                BarMark(x: .value("日期", item.day, unit: .day), y: .value("小时", item.hours))
                                    .foregroundStyle(.teal.gradient)
                            } else {
                                LineMark(x: .value("日期", item.day, unit: .day), y: .value("小时", item.hours))
                                    .foregroundStyle(.teal)
                                PointMark(x: .value("日期", item.day, unit: .day), y: .value("小时", item.hours))
                                    .foregroundStyle(.teal)
                            }
                        }
                        .chartYScale(domain: 0...max(1, (totals.map(\.hours).max() ?? 0) * 1.15))
                        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month().day())
                        } }
                        .frame(height: 250).padding(.vertical)
                    }
                    Section("每日明细") {
                        ForEach(totals.reversed()) { item in
                            LabeledContent(item.day.formatted(date: .abbreviated, time: .omitted), value: durationText(item.seconds))
                        }
                    }
                }
            }
            .navigationTitle("时间统计")
        }
    }
}
