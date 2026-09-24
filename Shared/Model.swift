import SwiftUI

// MARK: - Повтор

enum RepeatRule: String, Codable, CaseIterable, Identifiable {
    case none, daily, weekdays, weekends, weekly
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return L("Один раз", "Once")
        case .daily: return L("Каждый день", "Every day")
        case .weekdays: return L("По будням", "Weekdays")
        case .weekends: return L("По выходным", "Weekends")
        case .weekly: return L("Каждую неделю", "Every week")
        }
    }

    /// Дни недели для «по будням/выходным» (1 = вс … 7 = сб)
    var weekdaySet: [Int]? {
        switch self {
        case .weekdays: return [2, 3, 4, 5, 6]
        case .weekends: return [1, 7]
        default: return nil
        }
    }

    var needsFullDate: Bool { self == .none || self == .weekly }
}

// MARK: - Палитра: по умолчанию чёрно-белая, цвета — опция в настройках

enum Palette {
    /// Включается в «Ещё → Цветные метки»
    static var colorful = false

    static let colors: [Color] = [.blue, .indigo, .purple, .pink, .red, .orange, .yellow, .green, .mint, .teal]

    static func raw(_ index: Int) -> Color {
        let n = colors.count
        return colors[((index % n) + n) % n]
    }

    static func color(_ index: Int) -> Color {
        colorful ? raw(index) : .primary
    }

    static let icons: [String] = [
        "circle.fill", "star.fill", "briefcase.fill", "laptopcomputer", "dumbbell.fill", "figure.run",
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
    var remindBefore: Int      // минуты
    var colorIndex: Int
    var icon: String
    var duration: Int          // минуты, 0 = без длительности
    var important: Bool

    init(id: UUID = UUID(), title: String, note: String = "", date: Date,
         repeatRule: RepeatRule = .none, remindBefore: Int = 0,
         colorIndex: Int = 0, icon: String = "circle.fill",
         duration: Int = 0, important: Bool = false) {
        self.id = id
        self.title = title
        self.note = note
        self.date = date
        self.repeatRule = repeatRule
        self.remindBefore = remindBefore
        self.colorIndex = colorIndex
        self.icon = icon
        self.duration = duration
        self.important = important
    }

    enum CodingKeys: String, CodingKey {
        case id, title, note, date, repeatRule, remindBefore, colorIndex, icon, duration, important
    }

    // Мягкое чтение: старые сохранения без новых полей не ломаются
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        date = try c.decode(Date.self, forKey: .date)
        repeatRule = (try? c.decode(RepeatRule.self, forKey: .repeatRule)) ?? .none
        remindBefore = (try? c.decode(Int.self, forKey: .remindBefore)) ?? 0
        colorIndex = (try? c.decode(Int.self, forKey: .colorIndex)) ?? 0
        icon = (try? c.decode(String.self, forKey: .icon)) ?? "circle.fill"
        duration = (try? c.decode(Int.self, forKey: .duration)) ?? 0
        important = (try? c.decode(Bool.self, forKey: .important)) ?? false
    }

    var color: Color { Palette.color(colorIndex) }
}

// MARK: - Конкретное наступление события

struct Occurrence: Identifiable, Hashable {
    let eventID: UUID
    let title: String
    let note: String
    let date: Date
    let duration: Int
    let colorIndex: Int
    let icon: String
    let important: Bool
    let repeating: Bool

    init(event e: ScheduleEvent, date: Date) {
        eventID = e.id
        title = e.title
        note = e.note
        self.date = date
        duration = e.duration
        colorIndex = e.colorIndex
        icon = e.icon
        important = e.important
        repeating = e.repeatRule != .none
    }

    /// Стабильный ключ для «выполнено» и «пропустить»
    var key: String { "\(eventID.uuidString)|\(Int(date.timeIntervalSince1970))" }
    var id: String { key }
    var end: Date { date.addingTimeInterval(TimeInterval(max(duration, 0) * 60)) }
    var color: Color { Palette.color(colorIndex) }

    func isNow(_ now: Date) -> Bool { duration > 0 && date <= now && now < end }

    var timeRange: String {
        duration > 0 ? "\(timeString(date))–\(timeString(end))" : timeString(date)
    }
}

// MARK: - Расчёт наступлений

enum Schedule {
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

    static func occurrences(of events: [ScheduleEvent], from start: Date, to end: Date,
                            limit: Int = 500, skipped: Set<String> = []) -> [Occurrence] {
        let cal = Calendar.current
        var result: [Occurrence] = []

        for e in events {
            if e.repeatRule == .none {
                if e.date >= start && e.date < end {
                    result.append(Occurrence(event: e, date: e.date))
                }
                continue
            }
            let from = max(start, cal.startOfDay(for: e.date))
            guard from < end else { continue }

            for comps in matchComponents(for: e) {
                var cursor = from.addingTimeInterval(-1)
                var count = 0
                while let next = cal.nextDate(after: cursor, matching: comps, matchingPolicy: .nextTime),
                      next < end, count < 400 {
                    result.append(Occurrence(event: e, date: next))
                    cursor = next
                    count += 1
                }
            }
        }
        let visible = skipped.isEmpty ? result : result.filter { !skipped.contains($0.key) }
        return Array(visible.sorted { $0.date < $1.date }.prefix(limit))
    }

    static func day(_ date: Date, events: [ScheduleEvent], skipped: Set<String> = []) -> [Occurrence] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        return occurrences(of: events, from: start, to: end, skipped: skipped)
    }

    /// Текущие и будущие (то, что идёт прямо сейчас, тоже попадает)
    static func upcoming(_ events: [ScheduleEvent], now: Date, limit: Int, skipped: Set<String> = []) -> [Occurrence] {
        let start = Calendar.current.startOfDay(for: now)
        let list = occurrences(of: events, from: start, to: now.addingTimeInterval(21 * 86400), skipped: skipped)
        return Array(list.filter { $0.date >= now || $0.end > now }.prefix(limit))
    }
}
