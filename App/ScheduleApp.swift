import SwiftUI
import UserNotifications
import WidgetKit

// MARK: - Хранилище

@MainActor
final class ScheduleStore: ObservableObject {
    @Published private(set) var events: [ScheduleEvent] = []

    init() { events = SharedStorage.load() }

    func add(_ e: ScheduleEvent) {
        events.append(e)
        persist()
        NotificationManager.shared.schedule(e)
    }

    func update(_ e: ScheduleEvent) {
        guard let i = events.firstIndex(where: { $0.id == e.id }) else { return }
        events[i] = e
        persist()
        NotificationManager.shared.cancel(e)
        NotificationManager.shared.schedule(e)
    }

    func delete(_ e: ScheduleEvent) {
        events.removeAll { $0.id == e.id }
        persist()
        NotificationManager.shared.cancel(e)
    }

    private func persist() {
        SharedStorage.save(events)
        WidgetCenter.shared.reloadAllTimelines() // виджеты обновятся сразу
    }
}

// MARK: - Уведомления

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    func setup() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func schedule(_ e: ScheduleEvent) {
        let fireDate = e.date.addingTimeInterval(TimeInterval(-e.remindBefore * 60))
        let cal = Calendar.current
        let comps: DateComponents

        switch e.repeatRule {
        case .none:
            guard fireDate > Date() else { return }
            comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        case .daily:
            comps = cal.dateComponents([.hour, .minute], from: fireDate)
        case .weekly:
            comps = cal.dateComponents([.weekday, .hour, .minute], from: fireDate)
        }

        let content = UNMutableNotificationContent()
        content.title = e.title
        let whenText = e.remindBefore > 0 ? "Через \(e.remindBefore) мин" : "Пора!"
        content.body = e.note.isEmpty ? whenText : "\(whenText) — \(e.note)"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: e.repeatRule != .none)
        center.add(UNNotificationRequest(identifier: e.id.uuidString, content: content, trigger: trigger))
    }

    func cancel(_ e: ScheduleEvent) {
        center.removePendingNotificationRequests(withIdentifiers: [e.id.uuidString])
    }

    func rescheduleAll(_ events: [ScheduleEvent]) {
        center.removeAllPendingNotificationRequests()
        events.forEach(schedule)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

// MARK: - App

@main
struct ScheduleApp: App {
    @StateObject private var store = ScheduleStore()

    init() { NotificationManager.shared.setup() }

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store)
        }
    }
}

// MARK: - Главный экран

struct ContentView: View {
    @EnvironmentObject var store: ScheduleStore
    @State private var showAdd = false
    @State private var editing: ScheduleEvent?

    private var repeating: [ScheduleEvent] {
        store.events.filter { $0.repeatRule != .none }.sorted { timeKey($0) < timeKey($1) }
    }
    private var oneTime: [ScheduleEvent] {
        store.events.filter { $0.repeatRule == .none }.sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                if !SharedStorage.isShared {
                    Section {
                        Label("Виджеты не видят данные: нет доступа к App Group. Смотри README, раздел «Виджет пустой».",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                if store.events.isEmpty {
                    ContentUnavailableView("Пусто", systemImage: "calendar",
                                           description: Text("Жми + и добавь первое дело"))
                }
                if !repeating.isEmpty {
                    Section("Повторяющиеся") {
                        ForEach(repeating) { row($0) }
                            .onDelete { idx in idx.map { repeating[$0] }.forEach(store.delete) }
                    }
                }
                if !oneTime.isEmpty {
                    Section("Разовые") {
                        ForEach(oneTime) { row($0) }
                            .onDelete { idx in idx.map { oneTime[$0] }.forEach(store.delete) }
                    }
                }
            }
            .navigationTitle("Расписание")
            .toolbar {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
            .sheet(isPresented: $showAdd) {
                EventEditor(event: nil) { store.add($0) }
            }
            .sheet(item: $editing) { e in
                EventEditor(event: e) { store.update($0) }
            }
            .task {
                NotificationManager.shared.rescheduleAll(store.events)
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    private func row(_ e: ScheduleEvent) -> some View {
        Button { editing = e } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.title).font(.headline)
                    Text(subtitle(e)).font(.subheadline).foregroundStyle(.secondary)
                    if !e.note.isEmpty {
                        Text(e.note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if e.remindBefore > 0 {
                    Label("\(e.remindBefore) мин", systemImage: "bell")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .opacity(e.repeatRule == .none && e.date < Date() ? 0.4 : 1)
        }
        .foregroundStyle(.primary)
    }

    private func subtitle(_ e: ScheduleEvent) -> String {
        let time = timeString(e.date)
        switch e.repeatRule {
        case .none:
            return e.date.formatted(.dateTime.day().month(.wide).hour().minute().locale(ru))
        case .daily:
            return "Каждый день в \(time)"
        case .weekly:
            let day = e.date.formatted(.dateTime.weekday(.wide).locale(ru))
            return "Каждую неделю: \(day), \(time)"
        }
    }

    private func timeKey(_ e: ScheduleEvent) -> Int {
        let c = Calendar.current.dateComponents([.weekday, .hour, .minute], from: e.date)
        let day = e.repeatRule == .weekly ? (c.weekday ?? 0) : 0
        return day * 10000 + (c.hour ?? 0) * 100 + (c.minute ?? 0)
    }
}

// MARK: - Добавление / редактирование

struct EventEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ScheduleEvent
    private let isNew: Bool
    private let onSave: (ScheduleEvent) -> Void
    private let reminderOptions = [0, 5, 10, 15, 30, 60, 120]

    init(event: ScheduleEvent?, onSave: @escaping (ScheduleEvent) -> Void) {
        _draft = State(initialValue: event ?? ScheduleEvent(title: "", date: Date().addingTimeInterval(3600)))
        isNew = event == nil
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Что делаем", text: $draft.title)
                    TextField("Заметка (необязательно)", text: $draft.note, axis: .vertical)
                }
                Section {
                    DatePicker("Когда", selection: $draft.date)
                    Picker("Повтор", selection: $draft.repeatRule) {
                        ForEach(RepeatRule.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Напомнить", selection: $draft.remindBefore) {
                        ForEach(reminderOptions, id: \.self) { m in
                            Text(m == 0 ? "В момент события" : "За \(m) мин").tag(m)
                        }
                    }
                }
            }
            .environment(\.locale, ru)
            .navigationTitle(isNew ? "Новое дело" : "Изменить")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
