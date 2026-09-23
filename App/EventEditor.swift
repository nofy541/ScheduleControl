import SwiftUI

struct EventEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ScheduleEvent
    @State private var confirmDelete = false
    @FocusState private var titleFocused: Bool

    private let isNew: Bool
    private let onSave: (ScheduleEvent) -> Void
    private let onDelete: (ScheduleEvent) -> Void
    private let reminderOptions = [0, 5, 10, 15, 30, 60, 120, 1440]

    init(event: ScheduleEvent, isNew: Bool,
         onSave: @escaping (ScheduleEvent) -> Void,
         onDelete: @escaping (ScheduleEvent) -> Void) {
        _draft = State(initialValue: event)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // Превью карточки
                Section {
                    HStack(spacing: 14) {
                        EventIcon(icon: draft.icon, color: draft.color, size: 52)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(draft.title.isEmpty ? "Новое дело" : draft.title)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(draft.title.isEmpty ? .secondary : .primary)
                                .lineLimit(2)
                            Text(previewSubtitle).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .glass(22, tint: draft.color)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .animation(.snappy, value: draft.colorIndex)
                }

                Section {
                    TextField("Что делаем", text: $draft.title)
                        .font(.headline)
                        .focused($titleFocused)
                    TextField("Заметка (необязательно)", text: $draft.note, axis: .vertical)
                }

                Section {
                    Picker("Повтор", selection: $draft.repeatRule.animation(.snappy)) {
                        ForEach(RepeatRule.allCases) { Text($0.title).tag($0) }
                    }
                    if draft.repeatRule.needsFullDate {
                        DatePicker("Когда", selection: $draft.date)
                    } else {
                        DatePicker("Во сколько", selection: $draft.date, displayedComponents: .hourAndMinute)
                    }
                    Picker("Напомнить", selection: $draft.remindBefore) {
                        ForEach(reminderOptions, id: \.self) { m in
                            Text(reminderTitle(m)).tag(m)
                        }
                    }
                } header: {
                    Text("Когда")
                } footer: {
                    if draft.repeatRule == .weekly {
                        Text("День недели берётся из выбранной даты: \(ruFormat(draft.date, "EEEE")).")
                    }
                }

                Section("Цвет") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                        ForEach(Palette.colors.indices, id: \.self) { i in
                            let active = draft.colorIndex == i
                            Circle()
                                .fill(Palette.colors[i].gradient)
                                .frame(width: 38, height: 38)
                                .overlay {
                                    if active {
                                        Image(systemName: "checkmark")
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .padding(4)
                                .overlay(Circle().strokeBorder(Palette.colors[i], lineWidth: active ? 2.5 : 0))
                                .scaleEffect(active ? 1.05 : 1)
                                .onTapGesture {
                                    withAnimation(.snappy) { draft.colorIndex = i }
                                }
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Иконка") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(Palette.icons, id: \.self) { icon in
                            let active = draft.icon == icon
                            Image(systemName: icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(active ? Color.white : draft.color)
                                .frame(width: 42, height: 42)
                                .background(
                                    Circle().fill(active ? AnyShapeStyle(draft.color.gradient)
                                                         : AnyShapeStyle(draft.color.opacity(0.15)))
                                )
                                .onTapGesture {
                                    withAnimation(.snappy) { draft.icon = icon }
                                }
                        }
                    }
                    .padding(.vertical, 6)
                }

                if !isNew {
                    Section {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Удалить дело", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(isNew ? "Новое дело" : "Изменить")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        var e = draft
                        e.title = e.title.trimmingCharacters(in: .whitespaces)
                        onSave(e)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .confirmationDialog("Удалить «\(draft.title)»?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    onDelete(draft)
                    dismiss()
                }
            }
            .onAppear { if isNew { titleFocused = true } }
        }
    }

    private var previewSubtitle: String {
        let time = timeString(draft.date)
        switch draft.repeatRule {
        case .none: return "\(dayLabel(draft.date)), \(time)"
        case .daily: return "Каждый день в \(time)"
        case .weekdays: return "По будням в \(time)"
        case .weekends: return "По выходным в \(time)"
        case .weekly: return "\(ruFormat(draft.date, "EEEE").capitalized) в \(time)"
        }
    }

    private func reminderTitle(_ m: Int) -> String {
        switch m {
        case 0: return "В момент события"
        case 60: return "За 1 час"
        case 120: return "За 2 часа"
        case 1440: return "За день"
        default: return "За \(m) мин"
        }
    }
}
