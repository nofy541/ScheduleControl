import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject var store: ScheduleStore

    struct DayStat: Identifiable {
        let date: Date
        let total: Int
        let done: Int
        var id: Date { date }
        var label: String { cap(fmt(date, "EEE")) }
    }

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let week: [DayStat] = (0..<7).reversed().compactMap { back in
            guard let d = cal.date(byAdding: .day, value: -back, to: today) else { return nil }
            let list = store.day(d)
            return DayStat(date: d, total: list.count, done: list.filter { store.isDone($0) }.count)
        }
        let weekTotal = week.reduce(0) { $0 + $1.total }
        let weekDone = week.reduce(0) { $0 + $1.done }
        let pct = weekTotal == 0 ? 0 : Int((Double(weekDone) / Double(weekTotal) * 100).rounded())
        let streak = currentStreak()
        let top = topTasks()

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(title: L("Статистика", "Stats"), subtitle: L("последние 7 дней", "last 7 days"))

                // Главная цифра
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(pct)")
                            .font(.system(size: 64, weight: .bold))
                            .monospacedDigit()
                        Text("%").font(.title.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    ProgressBar(value: Double(pct) / 100, height: 6)
                    Text(L("выполнено: \(weekDone) из \(weekTotal)", "completed: \(weekDone) of \(weekTotal)"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .card()

                HStack(spacing: 12) {
                    statTile(value: "\(streak)",
                             caption: plural(streak, "день подряд", "дня подряд", "дней подряд", "day streak", "day streak"),
                             icon: "flame")
                    statTile(value: "\(store.state.done.count)",
                             caption: L("всего отметок", "total done"),
                             icon: "checkmark.circle")
                }

                // График
                SectionTitle(L("По дням", "By day"))
                Chart {
                    ForEach(week) { d in
                        BarMark(x: .value("day", d.label), y: .value("n", d.done))
                            .foregroundStyle(Color.primary)
                            .cornerRadius(4)
                        BarMark(x: .value("day", d.label), y: .value("n", max(d.total - d.done, 0)))
                            .foregroundStyle(Color.primary.opacity(0.12))
                            .cornerRadius(4)
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 180)
                .card()

                // Топ дел
                if !top.isEmpty {
                    SectionTitle(L("Чаще всего выполняешь", "Most completed"))
                    RowGroup {
                        ForEach(Array(top.enumerated()), id: \.offset) { i, item in
                            if i > 0 { Hairline() }
                            HStack(spacing: 14) {
                                EventIcon(icon: item.event.icon, colorIndex: item.event.colorIndex, size: 32)
                                Text(item.event.title).font(.body.weight(.medium)).lineLimit(1)
                                Spacer()
                                Text("\(item.count)")
                                    .font(.headline)
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)
                        }
                    }
                }

                if weekTotal == 0 && store.state.done.isEmpty {
                    EmptyState(icon: "chart.bar",
                               title: L("Пока нет данных", "No data yet"),
                               subtitle: L("Отмечай дела галочкой — здесь появится прогресс",
                                           "Check off tasks and your progress will show up here"))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .screen()
    }

    private func statTile(value: String, caption: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.headline)
            Text(value).font(.system(size: 34, weight: .bold)).monospacedDigit()
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    /// Дней подряд, когда всё запланированное выполнено (пустые дни не прерывают серию,
    /// а сегодняшний день засчитывается, только когда всё уже сделано)
    private func currentStreak() -> Int {
        let cal = Calendar.current
        var streak = 0
        var day = cal.startOfDay(for: Date())
        for i in 0..<90 {
            let list = store.day(day)
            let done = list.filter { store.isDone($0) }.count
            if !list.isEmpty {
                if done == list.count { streak += 1 }
                else if i > 0 { break }
            }
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    private func topTasks() -> [(event: ScheduleEvent, count: Int)] {
        var counts: [UUID: Int] = [:]
        for key in store.state.done {
            if let idPart = key.split(separator: "|").first, let id = UUID(uuidString: String(idPart)) {
                counts[id, default: 0] += 1
            }
        }
        return counts
            .compactMap { id, n in store.event(id).map { (event: $0, count: n) } }
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { $0 }
    }
}
