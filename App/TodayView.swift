import SwiftUI

struct TodayView: View {
    @EnvironmentObject var store: ScheduleStore
    let onEdit: (UUID) -> Void
    let onAdd: (Date?) -> Void

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            content(now: ctx.date)
        }
    }

    private func content(now: Date) -> some View {
        let cal = Calendar.current
        let today = store.day(now)
        let tomorrowDate = cal.date(byAdding: .day, value: 1, to: now) ?? now
        let tomorrow = store.day(tomorrowDate)
        let done = today.filter { $0.date <= now }.count
        let next = store.occurrences(from: now, to: now.addingTimeInterval(14 * 86400)).first

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Заголовок
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting(now))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(ruFormat(now, "EEEE, d MMMM").capitalized)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .padding(.top, 8)

                // Сводка дня
                summary(done: done, total: today.count, next: next, now: now)

                if store.events.isEmpty {
                    EmptyCard(icon: "calendar.badge.plus",
                              title: "Пока пусто",
                              subtitle: "Жми + внизу и добавь первое дело")
                } else {
                    SectionTitle("Сегодня")
                    if today.isEmpty {
                        EmptyCard(icon: "sun.max", title: "Свободный день", subtitle: "На сегодня ничего не запланировано")
                    } else {
                        ForEach(today) { occ in
                            OccurrenceCard(occ: occ, past: occ.date <= now)
                                .onTapGesture { onEdit(occ.eventID) }
                        }
                    }

                    if !tomorrow.isEmpty {
                        SectionTitle("Завтра")
                        ForEach(tomorrow.prefix(6)) { occ in
                            OccurrenceCard(occ: occ)
                                .onTapGesture { onEdit(occ.eventID) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
    }

    private func summary(done: Int, total: Int, next: Occurrence?, now: Date) -> some View {
        HStack(spacing: 16) {
            ZStack {
                ProgressRing(progress: total == 0 ? 0 : Double(done) / Double(total),
                             color: next?.color ?? .blue, lineWidth: 9)
                VStack(spacing: 0) {
                    Text("\(done)/\(total)")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                    Text("позади").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 78, height: 78)

            VStack(alignment: .leading, spacing: 4) {
                if let next {
                    Text("ДАЛЬШЕ").font(.caption2.weight(.bold)).foregroundStyle(next.color)
                    HStack(spacing: 6) {
                        Image(systemName: next.icon).foregroundStyle(next.color)
                        Text(next.title).font(.headline).lineLimit(1)
                    }
                    Group {
                        if Calendar.current.isDateInToday(next.date) {
                            Text("в \(timeString(next.date)) · через ") + Text(next.date, style: .relative)
                        } else {
                            Text("\(dayLabel(next.date)) в \(timeString(next.date))")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                } else {
                    Text("Ближайших дел нет").font(.headline)
                    Text("Можно отдыхать 😌").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .glass(26, tint: next?.color)
        .onTapGesture { if let next { onEdit(next.eventID) } }
    }

    private func greeting(_ d: Date) -> String {
        switch Calendar.current.component(.hour, from: d) {
        case 5..<12: return "Доброе утро"
        case 12..<18: return "Добрый день"
        case 18..<23: return "Добрый вечер"
        default: return "Доброй ночи"
        }
    }
}
