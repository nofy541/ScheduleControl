import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Настройка стиля (долгий тап по виджету → «Изменить виджет»)

enum WidgetTheme: String, AppEnum {
    case auto, black, white

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Style"
    static var caseDisplayRepresentations: [WidgetTheme: DisplayRepresentation] = [
        .auto: "Auto",
        .black: "Black",
        .white: "White"
    ]
}

struct StyleIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Style"
    static var description = IntentDescription("Widget look")

    @Parameter(title: "Style", default: .auto)
    var theme: WidgetTheme

    init() {}
}

// MARK: - Интерактивная галочка (iOS 17+)

struct ToggleDoneIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle done"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Key")
    var key: String

    init() {}
    init(key: String) { self.key = key }

    func perform() async throws -> some IntentResult {
        SharedStorage.toggleDone(key)
        return .result()
    }
}

// MARK: - Данные

struct WEntry: TimelineEntry {
    let date: Date
    let events: [ScheduleEvent]
    let state: AppState
    let theme: WidgetTheme
    let hasAccess: Bool

    func upcoming(_ n: Int) -> [Occurrence] {
        Schedule.upcoming(events, now: date, limit: n, skipped: state.skipped)
    }
    var next: Occurrence? { upcoming(1).first }
    var today: [Occurrence] { Schedule.day(date, events: events, skipped: state.skipped) }
    func isDone(_ o: Occurrence) -> Bool { state.done.contains(o.key) }
    var doneToday: Int { today.filter { isDone($0) }.count }

    /// Неделя с первого дня недели по календарю
    var week: [(date: Date, total: Int, done: Int)] {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
        return (0..<7).compactMap { i in
            guard let d = cal.date(byAdding: .day, value: i, to: start) else { return nil }
            let list = Schedule.day(d, events: events, skipped: state.skipped)
            return (date: d, total: list.count, done: list.filter { isDone($0) }.count)
        }
    }

    static func sample(_ theme: WidgetTheme) -> WEntry {
        let now = Date()
        let items: [(String, Double, String, Int)] = [
            (L("Зал", "Gym"), 3600, "dumbbell.fill", 60),
            (L("Созвон", "Call"), 3 * 3600, "phone.fill", 30),
            (L("Ужин", "Dinner"), 5 * 3600, "fork.knife", 0),
            (L("Чтение", "Reading"), 6 * 3600, "book.fill", 0)
        ]
        let events = items.map {
            ScheduleEvent(title: $0.0, date: now.addingTimeInterval($0.1), icon: $0.2, duration: $0.3)
        }
        return WEntry(date: now, events: events, state: AppState(), theme: theme, hasAccess: true)
    }
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WEntry { .sample(.auto) }

    func snapshot(for configuration: StyleIntent, in context: Context) async -> WEntry {
        if context.isPreview && SharedStorage.load().isEmpty { return .sample(configuration.theme) }
        return load(at: Date(), theme: configuration.theme)
    }

    func timeline(for configuration: StyleIntent, in context: Context) async -> Timeline<WEntry> {
        let now = Date()
        let events = SharedStorage.load()
        let state = SharedStorage.loadState()
        Palette.colorful = SharedStorage.loadSettings().colorful
        let cal = Calendar.current

        // Перерисовка: в начале и в конце каждого дела на сутки вперёд + в полночь
        var moments: [Date] = [now]
        for o in Schedule.occurrences(of: events, from: cal.startOfDay(for: now), to: now.addingTimeInterval(86400),
                                      skipped: state.skipped) {
            if o.date > now { moments.append(o.date.addingTimeInterval(1)) }
            if o.end > now && o.duration > 0 { moments.append(o.end.addingTimeInterval(1)) }
        }
        if let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) {
            moments.append(midnight)
        }
        moments = Array(Set(moments)).sorted().prefix(60).map { $0 }

        let entries = moments.map {
            WEntry(date: $0, events: events, state: state, theme: configuration.theme, hasAccess: SharedStorage.isShared)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func load(at date: Date, theme: WidgetTheme) -> WEntry {
        Palette.colorful = SharedStorage.loadSettings().colorful
        return WEntry(date: date, events: SharedStorage.load(), state: SharedStorage.loadState(),
                      theme: theme, hasAccess: SharedStorage.isShared)
    }
}

// MARK: - Оформление

extension WidgetFamily {
    var isAccessory: Bool {
        self == .accessoryCircular || self == .accessoryRectangular || self == .accessoryInline
    }
}

extension View {
    @ViewBuilder
    func themed(_ theme: WidgetTheme, _ family: WidgetFamily) -> some View {
        if family.isAccessory {
            self.containerBackground(for: .widget) { Color.clear }
        } else {
            switch theme {
            case .black:
                self.environment(\.colorScheme, .dark)
                    .containerBackground(for: .widget) { Color.black }
            case .white:
                self.environment(\.colorScheme, .light)
                    .containerBackground(for: .widget) { Color.white }
            case .auto:
                self.containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
            }
        }
    }
}

struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased(with: appLocale))
            .font(.system(size: 10, weight: .bold))
            .tracking(1)
            .foregroundStyle(.secondary)
    }
}

struct Mark: View {
    let done: Bool
    var size: CGFloat = 16
    var body: some View {
        ZStack {
            Circle().strokeBorder(Color.primary.opacity(done ? 1 : 0.35), lineWidth: 1.3)
            if done {
                Circle().fill(Color.primary)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.45, weight: .heavy))
                    .foregroundStyle(Color(uiColor: .systemBackground))
            }
        }
        .frame(width: size, height: size)
    }
}

struct WRow: View {
    let occ: Occurrence
    var done = false
    var showMark = false
    var showDay = false

    var body: some View {
        HStack(spacing: 8) {
            if showMark { Mark(done: done, size: 14) }
            Text(showDay && !shortDay(occ.date).isEmpty ? "\(shortDay(occ.date)) \(timeString(occ.date))" : timeString(occ.date))
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(occ.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(occ.color)
                .strikethrough(done)
                .lineLimit(1)
            if occ.important { Image(systemName: "star.fill").font(.system(size: 8)) }
            Spacer(minLength: 0)
        }
        .opacity(done ? 0.45 : 1)
    }
}

struct NoAccess: View {
    var compact = false
    var body: some View {
        if compact {
            Text(L("Открой приложение", "Open the app")).font(.caption)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle").font(.title3)
                Text(L("Открой Schedule Control → Ещё → Диагностика", "Open Schedule Control → More → Diagnostics"))
                    .font(.caption2).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
        }
    }
}

struct Free: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "checkmark").font(.title3.weight(.semibold))
            Spacer(minLength: 0)
            Text(L("Свободно", "Free")).font(.headline)
            Text(L("Ближайших дел нет", "Nothing coming up")).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Базовая обёртка: стиль + проверка доступа
struct WidgetShell<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    let entry: WEntry
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if entry.hasAccess { content() } else { NoAccess(compact: family.isAccessory) }
        }
        .environment(\.locale, appLocale)
        .themed(entry.theme, family)
    }
}

// MARK: - 1. «Дальше» — главный виджет, все размеры

struct NextView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WEntry

    var body: some View {
        WidgetShell(entry: entry) {
            switch family {
            case .systemMedium: medium
            case .systemLarge: large
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            default: small
            }
        }
    }

    @ViewBuilder
    private func block(_ o: Occurrence) -> some View {
        let now = o.isNow(entry.date)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: o.icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(o.color)
                Caption(now ? L("Сейчас", "Now") : L("Дальше", "Next"))
            }
            Text(o.title)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(2)
                .padding(.top, 2)
            Spacer(minLength: 0)
            Text(now ? timeString(o.end) : timeString(o.date))
                .font(.system(size: 34, weight: .semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Group {
                if now {
                    Text(L("до конца ", "ends in ")) + Text(o.end, style: .relative)
                } else if Calendar.current.isDateInToday(o.date) {
                    Text(L("через ", "in ")) + Text(o.date, style: .relative)
                } else {
                    Text(dayLabel(o.date))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var small: some View {
        if let o = entry.next { block(o) } else { Free() }
    }

    @ViewBuilder private var medium: some View {
        let list = entry.upcoming(4)
        if let first = list.first {
            HStack(alignment: .top, spacing: 14) {
                block(first)
                if list.count > 1 {
                    VStack(alignment: .leading, spacing: 9) {
                        Caption(L("Потом", "Later"))
                        ForEach(list.dropFirst()) { WRow(occ: $0, showDay: true) }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            Free()
        }
    }

    private var large: some View {
        let today = entry.today
        let firstOpen = today.firstIndex { $0.end > entry.date || $0.date >= entry.date } ?? today.count
        let from = max(0, min(firstOpen - 2, today.count - 7))
        let shown = Array(today[from..<today.count].prefix(7))
        let later = entry.upcoming(12).filter { !Calendar.current.isDateInToday($0.date) }.prefix(max(0, 10 - shown.count))

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(cap(fmt(entry.date, "EEEE"))).font(.system(size: 22, weight: .bold))
                Text(fmt(entry.date, "dMMMM")).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if !today.isEmpty {
                    Text("\(entry.doneToday)/\(today.count)").font(.subheadline.weight(.semibold)).monospacedDigit()
                }
            }
            if !today.isEmpty {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.1))
                        Capsule().fill(Color.primary)
                            .frame(width: g.size.width * CGFloat(entry.doneToday) / CGFloat(max(today.count, 1)))
                    }
                }
                .frame(height: 3)
            }
            Caption(L("Сегодня", "Today"))
            if shown.isEmpty {
                Text(L("Ничего не запланировано", "Nothing planned")).font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(shown) { WRow(occ: $0, done: entry.isDone($0), showMark: true) }
            }
            if !later.isEmpty {
                Caption(L("Дальше", "Later")).padding(.top, 4)
                ForEach(Array(later)) { WRow(occ: $0, showDay: true) }
            }
            Spacer(minLength: 0)
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let o = entry.next {
                VStack(spacing: 0) {
                    Image(systemName: o.icon).font(.system(size: 11, weight: .semibold))
                    Text(timeString(o.date))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .widgetAccentable()
                }
                .padding(4)
            } else {
                Image(systemName: "checkmark").font(.title3)
            }
        }
    }

    @ViewBuilder private var rectangular: some View {
        if let o = entry.next {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(o.timeRange) · \(dayLabel(o.date))")
                    .font(.system(size: 13, weight: .semibold))
                    .widgetAccentable()
                Text(o.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                if Calendar.current.isDateInToday(o.date) && o.date > entry.date {
                    (Text(L("через ", "in ")) + Text(o.date, style: .relative))
                        .font(.caption).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Label(L("Дел нет", "All clear"), systemImage: "checkmark")
        }
    }

    @ViewBuilder private var inline: some View {
        if let o = entry.next {
            Label("\(timeString(o.date)) \(o.title)", systemImage: o.icon)
        } else {
            Label(L("Дел нет", "All clear"), systemImage: "checkmark")
        }
    }
}

struct NextWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NextWidget", intent: StyleIntent.self, provider: Provider()) { NextView(entry: $0) }
            .configurationDisplayName(L("Дальше", "Up next"))
            .description(L("Следующее дело и список на день", "Your next task and the day ahead"))
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                                .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - 2. Чек-лист — интерактивный: галочки прямо на виджете

struct ChecklistView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WEntry

    var body: some View {
        WidgetShell(entry: entry) {
            let today = entry.today
            let limit = family == .systemLarge ? 9 : 4
            let firstOpen = today.firstIndex { !entry.isDone($0) } ?? 0
            let start = max(0, min(firstOpen, today.count - limit))
            let shown = Array(today[start..<today.count].prefix(limit))

            VStack(alignment: .leading, spacing: family == .systemLarge ? 11 : 8) {
                HStack {
                    Caption(L("Чек-лист на сегодня", "Today's checklist"))
                    Spacer()
                    Text("\(entry.doneToday)/\(today.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                }
                if shown.isEmpty {
                    Spacer()
                    Text(L("На сегодня пусто", "Nothing today")).font(.headline)
                    Spacer()
                } else {
                    ForEach(shown) { o in
                        Button(intent: ToggleDoneIntent(key: o.key)) {
                            HStack(spacing: 10) {
                                Mark(done: entry.isDone(o), size: 20)
                                Text(o.title)
                                    .font(.system(size: 14, weight: .medium))
                                    .strikethrough(entry.isDone(o))
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(timeString(o.date))
                                    .font(.system(size: 12))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .opacity(entry.isDone(o) ? 0.45 : 1)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

struct ChecklistWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ChecklistWidget", intent: StyleIntent.self, provider: Provider()) { ChecklistView(entry: $0) }
            .configurationDisplayName(L("Чек-лист", "Checklist"))
            .description(L("Отмечай дела галочкой прямо на виджете", "Check off tasks right from the widget"))
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - 3. Прогресс дня

struct ProgressWView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WEntry

    var body: some View {
        WidgetShell(entry: entry) {
            let total = entry.today.count
            let done = entry.doneToday
            let value = total == 0 ? 0 : Double(done) / Double(total)
            let nextOpen = entry.today.first { !entry.isDone($0) && $0.end >= entry.date }

            switch family {
            case .accessoryCircular:
                Gauge(value: value) {
                    Image(systemName: "checkmark")
                } currentValueLabel: {
                    Text("\(done)/\(total)")
                }
                .gaugeStyle(.accessoryCircularCapacity)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 3) {
                    Text(total == 0 ? L("Сегодня пусто", "Nothing today") : L("Сделано \(done) из \(total)", "\(done) of \(total) done"))
                        .font(.system(size: 14, weight: .semibold))
                        .widgetAccentable()
                    Gauge(value: value) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
                    if let n = nextOpen {
                        Text("\(timeString(n.date)) \(n.title)").font(.caption).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 0) {
                    Caption(L("Прогресс дня", "Today"))
                    Spacer(minLength: 0)
                    ZStack {
                        Circle().stroke(Color.primary.opacity(0.1), lineWidth: 9)
                        Circle()
                            .trim(from: 0, to: max(0.001, value))
                            .stroke(Color.primary, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: -2) {
                            Text("\(Int((value * 100).rounded()))")
                                .font(.system(size: 26, weight: .bold))
                                .monospacedDigit()
                            Text("%").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 86, height: 86)
                    .frame(maxWidth: .infinity)
                    Spacer(minLength: 0)
                    Text(total == 0 ? L("Свободный день", "Free day") : L("\(done) из \(total)", "\(done) of \(total)"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct ProgressWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ProgressWidget", intent: StyleIntent.self, provider: Provider()) { ProgressWView(entry: $0) }
            .configurationDisplayName(L("Прогресс", "Progress"))
            .description(L("Сколько дел сегодня уже сделано", "How much of today is done"))
            .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - 4. Обратный отсчёт

struct CountdownView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WEntry

    var body: some View {
        WidgetShell(entry: entry) {
            let next = entry.upcoming(10).first { $0.date > entry.date }
            switch family {
            case .accessoryCircular:
                if let o = next {
                    ProgressView(timerInterval: entry.date...max(o.date, entry.date.addingTimeInterval(60)), countsDown: true) {
                        Image(systemName: o.icon)
                    } currentValueLabel: {
                        Image(systemName: o.icon)
                    }
                    .progressViewStyle(.circular)
                } else {
                    ZStack { AccessoryWidgetBackground(); Image(systemName: "checkmark") }
                }
            case .accessoryRectangular:
                if let o = next {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(o.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text(o.date, style: .timer)
                            .font(.system(size: 22, weight: .semibold))
                            .monospacedDigit()
                            .widgetAccentable()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Label(L("Дел нет", "All clear"), systemImage: "checkmark")
                }
            default:
                if let o = next {
                    VStack(alignment: .leading, spacing: 4) {
                        Caption(L("До начала", "Starts in"))
                        Spacer(minLength: 0)
                        Text(o.date, style: .timer)
                            .font(.system(size: 30, weight: .bold))
                            .monospacedDigit()
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text(o.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(2)
                        Text("\(dayLabel(o.date)), \(timeString(o.date))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    Free()
                }
            }
        }
    }
}

struct CountdownWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "CountdownWidget", intent: StyleIntent.self, provider: Provider()) { CountdownView(entry: $0) }
            .configurationDisplayName(L("Таймер", "Countdown"))
            .description(L("Живой обратный отсчёт до следующего дела", "Live countdown to your next task"))
            .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - 5. Неделя

struct WeekView: View {
    let entry: WEntry

    var body: some View {
        WidgetShell(entry: entry) {
            let week = entry.week
            let maxTotal = max(week.map { $0.total }.max() ?? 1, 1)
            let symbols = orderedWeekdaySymbols()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Caption(L("Неделя", "This week"))
                    Spacer()
                    Text("\(week.reduce(0) { $0 + $1.done })/\(week.reduce(0) { $0 + $1.total })")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                }
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(week.enumerated()), id: \.offset) { i, d in
                        let isToday = Calendar.current.isDateInToday(d.date)
                        VStack(spacing: 5) {
                            Text("\(d.total)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .opacity(d.total > 0 ? 1 : 0)
                            GeometryReader { g in
                                let h = g.size.height * CGFloat(d.total) / CGFloat(maxTotal)
                                let doneH = d.total == 0 ? 0 : h * CGFloat(d.done) / CGFloat(d.total)
                                VStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    ZStack(alignment: .bottom) {
                                        RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.12))
                                            .frame(height: max(h, 4))
                                        RoundedRectangle(cornerRadius: 4).fill(Color.primary)
                                            .frame(height: doneH)
                                    }
                                }
                            }
                            Text(i < symbols.count ? symbols[i] : "")
                                .font(.system(size: 11, weight: isToday ? .bold : .medium))
                                .foregroundStyle(isToday ? Color(uiColor: .systemBackground) : Color.secondary)
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(isToday ? Color.primary : Color.clear))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WeekWidget", intent: StyleIntent.self, provider: Provider()) { WeekView(entry: $0) }
            .configurationDisplayName(L("Неделя", "Week"))
            .description(L("Загруженность и прогресс по дням недели", "Workload and progress for each day"))
            .supportedFamilies([.systemMedium])
    }
}

// MARK: - 6. Месяц

struct MonthView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WEntry

    var body: some View {
        WidgetShell(entry: entry) {
            if family == .systemMedium {
                HStack(spacing: 14) {
                    grid(compact: true)
                    VStack(alignment: .leading, spacing: 8) {
                        Caption(L("Дальше", "Next"))
                        let list = entry.upcoming(4)
                        if list.isEmpty {
                            Text(L("Свободно", "Free")).font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            ForEach(list) { WRow(occ: $0, showDay: true) }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                grid(compact: true)
            }
        }
    }

    private func grid(compact: Bool) -> some View {
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: entry.date)) ?? entry.date
        let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let busy = Set(Schedule.occurrences(of: entry.events, from: monthStart, to: monthEnd, skipped: entry.state.skipped)
            .map { cal.component(.day, from: $0.date) })
        let count = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let leading = (cal.component(.weekday, from: monthStart) - cal.firstWeekday + 7) % 7
        let cells: [Int?] = Array(repeating: nil, count: leading) + (1...count).map { Optional($0) }
        let today = cal.component(.day, from: entry.date)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

        return VStack(alignment: .leading, spacing: 4) {
            Text(cap(fmt(entry.date, "LLLL")))
                .font(.system(size: 13, weight: .bold))
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(orderedWeekdaySymbols().enumerated()), id: \.offset) { _, s in
                    Text(s).font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        let isToday = day == today
                        VStack(spacing: 1) {
                            Text("\(day)")
                                .font(.system(size: 9, weight: isToday ? .bold : .regular))
                                .monospacedDigit()
                                .foregroundStyle(isToday ? Color(uiColor: .systemBackground) : Color.primary)
                                .frame(width: 15, height: 15)
                                .background(Circle().fill(isToday ? Color.primary : Color.clear))
                            Circle().fill(Color.primary)
                                .frame(width: 2.5, height: 2.5)
                                .opacity(busy.contains(day) && !isToday ? 1 : 0)
                        }
                    } else {
                        Color.clear.frame(height: 18)
                    }
                }
            }
        }
        .frame(maxWidth: compact ? .infinity : nil)
    }
}

struct MonthWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "MonthWidget", intent: StyleIntent.self, provider: Provider()) { MonthView(entry: $0) }
            .configurationDisplayName(L("Месяц", "Month"))
            .description(L("Календарь с отмеченными днями", "Calendar with busy days marked"))
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Точка входа

@main
struct ScheduleWidgets: WidgetBundle {
    var body: some Widget {
        NextWidget()
        ChecklistWidget()
        ProgressWidget()
        CountdownWidget()
        WeekWidget()
        MonthWidget()
    }
}
