import Foundation

// Общий код: используется и приложением, и виджетом.

let ru = Locale(identifier: "ru_RU")

enum RepeatRule: String, Codable, CaseIterable, Identifiable {
    case none, daily, weekly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "Один раз"
        case .daily: return "Каждый день"
        case .weekly: return "Каждую неделю"
        }
    }
}

struct ScheduleEvent: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var note: String = ""
    var date: Date
    var repeatRule: RepeatRule = .none
    var remindBefore: Int = 0 // за сколько минут напомнить
}

/// Конкретное «наступление» события (повторяющееся событие даёт много таких).
struct Occurrence: Identifiable, Hashable {
    let eventID: UUID
    let title: String
    let note: String
    let date: Date
    var id: String { "\(eventID.uuidString)-\(date.timeIntervalSince1970)" }
}

// MARK: - Хранилище в общей папке App Group

enum SharedStorage {
    static let appGroup = "group.com.nofy.raspisanie"

    static var groupContainer: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    /// true — приложение и виджет видят одну и ту же папку
    static var isShared: Bool { groupContainer != nil }

    static var fileURL: URL {
        (groupContainer ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
            .appendingPathComponent("events.json")
    }

    static func load() -> [ScheduleEvent] {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([ScheduleEvent].self, from: data) else { return [] }
        return list
    }

    static func save(_ events: [ScheduleEvent]) {
        if let data = try? JSONEncoder().encode(events) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

// MARK: - Расчёт ближайших наступлений

enum Schedule {
    static func occurrences(of events: [ScheduleEvent], from start: Date, to end: Date, limit: Int = 200) -> [Occurrence] {
        let cal = Calendar.current
        var result: [Occurrence] = []

        for e in events {
            switch e.repeatRule {
            case .none:
                if e.date >= start && e.date < end {
                    result.append(Occurrence(eventID: e.id, title: e.title, note: e.note, date: e.date))
                }
            case .daily, .weekly:
                let comps = e.repeatRule == .daily
                    ? cal.dateComponents([.hour, .minute], from: e.date)
                    : cal.dateComponents([.weekday, .hour, .minute], from: e.date)
                var cursor = start.addingTimeInterval(-1)
                var count = 0
                while let next = cal.nextDate(after: cursor, matching: comps, matchingPolicy: .nextTime),
                      next < end, count < 60 {
                    result.append(Occurrence(eventID: e.id, title: e.title, note: e.note, date: next))
                    cursor = next
                    count += 1
                }
            }
        }
        return Array(result.sorted { $0.date < $1.date }.prefix(limit))
    }
}

// MARK: - Форматирование

func timeString(_ d: Date) -> String {
    d.formatted(.dateTime.hour().minute().locale(ru))
}

func dayLabel(_ d: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(d) { return "сегодня" }
    if cal.isDateInTomorrow(d) { return "завтра" }
    return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(ru))
}

func shortDay(_ d: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(d) { return "" }
    if cal.isDateInTomorrow(d) { return "завтра" }
    return d.formatted(.dateTime.weekday(.abbreviated).locale(ru))
}
