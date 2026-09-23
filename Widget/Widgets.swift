import WidgetKit
import SwiftUI

// MARK: - Данные для виджета

struct ScheduleEntry: TimelineEntry {
    let date: Date
    let upcoming: [Occurrence]   // ближайшие дела начиная с date
    let today: [Occurrence]      // все дела сегодняшнего дня
    let hasAccess: Bool          // видит ли виджет общую папку

    static func make(at date: Date, events: [ScheduleEvent]) -> ScheduleEntry {
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: date)
        let endDay = cal.date(byAdding: .day, value: 1, to: startDay) ?? startDay.addingTimeInterval(86400)
        return ScheduleEntry(
            date: date,
            upcoming: Schedule.occurrences(of: events, from: date, to: date.addingTimeInterval(14 * 86400), limit: 10),
            today: Schedule.occurrences(of: events, from: startDay, to: endDay),
            hasAccess: SharedStorage.isShared
        )
    }

    static var sample: ScheduleEntry {
        let now = Date()
        let items: [(String, Double)] = [("Зал", 3600), ("Созвон", 3 * 3600), ("Ужин", 5 * 3600), ("Кодинг", 6 * 3600)]
        let occ = items.map { Occurrence(eventID: UUID(), title: $0.0, note: "", date: now.addingTimeInterval($0.1)) }
        return ScheduleEntry(date: now, upcoming: occ, today: occ, hasAccess: true)
    }
}

struct ScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScheduleEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        if context.isPreview {
            completion(.sample)
        } else {
            completion(.make(at: Date(), events: SharedStorage.load()))
        }
    }

    // Виджет перерисовывается сразу после каждого события и в полночь
    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        let now = Date()
        let events = SharedStorage.load()
        let cal = Calendar.current

        var moments: [Date] = [now]
        let next24h = Schedule.occurrences(of: events, from: now, to: now.addingTimeInterval(86400))
        moments += next24h.prefix(30).map { $0.date.addingTimeInterval(1) }
        if let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) {
            moments.append(midnight)
        }
        moments = Array(Set(moments)).sorted()

        let entries = moments.map { ScheduleEntry.make(at: $0, events: events) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Общие куски UI

extension WidgetFamily {
    var isAccessory: Bool {
        self == .accessoryCircular || self == .accessoryRectangular || self == .accessoryInline
    }
}

extension View {
    func widgetBackground(_ family: WidgetFamily) -> some View {
        containerBackground(for: .widget) {
            if family.isAccessory {
                Color.clear
            } else {
                ZStack {
                    Color(uiColor: .systemBackground)
                    LinearGradient(colors: [Color.blue.opacity(0.18), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
        }
    }
}

struct OccRow: View {
    let occ: Occurrence
    var past = false
    var showDay = false

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(past ? Color.secondary : Color.blue)
                .frame(width: 3, height: 16)
            Text(showDay && !shortDay(occ.date).isEmpty ? "\(shortDay(occ.date)) \(timeString(occ.date))" : timeString(occ.date))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 42, alignment: .leading)
            Text(occ.title)
                .font(.subheadline)
                .lineLimit(1)
                .strikethrough(past)
            Spacer(minLength: 0)
        }
        .opacity(past ? 0.5 : 1)
    }
}

struct NoAccessView: View {
    var compact = false
    var body: some View {
        if compact {
            Text("Открой приложение").font(.caption)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle").font(.title2)
                Text("Открой «Расписание». Если не помогло — смотри README")
                    .font(.caption).multilineTextAlignment(.center)
            }
        }
    }
}

struct FreeView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle").font(.title).foregroundStyle(.green)
            Text("Свободно").font(.headline)
            Text("Ближайших дел нет").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Крупный блок «что дальше» — для маленького и среднего виджета
struct NextBlock: View {
    let next: Occurrence

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Дальше", systemImage: "calendar")
                .font(.caption.bold())
                .foregroundStyle(.blue)
            Text(next.title)
                .font(.headline)
                .lineLimit(2)
            if !next.note.isEmpty {
                Text(next.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(timeString(next.date))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
            if Calendar.current.isDateInToday(next.date) {
                (Text("через ") + Text(next.date, style: .relative))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text(dayLabel(next.date)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Виджет 1: «Ближайшие дела» (все размеры)

struct UpcomingView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScheduleEntry

    var body: some View {
        content.widgetBackground(family)
    }

    @ViewBuilder
    private var content: some View {
        if !entry.hasAccess {
            NoAccessView(compact: family.isAccessory)
        } else {
            switch family {
            case .systemSmall: small
            case .systemMedium: medium
            case .systemLarge: large
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            default: small
            }
        }
    }

    // Главный экран — маленький
    @ViewBuilder private var small: some View {
        if let next = entry.upcoming.first { NextBlock(next: next) } else { FreeView() }
    }

    // Главный экран — средний
    @ViewBuilder private var medium: some View {
        if let next = entry.upcoming.first {
            HStack(spacing: 12) {
                NextBlock(next: next)
                if entry.upcoming.count > 1 {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Потом").font(.caption.bold()).foregroundStyle(.secondary)
                        ForEach(entry.upcoming.dropFirst().prefix(3)) { OccRow(occ: $0, showDay: true) }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            FreeView()
        }
    }

    // Главный экран — большой: весь сегодняшний день + что дальше
    private var large: some View {
        let today = entry.today
        let firstUpcoming = today.firstIndex { $0.date > entry.date } ?? today.count
        let from = max(0, min(firstUpcoming - 2, today.count - 6))
        let todayShown = Array(today[from..<today.count].prefix(6))
        let later = entry.upcoming.filter { !Calendar.current.isDateInToday($0.date) }
        let laterShown = Array(later.prefix(max(0, 8 - todayShown.count)))

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Расписание").font(.headline)
                Spacer()
                Text(entry.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(ru)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("СЕГОДНЯ").font(.caption2.bold()).foregroundStyle(.secondary)
            if todayShown.isEmpty {
                Text("Ничего не запланировано").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(todayShown) { OccRow(occ: $0, past: $0.date <= entry.date) }
            }
            if !laterShown.isEmpty {
                Text("ДАЛЬШЕ").font(.caption2.bold()).foregroundStyle(.secondary).padding(.top, 4)
                ForEach(laterShown) { OccRow(occ: $0, showDay: true) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Экран блокировки — кружок
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let next = entry.upcoming.first {
                VStack(spacing: 1) {
                    Image(systemName: "bell.fill").font(.caption2)
                    Text(timeString(next.date))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .widgetAccentable()
                }
            } else {
                Image(systemName: "checkmark").font(.title3)
            }
        }
    }

    // Экран блокировки — прямоугольник
    @ViewBuilder private var rectangular: some View {
        if let next = entry.upcoming.first {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(timeString(next.date)) · \(dayLabel(next.date))")
                    .font(.headline)
                    .widgetAccentable()
                Text(next.title).font(.body).lineLimit(1)
                if Calendar.current.isDateInToday(next.date) {
                    (Text("через ") + Text(next.date, style: .relative))
                        .font(.caption).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Label("Дел нет", systemImage: "checkmark.circle")
        }
    }

    // Экран блокировки — строка над часами
    @ViewBuilder private var inline: some View {
        if let next = entry.upcoming.first {
            Label("\(timeString(next.date)) \(next.title)", systemImage: "calendar")
        } else {
            Label("Дел нет", systemImage: "checkmark")
        }
    }
}

struct UpcomingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UpcomingWidget", provider: ScheduleProvider()) { entry in
            UpcomingView(entry: entry).environment(\.locale, ru)
        }
        .configurationDisplayName("Ближайшие дела")
        .description("Что у тебя дальше по расписанию")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Виджет 2: «Прогресс дня»

struct DayProgressView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScheduleEntry

    private var total: Int { entry.today.count }
    private var done: Int { entry.today.filter { $0.date <= entry.date }.count }
    private var progress: Double { total == 0 ? 0 : Double(done) / Double(total) }
    private var nextToday: Occurrence? { entry.today.first { $0.date > entry.date } }

    private var nextText: String {
        if let n = nextToday { return "\(timeString(n.date)) \(n.title)" }
        return total == 0 ? "Сегодня свободно" : "На сегодня всё 🎉"
    }

    var body: some View {
        content.widgetBackground(family)
    }

    @ViewBuilder
    private var content: some View {
        if !entry.hasAccess {
            NoAccessView(compact: family.isAccessory)
        } else {
            switch family {
            case .accessoryCircular:
                Gauge(value: progress) {
                    Image(systemName: "checklist")
                } currentValueLabel: {
                    Text("\(done)/\(total)")
                }
                .gaugeStyle(.accessoryCircularCapacity)

            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 3) {
                    Text(total == 0 ? "Сегодня пусто" : "Сегодня: \(done) из \(total)")
                        .font(.headline)
                        .widgetAccentable()
                    Gauge(value: progress) { EmptyView() }
                        .gaugeStyle(.accessoryLinearCapacity)
                    Text(nextText).font(.caption).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            default: // маленький на главном экране
                VStack(spacing: 10) {
                    ZStack {
                        Circle().stroke(Color.blue.opacity(0.2), lineWidth: 10)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text("\(done)/\(total)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text("позади").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 84, height: 84)
                    Text(nextText).font(.caption).lineLimit(1)
                }
            }
        }
    }
}

struct DayProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DayProgressWidget", provider: ScheduleProvider()) { entry in
            DayProgressView(entry: entry).environment(\.locale, ru)
        }
        .configurationDisplayName("Прогресс дня")
        .description("Сколько дел на сегодня уже позади")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Точка входа расширения

@main
struct RaspisanieWidgets: WidgetBundle {
    var body: some Widget {
        UpcomingWidget()
        DayProgressWidget()
    }
}
