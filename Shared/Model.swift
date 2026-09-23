import SwiftUI

// Общий код: используется и приложением, и виджетом.

let ru = Locale(identifier: "ru_RU")

// MARK: - Повтор

enum RepeatRule: String, Codable, CaseIterable, Identifiable {
    case none, daily, weekdays, weekends, weekly
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Один раз"
        case .daily: return "Каждый день"
        case .weekdays: return "По будням"
        case .weekends: return "По выходным"
        case .weekly: return "Каждую неделю"
        }
    }

    /// Дни недели для правил «по будням/выходным» (1 = вс … 7 = сб)
    var weekdaySet: [Int]? {
        switch self {
        case .weekdays: return [2, 3, 4, 5, 6]
        case .weekends: return [1, 7]
        default: return nil
        }
    }

    /// Нужна ли дата целиком (или важно только время)
    var needsFullDate: Bool { self == .none || self == .weekly }
}

// MARK: - Цвета и иконки

enum Palette {
    static let colors: [Color] = [.blue, .indigo, .purple, .pink, .red, .orange, .yellow, .green, .mint, .teal]

    static func color(_ index: Int) -> Color {
        let n = colors.count
        return colors[((index % n) + n) % n]
    }

    static let icons: [String] = [
        "calendar", "star.fill", "briefcase.fill", "laptopcomputer", "dumbbell.fill", "figure.run",
        "book.fill", "graduationcap.fill", "fork.knife", "cup.and.saucer.fill", "cart.fill", "phone.fill",
        "video.fill", "gamecontroller.fill", "music.note", "camera.fill", "car.fill", "airplane",
        "house.fill", "moon.fill", "heart.fill", "gift.fill", "dollarsign.circle.fill", "sparkles"
    ]
}

// MARK: - Событие

struct ScheduleEvent: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var note: String
    var date: Date
    var repeatRule: RepeatRule
    var remindBefore: Int      // за сколько минут напомнить
    var colorIndex: Int
    var icon: String

    init(id: UUID = UUID(), title: String, note: String = "", date: Date,
         repeatRule: RepeatRule = .none, remindBefore: Int = 0,
         colorIndex: Int = 0, icon: String = "calendar") {
        self.id = id
        self.title = title
        self.note = note
        self.date = date
        self.repeatRule = repeatRule
        self.remindBefore = remindBefore
        self.colorIndex = colorIndex
        self.icon = icon
    }

    enum CodingKeys: String, CodingKey {
        case id, title, note, date, repeatRule, remindBefore, colorIndex, icon
    }

    // Мягкое чтение: старые сохранения без цвета/иконки не ломаются
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        date = try c.decode(Date.self, forKey: .date)
        repeatRule = (try? c.decode(RepeatRule.self, forKey: .repeatRule)) ?? .none
        remindBefore = (try? c.decode(Int.self, forKey: .remindBefore)) ?? 0
        colorIndex = (try? c.decode(Int.self, forKey: .colorIndex)) ?? 0
        icon = (try? c.decode(String.self, forKey: .icon)) ?? "calendar"
    }

    var color: Color { Palette.color(colorIndex) }
}

/// Конкретное «наступление» события (повторяющееся событие даёт много таких)
struct Occurrence: Identifiable, Hashable {
    let eventID: UUID
    let title: String
    let note: String
    let date: Date
    let colorIndex: Int
    let icon: String

    var id: String { "\(eventID.uuidString)-\(date.timeIntervalSince1970)" }
    var color: Color { Palette.color(colorIndex) }

    init(event e: ScheduleEvent, date: Date) {
        eventID = e.id
        title = e.title
        note = e.note
        self.date = date
        colorIndex = e.colorIndex
        icon = e.icon
    }
}

// MARK: - Расчёт наступлений

enum Schedule {
    /// Какие компоненты даты должны совпасть для повторяющегося события
    static func matchComponents(for e: ScheduleEvent) -> [DateComponents] {
        let cal = Calendar.current
        let hm = cal.dateComponents([.hour, .minute], from: e.date)
        switch e.repeatRule {
        case .none:
            return []
        case .daily:
            return [hm]
        case .weekly:
            return [cal.dateComponents([.weekday, .hour, .minute], from: e.date)]
        case .weekdays, .weekends:
            return (e.repeatRule.weekdaySet ?? []).map { wd in
                var c = hm
                c.weekday = wd
                return c
            }
        }
    }

    static func occurrences(of events: [ScheduleEvent], from start: Date, to end: Date, limit: Int = 500) -> [Occurrence] {
        let cal = Calendar.current
        var result: [Occurrence] = []

        for e in events {
            if e.repeatRule == .none {
                if e.date >= start && e.date < end {
                    result.append(Occurrence(event: e, date: e.date))
                }
                continue
            }
            // Повторяющиеся начинаются с дня создания
            let from = max(start, cal.startOfDay(for: e.date))
            guard from < end else { continue }

            for comps in matchComponents(for: e) {
                var cursor = from.addingTimeInterval(-1)
                var count = 0
                while let next = cal.nextDate(after: cursor, matching: comps, matchingPolicy: .nextTime),
                      next < end, count < 120 {
                    result.append(Occurrence(event: e, date: next))
                    cursor = next
                    count += 1
                }
            }
        }
        return Array(result.sorted { $0.date < $1.date }.prefix(limit))
    }

    static func day(_ date: Date, events: [ScheduleEvent]) -> [Occurrence] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        return occurrences(of: events, from: start, to: end)
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

func ruFormat(_ d: Date, _ pattern: String) -> String {
    let f = DateFormatter()
    f.locale = ru
    f.dateFormat = pattern
    return f.string(from: d)
}
