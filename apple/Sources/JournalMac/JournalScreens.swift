import SwiftUI
import Charts
import JournalCore

struct ScreenHeading: View {
    let title: String
    let subtitle: String
    var body: some View { VStack(alignment: .leading, spacing: 7) { Text(title).font(.system(size: 30, weight: .semibold)); Text(subtitle).font(.callout).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }
}
struct Paper<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary)) }
}
struct MetricTile: View {
    let title: String
    let value: String
    var body: some View { VStack(alignment: .leading, spacing: 5) { Text(value).font(.title2.weight(.semibold)).monospacedDigit(); Text(title).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }
}
struct StatsStrip: View {
    let entries: [Entry]
    var metrics: [Metric] = Metric.allCases
    var body: some View {
        let summary = Summary(entries)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), alignment: .leading)], alignment: .leading, spacing: 16) {
            MetricTile(title: "活动次数", value: "\(summary.count)")
            MetricTile(title: "活跃天数", value: "\(summary.days)")
            ForEach(metrics, id: \.self) { metric in MetricTile(title: "\(metric.title) / \(metric.unit)", value: numberLabel(summary.sums[metric])) }
        }
    }
}
struct EntryRows: View {
    @ObservedObject var store: JournalStore
    let entries: [Entry]
    var body: some View {
        if entries.isEmpty {
            Text("这段时间还没有记录。").foregroundStyle(.secondary).padding(.vertical, 18).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(ordered(entries)) { entry in
                    Button { store.selectedEntry = entry.id } label: {
                        HStack(alignment: .top, spacing: 12) {
                            let activity = store.snapshot.activities.first { $0.id == entry.activityID }
                            Text(activity?.icon ?? "✎").font(.title2).frame(width: 35, height: 38)
                                .background(Color(hex: activity?.color ?? "#3D8060").opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                                HStack(spacing: 8) {
                                    Text(activity?.name ?? "日记")
                                    Text(JournalDate.time(entry.startedAt))
                                    ForEach(Metric.allCases, id: \.self) { metric in
                                        if let value = entry.metrics?[metric] { Text("\(numberLabel(value)) \(metric.unit)") }
                                    }
                                }.font(.caption).foregroundStyle(.secondary)
                                if !entry.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(JournalText.excerpt(entry.body)).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                                }
                                if let tags = entry.tags, !tags.isEmpty { Text(tags.map { "#" + $0 }.joined(separator: "  ")).font(.caption).foregroundStyle(Color.journalGreen).lineLimit(1) }
                            }
                            Spacer(minLength: 0)
                            if let repository = store.repository, let reference = entry.cover ?? JournalText.imageReferences(entry.body).first {
                                JournalImage(repository: repository, url: URL(string: reference, relativeTo: JournalMarkdown.imageBase)?.absoluteURL, revision: store.revision)
                                    .frame(width: 64, height: 52).clipped()
                            }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }.padding(12).contentShape(Rectangle())
                            .background(store.selectedEntry == entry.id ? Color.journalGreen.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).contextMenu {
                        Button("编辑记录", systemImage: "pencil") { store.editEntry(entry) }
                        Button("移入回收站…", systemImage: "trash", role: .destructive) { store.deletingEntry = entry }
                    }.disabled(store.busy)
                }
            }
        }
    }
}
struct MonthNavigation: View {
    @Binding var month: String
    var body: some View {
        HStack {
            Button("上个月", systemImage: "chevron.left") { month = JournalDate.shiftMonth(month, by: -1) }.labelStyle(.iconOnly).disabled(month <= "1900-01")
            Text(month.replacingOccurrences(of: "-", with: " / ")).font(.headline).monospacedDigit().frame(minWidth: 100)
            Button("下个月", systemImage: "chevron.right") { month = JournalDate.shiftMonth(month, by: 1) }.labelStyle(.iconOnly).disabled(month >= "9998-12")
        }.buttonStyle(.borderless)
    }
}
struct MonthGrid: View {
    let month: String
    let selected: String?
    let entries: [Entry]
    let activities: [Activity]
    let select: (String) -> Void
    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]
    var body: some View {
        let grouped = Dictionary(grouping: entries, by: \.date)
        VStack(spacing: 4) {
            HStack { ForEach(weekdays, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity) } }.padding(.bottom, 7)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(JournalDate.monthDays(month), id: \.self) { day in
                    let items = grouped[day] ?? []
                    Button { select(day) } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(String(Int(day.suffix(2))!)).font(.system(size: 13, weight: day == JournalDate.today() ? .bold : .regular))
                                Spacer(minLength: 1)
                                if day == JournalDate.today() { Circle().fill(Color.journalGreen).frame(width: 5, height: 5) }
                            }
                            HStack(spacing: 3) {
                                ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { _, item in
                                    let color = activities.first(where: { $0.id == item.activityID })?.color ?? "#7C8C87"
                                    Circle().fill(Color(hex: color)).frame(width: 6, height: 6)
                                }
                                if items.count > 3 { Text("+").font(.system(size: 9)) }
                            }.frame(height: 8)
                        }.padding(9).frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
                            .background(selected == day ? Color.journalGreen.opacity(0.16) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected == day ? Color.journalGreen : .clear, lineWidth: 1))
                            .opacity(day.hasPrefix(month) ? 1 : 0.35)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).help("\(day) · \(items.count) 条记录").accessibilityLabel("\(day)，\(items.count) 条记录")
                }
            }
        }
    }
}
struct CalendarScreen: View {
    @ObservedObject var store: JournalStore
    @State private var month = String(JournalDate.today().prefix(7))
    @State private var day = JournalDate.today()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenHeading(title: "日子，有迹可循。", subtitle: "把时间展开，看看发生了什么。")
                HStack {
                    MonthNavigation(month: $month)
                    Spacer()
                    Button("今天") { day = JournalDate.today(); month = String(day.prefix(7)) }
                }
                Paper {
                    VStack(alignment: .leading, spacing: 18) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], alignment: .leading, spacing: 8) { ForEach(store.snapshot.activities) { activity in Label(activity.name, systemImage: "circle.fill").font(.caption).foregroundStyle(Color(hex: activity.color)) } }
                        MonthGrid(month: month, selected: day, entries: store.snapshot.entries, activities: store.snapshot.activities) { value in day = value; month = String(value.prefix(7)) }
                    }
                }
                Paper { StatsStrip(entries: store.snapshot.entries.filter { $0.date.hasPrefix(month) }) }
                VStack(alignment: .leading, spacing: 12) {
                    Text("这个月的积累").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                        ForEach(store.snapshot.activities) { activity in
                            let summary = Summary(store.snapshot.entries.filter { $0.activityID == activity.id && $0.date.hasPrefix(month) })
                            let metric = activity.metrics.contains(.distance) ? Metric.distance : activity.metrics.first
                            Button {
                                store.activityFocusMonth = month
                                store.activityFocusDay = nil
                                store.selection = "activity:" + activity.id
                            } label: {
                                Paper {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(activity.icon + " " + activity.name).font(.subheadline)
                                        Text("\(summary.count) 次").font(.title2.bold())
                                        Text("\(summary.days) 天" + (metric.map { " · \(numberLabel(summary.sums[$0])) \($0.unit)" } ?? "")).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Paper {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { Text(day).font(.title3.bold()); Spacer(); Button("为这天添加记录", systemImage: "plus") { store.newEntry(date: day) }.disabled(day > JournalDate.today()) }
                        EntryRows(store: store, entries: store.snapshot.entries.filter { $0.date == day })
                    }
                }
            }.padding(26)
        }.background(Color.primary.opacity(0.025))
            .onChange(of: month) { _, value in if !day.hasPrefix(value) { day = value + "-01" } }
            .onAppear { store.contextDate = day }
            .onChange(of: day) { _, value in store.contextDate = value }
    }
}
struct TimelineScreen: View {
    @ObservedObject var store: JournalStore
    @State private var end = JournalDate.today()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenHeading(title: "七日时间轴", subtitle: "记录发生的事，也记录当时的自己。")
                HStack {
                    Button("前七天", systemImage: "chevron.left") { end = JournalDate.shift(end, days: -7) }
                    Spacer(); Text("\(JournalDate.shift(end, days: -6)) — \(end)").font(.callout).monospacedDigit(); Spacer()
                    Button("后七天", systemImage: "chevron.right") { end = JournalDate.shift(end, days: 7) }
                    Button("今天") { end = JournalDate.today() }
                }
                ForEach((0..<7).map { JournalDate.shift(end, days: -$0) }, id: \.self) { day in
                    Paper {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack { Text(day).font(.headline); Spacer(); Button("添加", systemImage: "plus") { store.newEntry(date: day) }.disabled(day > JournalDate.today()) }
                            EntryRows(store: store, entries: store.snapshot.entries.filter { $0.date == day })
                        }
                    }
                }
            }.padding(26)
        }.background(Color.primary.opacity(0.025))
            .onAppear { store.contextDate = min(end, JournalDate.today()) }
            .onChange(of: end) { _, value in store.contextDate = min(value, JournalDate.today()) }
    }
}
struct YearNavigation: View {
    @Binding var year: Int
    var body: some View {
        HStack {
            Button("上一年", systemImage: "chevron.left") { year -= 1 }.labelStyle(.iconOnly).disabled(year <= 1900)
            Text("\(String(year)) 年").font(.headline).monospacedDigit()
            Button("下一年", systemImage: "chevron.right") { year += 1 }.labelStyle(.iconOnly).disabled(year >= 9998)
        }.buttonStyle(.borderless)
    }
}
struct ActivityHeatmap: View {
    let year: Int
    let entries: [Entry]
    let color: Color
    var select: ((String) -> Void)? = nil
    var body: some View {
        let days = JournalDate.yearDays(year)
        let counts = Dictionary(grouping: entries.filter { $0.kind == "event" }, by: \.date).mapValues(\.count)
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal) {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(11), spacing: 3), count: 7), spacing: 3) {
                    ForEach(days.indices, id: \.self) { index in
                        if let day = days[index] {
                            let count = counts[day] ?? 0
                            Button { select?(day) } label: {
                                RoundedRectangle(cornerRadius: 2).fill(count == 0 ? Color.primary.opacity(0.07) : color.opacity(Double(min(count, 4)) / 4)).frame(width: 11, height: 11)
                            }.buttonStyle(.plain).help("\(day)：\(count) 次").accessibilityLabel("\(day)，\(count) 次")
                        } else { Color.clear.frame(width: 11, height: 11) }
                    }
                }.padding(.vertical, 2)
            }
            HStack(spacing: 5) {
                Text("未记录")
                ForEach(0..<5) { count in RoundedRectangle(cornerRadius: 2).fill(count == 0 ? Color.primary.opacity(0.07) : color.opacity(Double(count) / 4)).frame(width: 10, height: 10) }
                Text("4+ 次"); Spacer(); Text("每列一周 · 周一开始")
            }.font(.caption2).foregroundStyle(.secondary)
        }
    }
}
struct ActivitiesScreen: View {
    @ObservedObject var store: JournalStore
    @State private var year = Int(JournalDate.today().prefix(4))!
    @State private var showArchived = false
    private var activities: [Activity] { showArchived ? store.snapshot.activities : store.snapshot.activeActivities }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenHeading(title: "持续发生的小事", subtitle: "每一行，都是生活里的一份积累。")
                HStack { Text("\(activities.count) 项活动").foregroundStyle(.secondary); Spacer(); Button("新建活动", systemImage: "plus") { store.newActivity() }; YearNavigation(year: $year) }
                if !store.snapshot.archivedActivityIDs.isEmpty { Toggle("显示已归档活动", isOn: $showArchived).font(.callout) }
                if activities.isEmpty {
                    ContentUnavailableView { Label("还没有活动", systemImage: "square.grid.2x2") } description: { Text("创建你想记录的活动，可以选择时长、距离或页数。") } actions: { Button("新建活动") { store.newActivity() } }
                }
                ForEach(activities) { activity in
                    let entries = store.snapshot.entries.filter { $0.activityID == activity.id && $0.date.hasPrefix(String(year)) }
                    Paper {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                Button { openActivity(activity) } label: { Text("\(activity.icon)  \(activity.name)").font(.title3.bold()) }.buttonStyle(.plain)
                                if store.snapshot.archivedActivityIDs.contains(activity.id) { Text("已归档").font(.caption).foregroundStyle(.secondary) }
                                Spacer(); Text("\(Summary(entries).count) 次 · \(Summary(entries).days) 天").foregroundStyle(.secondary)
                                ActivityActions(store: store, activity: activity)
                            }
                            ActivityHeatmap(year: year, entries: entries, color: Color(hex: activity.color)) { value in
                                store.activityFocusMonth = String(value.prefix(7)); store.activityFocusDay = value
                                store.selection = "activity:" + activity.id
                            }
                            Text(entries.map(\.date).max().map { "最近记录 " + $0 } ?? "这一年还没有记录").font(.caption).foregroundStyle(.secondary)
                            Button("查看记录与统计 →") { openActivity(activity) }.buttonStyle(.link)
                        }
                    }
                }
            }.padding(26)
        }.background(Color.primary.opacity(0.025))
    }
    private func openActivity(_ activity: Activity) {
        store.activityFocusMonth = String(format: "%04d", year) + String(JournalDate.today().dropFirst(4).prefix(3))
        store.activityFocusDay = nil
        store.selection = "activity:" + activity.id
    }
}
struct ActivityScreen: View {
    @ObservedObject var store: JournalStore
    let activity: Activity
    @State private var month = String(JournalDate.today().prefix(7))
    @State private var day: String?
    private var year: Int { Int(month.prefix(4))! }
    init(store: JournalStore, activity: Activity) {
        self.store = store; self.activity = activity
        _month = State(initialValue: store.activityFocusMonth)
        _day = State(initialValue: store.activityFocusDay)
    }
    var body: some View {
        let all = store.snapshot.entries.filter { $0.activityID == activity.id }
        let annual = all.filter { $0.date.hasPrefix(String(year)) }
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenHeading(title: "\(activity.icon)  \(activity.name)", subtitle: activity.body.trimmingCharacters(in: .whitespacesAndNewlines))
                HStack {
                    YearNavigation(year: Binding(get: { year }, set: { month = String(format: "%04d", $0) + String(month.suffix(3)); day = nil })); Spacer()
                    if store.snapshot.archivedActivityIDs.contains(activity.id) { Text("已归档 · 历史已保留").font(.caption).foregroundStyle(.secondary) }
                    else { Button(day == nil ? "记录今天的\(activity.name)" : "为所选日期记录", systemImage: "plus") { store.newEntry(date: day ?? JournalDate.today(), activity: activity.id) }.disabled((day ?? JournalDate.today()) > JournalDate.today()) }
                    ActivityActions(store: store, activity: activity)
                }
                Paper {
                    VStack(alignment: .leading, spacing: 22) {
                        StatsStrip(entries: annual, metrics: activity.metrics)
                        ActivityHeatmap(year: year, entries: annual, color: Color(hex: activity.color)) { value in day = value; month = String(value.prefix(7)) }
                    }
                }
                Paper {
                    VStack(alignment: .leading, spacing: 16) {
                        MonthNavigation(month: $month)
                        MonthGrid(month: month, selected: day, entries: all, activities: [activity]) { value in day = value; month = String(value.prefix(7)) }
                        HStack { Text("\(day ?? month) · 记录").font(.headline); Spacer(); if day != nil { Button("查看整月") { day = nil } } }
                        EntryRows(store: store, entries: all.filter { day == nil ? $0.date.hasPrefix(month) : $0.date == day })
                    }
                }
                Paper {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("\(String(year)) 年 · 统计").font(.headline)
                        if activity.metrics.contains(.duration) {
                            Text("平均时长 \(numberLabel(Summary(annual).averageDuration)) min · \(Summary(annual).samples[.duration] ?? 0) 个有效样本").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("每月活动次数").font(.subheadline)
                        Chart(1...12, id: \.self) { m in
                            BarMark(x: .value("月份", "\(m)月"), y: .value("次数", annual.filter { Int($0.date.dropFirst(5).prefix(2)) == m }.count)).foregroundStyle(Color(hex: activity.color))
                        }.frame(height: 150)
                        Text("星期分布").font(.subheadline)
                        Chart(0..<7, id: \.self) { index in
                            BarMark(x: .value("星期", ["一", "二", "三", "四", "五", "六", "日"][index]), y: .value("次数", annual.filter { JournalDate.weekday($0.date) == index }.count)).foregroundStyle(Color(hex: activity.color))
                        }.frame(height: 130)
                    }
                }
            }.padding(26)
        }.background(Color.primary.opacity(0.025))
            .onChange(of: month) { _, value in
                if let selected = day, !selected.hasPrefix(value) { day = nil }
            }
            .onAppear { store.contextDate = day ?? JournalDate.today(); store.activityFocusDay = nil }
            .onChange(of: day) { _, value in store.contextDate = value ?? JournalDate.today() }
    }
}
struct HistoryScreen: View {
    @ObservedObject var store: JournalStore
    let search: Bool
    @State private var filter = EntryFilter()
    @State private var dateRange = false
    @State private var start = JournalDate.shift(JournalDate.today(), days: -30)
    @State private var end = JournalDate.today()
    @FocusState private var searchFocused: Bool
    var body: some View {
        let entries = results
        let groups = Dictionary(grouping: entries, by: \.date)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenHeading(title: search ? "找回一个片段" : "全部记录", subtitle: search ? "搜索标题、正文、标签和活动名称；可以结合筛选。" : "按活动、标签和日期找到你想回顾的记录。")
                if search {
                    HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("试试：跑步、阅读，或某个想法…", text: $store.query).textFieldStyle(.plain).focused($searchFocused) }.padding(12).background(.background, in: RoundedRectangle(cornerRadius: 10))
                }
                HStack {
                    Text("\(entries.count) 条记录").foregroundStyle(.secondary)
                    Spacer()
                    Picker("类型", selection: $filter.kind) { Text("全部").tag("all"); Text("日记").tag("journal"); Text("活动").tag("event") }.pickerStyle(.segmented).frame(width: 200)
                }
                filterControls
                if groups.isEmpty { ContentUnavailableView("没有匹配记录", systemImage: search ? "magnifyingglass" : "book", description: Text("调整筛选条件，或添加一条记录。")) }
                ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                    Paper { VStack(alignment: .leading, spacing: 12) { Text(day).font(.headline); EntryRows(store: store, entries: groups[day]!) } }
                }
            }.padding(26)
        }.background(Color.primary.opacity(0.025))
            .onAppear { if search { searchFocused = true } }
    }
    private var results: [Entry] {
        var value = filter
        value.query = search ? store.query : ""
        if dateRange { value.start = start; value.end = end }
        return store.snapshot.entries.filter { value.matches($0, activities: store.snapshot.activities) }
    }
    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("活动", selection: $filter.activityID) {
                    Text("所有活动与日记").tag(Optional<String>.none)
                    ForEach(store.snapshot.activities) { Text($0.icon + " " + $0.name).tag(Optional($0.id)) }
                }.frame(maxWidth: 250)
                Picker("标签", selection: $filter.tag) {
                    Text("所有标签").tag(Optional<String>.none)
                    ForEach(Array(Set(store.snapshot.entries.flatMap { $0.tags ?? [] })).sorted(), id: \.self) { Text($0).tag(Optional($0)) }
                }.frame(maxWidth: 200)
                Spacer()
                Button("清除筛选") { filter = EntryFilter(); dateRange = false; if search { store.query = "" } }
            }
            HStack {
                Toggle("限制日期", isOn: $dateRange).toggleStyle(.checkbox)
                if dateRange {
                    DatePicker("从", selection: Binding(get: { JournalDate.parse(start)! }, set: { start = JournalDate.today($0) }), in: ...Date(), displayedComponents: .date)
                    DatePicker("到", selection: Binding(get: { JournalDate.parse(end)! }, set: { end = JournalDate.today($0) }), in: ...Date(), displayedComponents: .date)
                }
                Spacer()
            }.environment(\.timeZone, JournalDate.calendar.timeZone).environment(\.calendar, JournalDate.calendar)
            if dateRange && start > end { Text("开始日期不能晚于结束日期").font(.caption).foregroundStyle(.orange) }
        }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 10))
    }
}
