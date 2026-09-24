import SwiftUI

struct EventEditor: View {
    @EnvironmentObject var store: ScheduleStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ScheduleEvent
    @State private var confirmDelete = false
    @FocusState private var titleFocused: Bool

    private let isNew: Bool
    private let onSave: (ScheduleEvent) -> Void
    private let onDelete: (ScheduleEvent) -> Void
    private let reminderOptions = [0, 5, 10, 15, 30, 60, 120, 1440]
    private let durationOptions = [0, 15, 30, 45, 60, 90, 120, 180, 240]

    init(event: ScheduleEvent, isNew: Bool,
         onSave: @escaping (ScheduleEvent) -> Void,
         onDelete: @escaping (ScheduleEvent) -> Void) {
        _draft = State(initialValue: event)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var canSave: Bool { !draft.title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("Что делаем", "What's the plan"), text: $draft.title)
                        .font(.title3.weight(.semibold))
                        .focused($titleFocused)
                    TextField(L("Заметка", "Note"), text: $draft.note, axis: .vertical)
                        .foregroundStyle(.secondary)
                    Toggle(isOn: $draft.important.animation(.snappy)) {
                        Label(L("Важное", "Important"), systemImage: draft.important ? "star.fill" : "star")
                    }
                    .tint(.primary)
                }

                Section {
                    Picker(L("Повтор", "Repeat"), selection: $draft.repeatRule.animation(.snappy)) {
                        ForEach(RepeatRule.allCases) { Text($0.title).tag($0) }
                    }
                    if draft.repeatRule.needsFullDate {
                        DatePicker(L("Когда", "When"), selection: $draft.date)
                    } else {
                        DatePicker(L("Во сколько", "At"), selection: $draft.date, displayedComponents: .hourAndMinute)
                    }
                    Picker(L("Длительность", "Duration"), selection: $draft.duration) {
                        ForEach(durationOptions, id: \.self) { m in
                            Text(m == 0 ? L("Без длительности", "None") : durationText(m)).tag(m)
                        }
                    }
                    Picker(L("Напомнить", "Remind"), selection: $draft.remindBefore) {
                        ForEach(reminderOptions, id: \.self) { m in
                            Text(reminderTitle(m)).tag(m)
                        }
                    }
                } footer: {
                    if draft.repeatRule == .weekly {
                        Text(L("Каждую неделю: \(fmt(draft.date, "EEEE"))", "Every week on \(fmt(draft.date, "EEEE"))"))
                    }
                }

                Section(L("Иконка", "Icon")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(Palette.icons, id: \.self) { icon in
                            let active = draft.icon == icon
                            Image(systemName: icon)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(active ? Color(uiColor: .systemBackground) : Color.primary)
                                .frame(width: 42, height: 42)
                                .background(Circle().fill(active ? Color.primary : Color.primary.opacity(0.06)))
                                .onTapGesture {
                                    haptic()
                                    withAnimation(.snappy(duration: 0.2)) { draft.icon = icon }
                                }
                        }
                    }
                    .padding(.vertical, 6)
                }

                if store.settings.colorful {
                    Section(L("Цвет", "Color")) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                            ForEach(Palette.colors.indices, id: \.self) { i in
                                let active = draft.colorIndex % Palette.colors.count == i
                                Circle()
                                    .fill(Palette.colors[i])
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        if active {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(Color.primary, lineWidth: active ? 1.5 : 0))
                                    .onTapGesture {
                                        haptic()
                                        withAnimation(.snappy(duration: 0.2)) { draft.colorIndex = i }
                                    }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                if !isNew {
                    Section {
                        Button {
                            var copy = draft
                            copy.id = UUID()
                            onSave(draft)
                            store.add(copy)
                            dismiss()
                        } label: {
                            Label(L("Сохранить и дублировать", "Save & duplicate"), systemImage: "plus.square.on.square")
                        }
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label(L("Удалить", "Delete"), systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isNew ? L("Новое дело", "New task") : L("Дело", "Task"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Отмена", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Готово", "Done")) {
                        var e = draft
                        e.title = e.title.trimmingCharacters(in: .whitespaces)
                        haptic(.medium)
                        onSave(e)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .confirmationDialog(L("Удалить «\(draft.title)»?", "Delete “\(draft.title)”?"),
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(L("Удалить", "Delete"), role: .destructive) {
                    onDelete(draft)
                    dismiss()
                }
            }
            .onAppear { if isNew { titleFocused = true } }
        }
        .tint(.primary)
    }

    private func reminderTitle(_ m: Int) -> String {
        switch m {
        case 0: return L("В момент события", "At time of event")
        case 1440: return L("За день", "1 day before")
        default: return L("За \(durationText(m))", "\(durationText(m)) before")
        }
    }
}
