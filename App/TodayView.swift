import SwiftUI

struct TodayView: View {
    @EnvironmentObject var store: ScheduleStore
    let onEdit: (UUID) -> Void
    let onAdd: (Date?) -> Void

    @State private var quickText = ""
    @FocusState private var quickFocused: Bool

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            content(now: ctx.date)
        }
    }

    private func content(now: Date) -> some View {
        let cal = Calendar.current
        let today = store.day(now)
        let tomorrow = store.day(cal.date(byAdding: .day, value: 1, to: now) ?? now)
        let done = today.filter { store.isDone($0) }.count
        let current = today.first { $0.isNow(now) }
        let next = store.upcoming(now, limit: 5).first { $0.date > now }

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(title: greeting(now), subtitle: fmt(now, "EEEEdMMMM"))

                quickAdd(now: now)

                focusCard(current: current, next: next, now: now)

                if !today.isEmpty {
                    HStack(spacing: 12) {
                        Text("\(done)/\(today.count)")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        ProgressBar(value: Double(done) / Double(max(today.count, 1)))
                        Text(done == today.count ? L("Всё сделано", "All done") : L("сделано", "done"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                }

                if store.events.isEmpty {
                    EmptyState(icon: "square.and.pencil",
                               title: L("Пока пусто", "Nothing yet"),
                               subtitle: L("Напиши дело в строке выше или нажми +", "Type a task above or tap +"))
                } else {
                    SectionTitle(L("Сегодня", "Today"), trailing: today.isEmpty ? nil : "\(today.count)")
                    if today.isEmpty {
                        EmptyState(icon: "sun.max", title: L("Свободный день", "Free day"),
                                   subtitle: L("На сегодня ничего не запланировано", "Nothing planned for today"))
                    } else {
                        list(today, now: now, checks: true)
                    }

                    if !tomorrow.isEmpty {
                        SectionTitle(L("Завтра", "Tomorrow"), trailing: "\(tomorrow.count)")
                        list(Array(tomorrow.prefix(6)), now: now, checks: false)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.immediately)
        .screen()
    }

    // MARK: - Список с галочками и контекстным меню

    private func list(_ items: [Occurrence], now: Date, checks: Bool) -> some View {
        RowGroup {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, occ in
                if i > 0 { Hairline() }
                OccurrenceRow(occ: occ, done: store.isDone(occ), showCheck: checks, now: now) {
                    withAnimation(.snappy) { store.toggleDone(occ) }
                }
                .onTapGesture { onEdit(occ.eventID) }
                .contextMenu { menu(for: occ) }
            }
        }
    }

    @ViewBuilder
    private func menu(for occ: Occurrence) -> some View {
        Button { store.toggleDone(occ) } label: {
            Label(store.isDone(occ) ? L("Снять отметку", "Mark as not done") : L("Выполнено", "Mark as done"),
                  systemImage: "checkmark.circle")
        }
        Button { onEdit(occ.eventID) } label: { Label(L("Изменить", "Edit"), systemImage: "pencil") }
        if occ.repeating {
            Button { withAnimation { store.skip(occ) } } label: {
                Label(L("Пропустить этот раз", "Skip this time"), systemImage: "forward")
            }
        }
        if let e = store.event(occ.eventID) {
            Button(role: .destructive) { withAnimation { store.delete(e) } } label: {
                Label(L("Удалить", "Delete"), systemImage: "trash")
            }
        }
    }

    // MARK: - Быстрое добавление

    private func quickAdd(now: Date) -> some View {
        let parsed = QuickParser.parse(quickText, now: now)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "text.cursor").foregroundStyle(.secondary)
                TextField(L("Зал завтра в 18", "Gym tomorrow at 6pm"), text: $quickText)
                    .focused($quickFocused)
                    .submitLabel(.done)
                    .onSubmit { commit(parsed) }
                if parsed != nil {
                    Button { commit(parsed) } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            if let p = parsed, quickFocused || !quickText.isEmpty {
                HStack(spacing: 6) {
                    Text(p.title).fontWeight(.medium)
                    Text("·")
                    Text("\(dayLabel(p.date)), \(timeString(p.date))")
                    if p.repeatRule != .none {
                        Text("·")
                        Text(p.repeatRule.title)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .card(18, padding: 14)
        .animation(.snappy(duration: 0.2), value: parsed != nil)
    }

    private func commit(_ parsed: QuickParse?) {
        guard let p = parsed else { return }
        haptic(.medium)
        store.add(ScheduleEvent(title: p.title, date: p.date, repeatRule: p.repeatRule, colorIndex: store.events.count))
        quickText = ""
        quickFocused = false
    }

    // MARK: - Карточка «Сейчас / Дальше»

    @ViewBuilder
    private func focusCard(current: Occurrence?, next: Occurrence?, now: Date) -> some View {
        if let current {
            let total = current.end.timeIntervalSince(current.date)
            let passed = now.timeIntervalSince(current.date)
            VStack(alignment: .leading, spacing: 10) {
                Text(L("СЕЙЧАС", "NOW")).font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    EventIcon(icon: current.icon, colorIndex: current.colorIndex, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current.title).font(.title3.weight(.semibold)).lineLimit(2)
                        Text(L("до \(timeString(current.end))", "until \(timeString(current.end))"))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                ProgressBar(value: passed / max(total, 1), height: 6)
                if let next {
                    Text(L("Потом: \(next.title) в \(timeString(next.date))", "Next: \(next.title) at \(timeString(next.date))"))
                        .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .card()
            .onTapGesture { onEdit(current.eventID) }
        } else if let next {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("ДАЛЬШЕ", "NEXT")).font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
                    Text(next.title).font(.title3.weight(.semibold)).lineLimit(2)
                    Group {
                        if Calendar.current.isDateInToday(next.date) {
                            Text(L("через ", "in ")) + Text(next.date, style: .relative)
                        } else {
                            Text(dayLabel(next.date))
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text(timeString(next.date))
                    .font(.system(size: 30, weight: .semibold))
                    .monospacedDigit()
            }
            .card()
            .onTapGesture { onEdit(next.eventID) }
        }
    }

    private func greeting(_ d: Date) -> String {
        switch Calendar.current.component(.hour, from: d) {
        case 5..<12: return L("Доброе утро", "Good morning")
        case 12..<18: return L("Добрый день", "Good afternoon")
        case 18..<23: return L("Добрый вечер", "Good evening")
        default: return L("Доброй ночи", "Good night")
        }
    }
}
