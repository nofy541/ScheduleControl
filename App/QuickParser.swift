import Foundation

/// Быстрое добавление: «зал завтра в 18», «созвон в пт в 15:30», «пробежка по будням в 7»,
/// "gym tomorrow at 6pm", "call fri 15:30", "run weekdays at 7am"
struct QuickParse {
    var title: String
    var date: Date
    var repeatRule: RepeatRule
}

enum QuickParser {
    static func parse(_ text: String, now: Date = Date()) -> QuickParse? {
        var s = " " + text.replacingOccurrences(of: "\n", with: " ") + " "
        let cal = Calendar.current
        var repeatRule = RepeatRule.none
        var dayOffset: Int?
        var weekday: Int?
        var hour: Int?
        var minute = 0

        /// Находит шаблон, вырезает его из строки и возвращает группы
        func take(_ pattern: String) -> [String]? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
            let ns = s as NSString
            guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
            var groups: [String] = []
            for i in 0..<m.numberOfRanges {
                let r = m.range(at: i)
                groups.append(r.location == NSNotFound ? "" : ns.substring(with: r).lowercased())
            }
            s = ns.replacingCharacters(in: m.range, with: " ")
            return groups
        }

        // Повтор
        if take(#"\s(каждый день|ежедневно|every day|everyday|daily)(?=\s)"#) != nil { repeatRule = .daily }
        else if take(#"\s(по будням|в будни|weekdays|every weekday|on weekdays)(?=\s)"#) != nil { repeatRule = .weekdays }
        else if take(#"\s(по выходным|в выходные|weekends|on weekends)(?=\s)"#) != nil { repeatRule = .weekends }
        else if take(#"\s(каждую неделю|еженедельно|weekly|every week)(?=\s)"#) != nil { repeatRule = .weekly }

        // День
        if take(#"\s(послезавтра|day after tomorrow)(?=\s)"#) != nil { dayOffset = 2 }
        else if take(#"\s(завтра|tomorrow|tmrw)(?=\s)"#) != nil { dayOffset = 1 }
        else if take(#"\s(сегодня|today|tonight)(?=\s)"#) != nil { dayOffset = 0 }

        // День недели
        if dayOffset == nil {
            if let g = take(#"\s(?:(?:в|во|каждый|каждую|каждое)\s)?(понедельник|вторник|среду|среда|четверг|пятницу|пятница|субботу|суббота|воскресенье|пн|вт|ср|чт|пт|сб|вс)(?=\s)"#) {
                weekday = ruWeekday(g[1])
            } else if let g = take(#"\s(?:(?:on|every)\s)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun)(?=\s)"#) {
                weekday = enWeekday(g[1])
            }
        }

        // Время: «в 18», «в 18:30», «at 6pm», «15:30», «7am»
        var suffix = ""
        if let g = take(#"\s(?:в|во|at|@)\s*(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm|утра|вечера|дня|ночи)?(?=\s)"#) {
            hour = Int(g[1]); minute = Int(g[2]) ?? 0; suffix = g[3]
        } else if let g = take(#"\s(\d{1,2})[:.](\d{2})\s*(am|pm)?(?=\s)"#) {
            hour = Int(g[1]); minute = Int(g[2]) ?? 0; suffix = g[3]
        } else if let g = take(#"\s(\d{1,2})\s*(am|pm)(?=\s)"#) {
            hour = Int(g[1]); suffix = g[2]
        }
        if var h = hour {
            if ["pm", "вечера", "дня"].contains(suffix), h < 12 { h += 12 }
            if ["am", "ночи", "утра"].contains(suffix), h == 12 { h = 0 }
            hour = (0...23).contains(h) ? h : nil
            if !(0...59).contains(minute) { minute = 0 }
        }

        // Название — всё, что осталось
        let title = s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !title.isEmpty else { return nil }

        // Собираем дату
        var day = cal.startOfDay(for: now)
        if let dayOffset {
            day = cal.date(byAdding: .day, value: dayOffset, to: day) ?? day
        } else if let weekday {
            day = cal.nextDate(after: day.addingTimeInterval(-1), matching: DateComponents(weekday: weekday),
                               matchingPolicy: .nextTime) ?? day
        }

        var date: Date
        if let hour {
            date = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
            // Время уже прошло сегодня, а день не указан — значит завтра
            if dayOffset == nil && weekday == nil && repeatRule == .none && date < now {
                date = cal.date(byAdding: .day, value: 1, to: date) ?? date
            }
        } else if dayOffset != nil || weekday != nil {
            date = cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        } else {
            let startOfHour = cal.dateInterval(of: .hour, for: now)?.start ?? now
            date = cal.date(byAdding: .hour, value: 1, to: startOfHour) ?? now
        }

        if weekday != nil && repeatRule == .none && text.lowercased().contains(L("кажд", "every")) {
            repeatRule = .weekly
        }

        return QuickParse(title: cap(title), date: date, repeatRule: repeatRule)
    }

    private static func ruWeekday(_ s: String) -> Int? {
        let map: [(String, Int)] = [("пн", 2), ("пон", 2), ("вт", 3), ("ср", 4), ("чт", 5), ("чет", 5),
                                    ("пт", 6), ("пят", 6), ("сб", 7), ("суб", 7), ("вс", 1), ("вос", 1)]
        for (prefix, wd) in map.sorted(by: { $0.0.count > $1.0.count }) where s.hasPrefix(prefix) { return wd }
        return nil
    }

    private static func enWeekday(_ s: String) -> Int? {
        let map = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]
        return map[String(s.prefix(3))]
    }
}
