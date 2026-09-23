import SwiftUI

struct AllEventsView: View {
    @EnvironmentObject var store: ScheduleStore
    let onEdit: (UUID) -> Void

    @State private var search = ""
    @State private var colorFilter: Int?
    @State private var toDelete: ScheduleEvent?

    private var filtered: [ScheduleEvent] {
        store.events.filter { e in
            (search.isEmpty || e.title.localizedCaseInsensitiveContains(search) || e.note.localizedCaseInsensitiveContains(search))
            && (colorFilter == nil || e.colorIndex == colorFilter)
        }
    }

    var body: some View {
        let now = Date()
        let repeating = filtered.filter { $0.repeatRule != .none }.sorted { timeKey($0) < timeKey($1) }
        let upcoming = filtered.filter { $0.repeatRule == .none && $0.date >= now }.sorted { $0.date < $1.date }
        let past = filtered.filter { $0.repeatRule == .none && $0.date < now }.sorted { $0.date > $1.date }
        let usedColors = Array(Set(store.events.map(\.colorIndex))).sorted()

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Все дела")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .padding(.horizontal, 4)
                    .padding(.top, 8)

                // Поиск
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Поиск", text: $search)
                        .textInputAutocapitalization(.never)
                    if !search.isEmpty {
                        Button { search = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .glass(22)

                // Фильтр по цвету
                if usedColors.count > 1 {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            chip(title: "Все", color: nil, active: colorFilter == nil) { colorFilter = nil }
                            ForEach(usedColors, id: \.self) { i in
                                chip(title: nil, color: Palette.color(i), active: colorFilter == i) {
                                    colorFilter = colorFilter == i ? nil : i
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)
                }

                if store.events.isEmpty {
                    EmptyCard(icon: "tray", title: "Дел пока нет", subtitle: "Жми + и добавь первое")
                } else if filtered.isEmpty {
                    EmptyCard(icon: "magnifyingglass", title: "Ничего не нашлось", subtitle: "Попробуй другой запрос")
                }

                if !repeating.isEmpty {
                    SectionTitle("Повторяющиеся")
                    ForEach(repeating) { row($0) }
                }
                if !upcoming.isEmpty {
                    SectionTitle("Предстоящие")
                    ForEach(upcoming) { row($0) }
                }
                if !past.isEmpty {
                    SectionTitle("Прошедшие")
                    ForEach(past) { row($0).opacity(0.55) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .screenBackground()
        .confirmationDialog("Удалить «\(toDelete?.title ?? "")»?",
                            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                if let e = toDelete { withAnimation { store.delete(e) } }
                toDelete = nil
            }
        }
    }

    private func row(_ e: ScheduleEvent) -> some View {
        HStack(spacing: 12) {
            EventIcon(icon: e.icon, color: e.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title).font(.body.weight(.semibold)).lineLimit(1)
                Text(subtitle(e)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if e.remindBefore > 0 {
                Label("\(e.remindBefore)", systemImage: "bell.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .glass(20, tint: e.color)
        .contentShape(Rectangle())
        .onTapGesture { onEdit(e.id) }
        .contextMenu {
            Button { onEdit(e.id) } label: { Label("Изменить", systemImage: "pencil") }
            Button { store.duplicate(e) } label: { Label("Дублировать", systemImage: "plus.square.on.square") }
            Button(role: .destructive) { toDelete = e } label: { Label("Удалить", systemImage: "trash") }
        }
    }

    private func chip(title: String?, color: Color?, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let color { Circle().fill(color).frame(width: 14, height: 14) }
                if let title { Text(title).font(.subheadline.weight(.semibold)) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(Capsule().strokeBorder(Color.primary.opacity(active ? 0.5 : 0), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .glass(18, tint: active ? (color ?? .blue) : nil, interactive: true)
    }

    private func subtitle(_ e: ScheduleEvent) -> String {
        let time = timeString(e.date)
        switch e.repeatRule {
        case .none:
            return ruFormat(e.date, "d MMMM, EEEE") + " · \(time)"
        case .daily:
            return "Каждый день в \(time)"
        case .weekdays:
            return "По будням в \(time)"
        case .weekends:
            return "По выходным в \(time)"
        case .weekly:
            return "Каждую неделю: \(ruFormat(e.date, "EEEE")), \(time)"
        }
    }

    private func timeKey(_ e: ScheduleEvent) -> Int {
        let c = Calendar.current.dateComponents([.weekday, .hour, .minute], from: e.date)
        let day = e.repeatRule == .weekly ? (c.weekday ?? 0) : 0
        return day * 10000 + (c.hour ?? 0) * 100 + (c.minute ?? 0)
    }
}
