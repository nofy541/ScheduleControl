import SwiftUI

struct AllEventsView: View {
    @EnvironmentObject var store: ScheduleStore
    let onEdit: (UUID) -> Void

    enum Filter: CaseIterable { case all, important, repeating, once, past }

    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var toDelete: ScheduleEvent?

    var body: some View {
        let now = Date()
        let base = store.events.filter { e in
            search.isEmpty
            || e.title.localizedCaseInsensitiveContains(search)
            || e.note.localizedCaseInsensitiveContains(search)
        }
        let repeating = base.filter { $0.repeatRule != .none }.sorted { timeKey($0) < timeKey($1) }
        let upcoming = base.filter { $0.repeatRule == .none && $0.date >= now }.sorted { $0.date < $1.date }
        let past = base.filter { $0.repeatRule == .none && $0.date < now }.sorted { $0.date > $1.date }
        let important = base.filter(\.important).sorted { $0.date < $1.date }

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(title: L("Все дела", "All tasks"),
                             subtitle: "\(store.events.count) " + plural(store.events.count, "дело", "дела", "дел", "task", "tasks"))

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L("Поиск", "Search"), text: $search)
                        .textInputAutocapitalization(.never)
                    if !search.isEmpty {
                        Button { search = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card(16, padding: 12)

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Filter.allCases, id: \.self) { f in
                            Chip(title: title(f), active: filter == f) { filter = f }
                        }
                    }
                }
                .scrollIndicators(.hidden)

                if store.events.isEmpty {
                    EmptyState(icon: "tray", title: L("Дел пока нет", "No tasks yet"),
                               subtitle: L("Нажми + и добавь первое", "Tap + to add one"))
                }

                switch filter {
                case .all:
                    group(L("Повторяющиеся", "Repeating"), repeating)
                    group(L("Предстоящие", "Upcoming"), upcoming)
                    group(L("Прошедшие", "Past"), past, faded: true)
                case .important:
                    group(L("Важные", "Important"), important)
                case .repeating:
                    group(L("Повторяющиеся", "Repeating"), repeating)
                case .once:
                    group(L("Предстоящие", "Upcoming"), upcoming)
                case .past:
                    group(L("Прошедшие", "Past"), past, faded: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.immediately)
        .screen()
        .confirmationDialog(L("Удалить «\(toDelete?.title ?? "")»?", "Delete “\(toDelete?.title ?? "")”?"),
                            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible) {
            Button(L("Удалить", "Delete"), role: .destructive) {
                if let e = toDelete { withAnimation { store.delete(e) } }
                toDelete = nil
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [ScheduleEvent], faded: Bool = false) -> some View {
        if !items.isEmpty {
            SectionTitle(title, trailing: "\(items.count)")
            RowGroup {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, e in
                    if i > 0 { Hairline() }
                    row(e).opacity(faded ? 0.45 : 1)
                }
            }
        }
    }

    private func row(_ e: ScheduleEvent) -> some View {
        HStack(spacing: 14) {
            EventIcon(icon: e.icon, colorIndex: e.colorIndex, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(e.title).font(.body.weight(.medium)).lineLimit(1)
                    if e.important { Image(systemName: "star.fill").font(.caption2) }
                }
                Text(subtitle(e))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if e.remindBefore > 0 {
                Image(systemName: "bell").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .onTapGesture { onEdit(e.id) }
        .contextMenu {
            Button { onEdit(e.id) } label: { Label(L("Изменить", "Edit"), systemImage: "pencil") }
            Button { store.duplicate(e) } label: { Label(L("Дублировать", "Duplicate"), systemImage: "plus.square.on.square") }
            Button(role: .destructive) { toDelete = e } label: { Label(L("Удалить", "Delete"), systemImage: "trash") }
        }
    }

    private func title(_ f: Filter) -> String {
        switch f {
        case .all: return L("Все", "All")
        case .important: return L("★ Важные", "★ Important")
        case .repeating: return L("Повторяющиеся", "Repeating")
        case .once: return L("Разовые", "One-time")
        case .past: return L("Прошедшие", "Past")
        }
    }

    private func subtitle(_ e: ScheduleEvent) -> String {
        let time = timeString(e.date)
        let dur = e.duration > 0 ? " · \(durationText(e.duration))" : ""
        switch e.repeatRule {
        case .none: return "\(fmt(e.date, "EEEdMMM")), \(time)\(dur)"
        case .daily: return L("Каждый день в \(time)", "Every day at \(time)") + dur
        case .weekdays: return L("По будням в \(time)", "Weekdays at \(time)") + dur
        case .weekends: return L("По выходным в \(time)", "Weekends at \(time)") + dur
        case .weekly: return "\(cap(fmt(e.date, "EEEE"))), \(time)\(dur)"
        }
    }

    private func timeKey(_ e: ScheduleEvent) -> Int {
        let c = Calendar.current.dateComponents([.weekday, .hour, .minute], from: e.date)
        let day = e.repeatRule == .weekly ? (c.weekday ?? 0) : 0
        return day * 10000 + (c.hour ?? 0) * 100 + (c.minute ?? 0)
    }
}
