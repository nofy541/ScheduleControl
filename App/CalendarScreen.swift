import SwiftUI

struct CalendarScreen: View {
    @EnvironmentObject var store: ScheduleStore
    let onEdit: (UUID) -> Void
    let onAdd: (Date?) -> Void

    @State private var month: Date = CalendarScreen.monthStart(Date())
    @State private var selected: Date = Calendar.current.startOfDay(for: Date())

    /// Календарь с неделей от понедельника
    private var cal: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }

    static func monthStart(_ d: Date) -> Date {
        let c = Calendar.current
        return c.date(from: c.dateComponents([.year, .month], from: d)) ?? d
    }

    var body: some View {
        let monthEnd = cal.date(byAdding: .month, value: 1, to: month) ?? month
        let occs = store.occurrences(from: month, to: monthEnd)
        let byDay = Dictionary(grouping: occs) { cal.startOfDay(for: $0.date) }
        let dayList = store.day(selected)

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Календарь")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .padding(.horizontal, 4)
                    .padding(.top, 8)

                monthCard(byDay: byDay)

                HStack {
                    SectionTitle(dayTitle(selected))
                    if !dayList.isEmpty {
                        Text("\(dayList.count)")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .glass(10)
                            .padding(.top, 8)
                    }
                }

                if dayList.isEmpty {
                    Button { onAdd(selected) } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill").font(.system(size: 30)).foregroundStyle(.blue)
                            Text("Свободный день").font(.headline).foregroundStyle(.primary)
                            Text("Нажми, чтобы добавить дело на этот день")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(22)
                    }
                    .buttonStyle(.plain)
                    .glass(24)
                } else {
                    ForEach(dayList) { occ in
                        OccurrenceCard(occ: occ, past: occ.date < Date())
                            .onTapGesture { onEdit(occ.eventID) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
    }

    // MARK: - Карточка месяца

    private func monthCard(byDay: [Date: [Occurrence]]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        let symbols = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

        return VStack(spacing: 10) {
            // Шапка: месяц и стрелки
            HStack {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left").font(.headline).frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .glass(18, interactive: true)

                Spacer()
                VStack(spacing: 0) {
                    Text(ruFormat(month, "LLLL").capitalized)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    Text(ruFormat(month, "yyyy")).font(.caption).foregroundStyle(.secondary)
                }
                .onTapGesture { goToday() }
                Spacer()

                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right").font(.headline).frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .glass(18, interactive: true)
            }

            // Дни недели
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(symbols, id: \.self) { s in
                    Text(s).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
            }

            // Сетка дней
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(gridDays().enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day, occs: byDay[day] ?? [])
                    } else {
                        Color.clear.frame(height: 46)
                    }
                }
            }

            if !cal.isDate(month, equalTo: Date(), toGranularity: .month) {
                Button("К сегодняшнему дню") { goToday() }
                    .font(.footnote.weight(.semibold))
            }
        }
        .padding(14)
        .glass(28)
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { v in
                if v.translation.width < -50 { shiftMonth(1) }
                if v.translation.width > 50 { shiftMonth(-1) }
            }
        )
    }

    private func dayCell(_ day: Date, occs: [Occurrence]) -> some View {
        let isToday = cal.isDateInToday(day)
        let isSelected = cal.isDate(day, inSameDayAs: selected)
        let colors = Array(Set(occs.map(\.colorIndex))).sorted().prefix(3)

        return VStack(spacing: 3) {
            Text("\(cal.component(.day, from: day))")
                .font(.system(.callout, design: .rounded).weight(isToday || isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? Color.white : (isToday ? Color.blue : Color.primary))
                .frame(width: 34, height: 34)
                .background {
                    if isSelected {
                        Circle().fill(Color.blue.gradient)
                    } else if isToday {
                        Circle().strokeBorder(Color.blue, lineWidth: 1.5)
                    }
                }
            HStack(spacing: 3) {
                ForEach(Array(colors), id: \.self) { i in
                    Circle().fill(Palette.color(i)).frame(width: 5, height: 5)
                }
            }
            .frame(height: 5)
        }
        .frame(height: 46)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy) { selected = day }
        }
    }

    // MARK: - Логика

    /// Дни месяца + пустые ячейки перед первым числом
    private func gridDays() -> [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let weekday = cal.component(.weekday, from: month)       // 1 = вс
        let leading = (weekday - cal.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: leading)
        for d in range {
            days.append(cal.date(byAdding: .day, value: d - 1, to: month))
        }
        return days
    }

    private func shiftMonth(_ delta: Int) {
        withAnimation(.snappy) {
            month = cal.date(byAdding: .month, value: delta, to: month) ?? month
            // Выбираем 1-е число (или сегодня, если вернулись в текущий месяц)
            selected = cal.isDate(month, equalTo: Date(), toGranularity: .month) ? cal.startOfDay(for: Date()) : month
        }
    }

    private func goToday() {
        withAnimation(.snappy) {
            month = CalendarScreen.monthStart(Date())
            selected = cal.startOfDay(for: Date())
        }
    }

    private func dayTitle(_ d: Date) -> String {
        if cal.isDateInToday(d) { return "Сегодня" }
        if cal.isDateInTomorrow(d) { return "Завтра" }
        return ruFormat(d, "EEEE, d MMMM")
    }
}
