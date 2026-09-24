import SwiftUI

struct CalendarScreen: View {
    @EnvironmentObject var store: ScheduleStore
    let onEdit: (UUID) -> Void
    let onAdd: (Date?) -> Void

    @State private var month: Date = CalendarScreen.monthStart(Date())
    @State private var selected: Date = Calendar.current.startOfDay(for: Date())

    private let cal = Calendar.current

    static func monthStart(_ d: Date) -> Date {
        let c = Calendar.current
        return c.date(from: c.dateComponents([.year, .month], from: d)) ?? d
    }

    var body: some View {
        let monthEnd = cal.date(byAdding: .month, value: 1, to: month) ?? month
        let occs = store.occurrences(from: month, to: monthEnd)
        let byDay = Dictionary(grouping: occs) { cal.startOfDay(for: $0.date) }
        let dayList = store.day(selected)
        let doneCount = dayList.filter { store.isDone($0) }.count

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(title: cap(fmt(month, "LLLL")), subtitle: fmt(month, "yyyy"))

                monthGrid(byDay: byDay)

                SectionTitle(dayTitle(selected), trailing: dayList.isEmpty ? nil : "\(doneCount)/\(dayList.count)")

                if dayList.isEmpty {
                    Button { onAdd(selected) } label: {
                        HStack {
                            Image(systemName: "plus")
                            Text(L("Добавить дело на этот день", "Add a task for this day"))
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    RowGroup {
                        ForEach(Array(dayList.enumerated()), id: \.element.id) { i, occ in
                            if i > 0 { Hairline() }
                            OccurrenceRow(occ: occ, done: store.isDone(occ), showCheck: true) {
                                withAnimation(.snappy) { store.toggleDone(occ) }
                            }
                            .onTapGesture { onEdit(occ.eventID) }
                            .contextMenu {
                                if occ.repeating {
                                    Button { withAnimation { store.skip(occ) } } label: {
                                        Label(L("Пропустить этот раз", "Skip this time"), systemImage: "forward")
                                    }
                                }
                                Button { onEdit(occ.eventID) } label: { Label(L("Изменить", "Edit"), systemImage: "pencil") }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
        .screen()
    }

    // MARK: - Сетка месяца

    private func monthGrid(byDay: [Date: [Occurrence]]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

        return VStack(spacing: 8) {
            HStack {
                navButton("chevron.left") { shiftMonth(-1) }
                Spacer()
                if !cal.isDate(month, equalTo: Date(), toGranularity: .month) {
                    Button(L("Сегодня", "Today")) { goToday() }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.plain)
                }
                Spacer()
                navButton("chevron.right") { shiftMonth(1) }
            }

            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(orderedWeekdaySymbols().enumerated()), id: \.offset) { _, s in
                    Text(s)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(height: 20)
                }
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(gridDays().enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day, occs: byDay[day] ?? [])
                    } else {
                        Color.clear.frame(height: 48)
                    }
                }
            }
        }
        .card(24, padding: 14)
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { v in
                if v.translation.width < -50 { shiftMonth(1) }
                if v.translation.width > 50 { shiftMonth(-1) }
            }
        )
    }

    private func navButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: { haptic(); action() }) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private func dayCell(_ day: Date, occs: [Occurrence]) -> some View {
        let isToday = cal.isDateInToday(day)
        let isSelected = cal.isDate(day, inSameDayAs: selected)
        let allDone = !occs.isEmpty && occs.allSatisfy { store.isDone($0) }
        let dots = min(occs.count, 3)
        let colorful = Palette.colorful
        let dotColors = Array(Set(occs.map(\.colorIndex))).sorted().prefix(3)

        return VStack(spacing: 4) {
            Text("\(cal.component(.day, from: day))")
                .font(.system(size: 16, weight: isToday || isSelected ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : Color.primary)
                .frame(width: 34, height: 34)
                .background {
                    if isSelected {
                        Circle().fill(Color.primary)
                    } else if isToday {
                        Circle().strokeBorder(Color.primary, lineWidth: 1.2)
                    }
                }
            HStack(spacing: 3) {
                if allDone {
                    Image(systemName: "checkmark").font(.system(size: 7, weight: .black))
                } else if colorful {
                    ForEach(Array(dotColors), id: \.self) { i in
                        Circle().fill(Palette.raw(i)).frame(width: 4, height: 4)
                    }
                } else {
                    ForEach(0..<dots, id: \.self) { _ in
                        Circle().fill(Color.primary).frame(width: 4, height: 4)
                    }
                }
            }
            .frame(height: 6)
        }
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            haptic()
            withAnimation(.snappy) { selected = day }
        }
    }

    // MARK: - Логика

    private func gridDays() -> [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let weekday = cal.component(.weekday, from: month)
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
        if cal.isDateInToday(d) { return L("Сегодня", "Today") }
        if cal.isDateInTomorrow(d) { return L("Завтра", "Tomorrow") }
        return fmt(d, "EEEEdMMMM")
    }
}
