import Foundation

// MARK: - Язык: автоматически по языку системы (русский → RU, всё остальное → EN)

let isRU: Bool = {
    let lang = (Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "en").lowercased()
    return lang.hasPrefix("ru") || lang.hasPrefix("uk") || lang.hasPrefix("be") || lang.hasPrefix("kk")
}()

let appLocale = Locale(identifier: isRU ? "ru_RU" : "en_US")

/// L("по-русски", "in English")
func L(_ ru: String, _ en: String) -> String { isRU ? ru : en }

/// Склонение: plural(3, "день", "дня", "дней", "day", "days")
func plural(_ n: Int, _ one: String, _ few: String, _ many: String, _ enOne: String, _ enMany: String) -> String {
    guard isRU else { return n == 1 ? enOne : enMany }
    let n10 = n % 10, n100 = n % 100
    if n10 == 1 && n100 != 11 { return one }
    if (2...4).contains(n10) && !(12...14).contains(n100) { return few }
    return many
}

// MARK: - Форматирование дат

func timeString(_ d: Date) -> String {
    d.formatted(.dateTime.hour().minute().locale(appLocale))
}

/// Шаблон вида "EEEEdMMMM" — порядок слов подставится под язык
func fmt(_ d: Date, _ template: String) -> String {
    let f = DateFormatter()
    f.locale = appLocale
    f.setLocalizedDateFormatFromTemplate(template)
    return f.string(from: d)
}

func cap(_ s: String) -> String {
    s.prefix(1).uppercased(with: appLocale) + s.dropFirst()
}

func dayLabel(_ d: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(d) { return L("сегодня", "today") }
    if cal.isDateInTomorrow(d) { return L("завтра", "tomorrow") }
    return fmt(d, "EEEdMMM")
}

func shortDay(_ d: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(d) { return "" }
    if cal.isDateInTomorrow(d) { return L("завтра", "tmrw") }
    return fmt(d, "EEE")
}

func durationText(_ minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
    if h == 0 { return L("\(m) мин", "\(m) min") }
    if m == 0 { return L("\(h) ч", "\(h) h") }
    return L("\(h) ч \(m) мин", "\(h) h \(m) min")
}

/// Названия дней недели по порядку календаря (с учётом первого дня недели)
func orderedWeekdaySymbols(short: Bool = true) -> [String] {
    let f = DateFormatter()
    f.locale = appLocale
    let symbols = (short ? f.veryShortStandaloneWeekdaySymbols : f.shortStandaloneWeekdaySymbols) ?? []
    guard symbols.count == 7 else { return symbols }
    let first = Calendar.current.firstWeekday - 1
    return Array(symbols[first...] + symbols[..<first]).map { cap($0) }
}
