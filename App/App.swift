import SwiftUI
import UserNotifications
import WidgetKit
import UIKit

// MARK: - Хранилище

@MainActor
final class ScheduleStore: ObservableObject {
    @Published private(set) var events: [ScheduleEvent] = []
    @Published private(set) var state = AppState()
    @Published var settings = AppSettings() {
        didSet {
            guard settings != oldValue else { return }
            Palette.colorful = settings.colorful
            SharedStorage.saveSettings(settings)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    init() {
        events = SharedStorage.load()
        state = SharedStorage.loadState()
        settings = SharedStorage.loadSettings()
        Palette.colorful = settings.colorful
    }

    /// Перечитать с диска (например, после отметки в интерактивном виджете)
    func reload() {
        events = SharedStorage.load()
        state = SharedStorage.loadState()
    }

    func event(_ id: UUID) -> ScheduleEvent? { events.first { $0.id == id } }

    // MARK: События

    func add(_ e: ScheduleEvent) {
        events.append(e)
        persist()
        NotificationManager.shared.schedule(e)
    }

    func update(_ e: ScheduleEvent) {
        guard let i = events.firstIndex(where: { $0.id == e.id }) else { return add(e) }
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

    func duplicate(_ e: ScheduleEvent) {
        var copy = e
        copy.id = UUID()
        add(copy)
    }

    func deletePastOneTime() -> Int {
        let now = Date()
        let past = events.filter { $0.repeatRule == .none && $0.date < now }
        past.forEach { NotificationManager.shared.cancel($0) }
        let ids = Set(past.map(\.id))
        events.removeAll { ids.contains($0.id) }
        persist()
        return past.count
    }

    // MARK: Отметки

    func isDone(_ o: Occurrence) -> Bool { state.done.contains(o.key) }

    func toggleDone(_ o: Occurrence) {
        if state.done.contains(o.key) { state.done.remove(o.key) } else { state.done.insert(o.key) }
        SharedStorage.saveState(state)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Пропустить одно наступление повторяющегося дела
    func skip(_ o: Occurrence) {
        state.skipped.insert(o.key)
        SharedStorage.saveState(state)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func restoreSkipped() {
        state.skipped.removeAll()
        SharedStorage.saveState(state)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Выборки

    func occurrences(from: Date, to: Date) -> [Occurrence] {
        Schedule.occurrences(of: events, from: from, to: to, limit: 5000, skipped: state.skipped)
    }

    func day(_ d: Date) -> [Occurrence] { Schedule.day(d, events: events, skipped: state.skipped) }

    func upcoming(_ now: Date, limit: Int) -> [Occurrence] {
        Schedule.upcoming(events, now: now, limit: limit, skipped: state.skipped)
    }

    // MARK: Бэкап

    func exportURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ScheduleControl-backup.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(Backup(events: events, state: state)) {
            try? data.write(to: url, options: .atomic)
        }
        return url
    }

    /// Импорт: дела с тем же id заменяются, новые добавляются
    func importBackup(from url: URL) throws -> Int {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)

        let incoming: [ScheduleEvent]
        var incomingState = AppState()
        if let backup = try? JSONDecoder().decode(Backup.self, from: data) {
            incoming = backup.events
            incomingState = backup.state
        } else {
            incoming = try JSONDecoder().decode([ScheduleEvent].self, from: data)
        }

        for e in incoming {
            if let i = events.firstIndex(where: { $0.id == e.id }) { events[i] = e } else { events.append(e) }
        }
        state.done.formUnion(incomingState.done)
        state.skipped.formUnion(incomingState.skipped)
        persist()
        SharedStorage.saveState(state)
        NotificationManager.shared.rescheduleAll(events)
        return incoming.count
    }

    private func persist() {
        SharedStorage.save(events)
        WidgetCenter.shared.reloadAllTimelines()
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
        let cal = Calendar.current
        let fire = e.date.addingTimeInterval(TimeInterval(-e.remindBefore * 60))

        let content = UNMutableNotificationContent()
        content.title = e.important ? "★ \(e.title)" : e.title
        let whenText = e.remindBefore > 0
            ? L("Через \(durationText(e.remindBefore))", "In \(durationText(e.remindBefore))")
            : L("Пора!", "It's time!")
        content.body = e.note.isEmpty ? whenText : "\(whenText) — \(e.note)"
        content.sound = .default
        if e.important { content.interruptionLevel = .timeSensitive }

        func add(_ id: String, _ comps: DateComponents, _ repeats: Bool) {
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: repeats)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }

        switch e.repeatRule {
        case .none:
            guard fire > Date() else { return }
            add(e.id.uuidString, cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire), false)
        case .daily:
            add(e.id.uuidString, cal.dateComponents([.hour, .minute], from: fire), true)
        case .weekly:
            add(e.id.uuidString, cal.dateComponents([.weekday, .hour, .minute], from: fire), true)
        case .weekdays, .weekends:
            let shift = cal.dateComponents([.day], from: cal.startOfDay(for: e.date), to: cal.startOfDay(for: fire)).day ?? 0
            let hm = cal.dateComponents([.hour, .minute], from: fire)
            for wd in e.repeatRule.weekdaySet ?? [] {
                var c = hm
                c.weekday = ((wd - 1 + shift) % 7 + 7) % 7 + 1
                add("\(e.id.uuidString)-\(wd)", c, true)
            }
        }
    }

    func cancel(_ e: ScheduleEvent) {
        let base = e.id.uuidString
        center.removePendingNotificationRequests(withIdentifiers: [base] + (1...7).map { "\(base)-\($0)" })
    }

    func rescheduleAll(_ events: [ScheduleEvent]) {
        center.removeAllPendingNotificationRequests()
        events.forEach(schedule)
    }

    func sendTest() {
        let content = UNMutableNotificationContent()
        content.title = "Schedule Control"
        content.body = L("Уведомления работают 👌", "Notifications work 👌")
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        center.add(UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: trigger))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

// MARK: - Тактильный отклик

func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}

// MARK: - App

@main
struct ScheduleApp: App {
    @StateObject private var store = ScheduleStore()

    init() { NotificationManager.shared.setup() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environment(\.locale, appLocale)
                .tint(.primary)
                .preferredColorScheme(store.settings.theme == 1 ? .light : store.settings.theme == 2 ? .dark : nil)
        }
    }
}

// MARK: - Корень: вкладки

struct EditorRequest: Identifiable {
    let id = UUID()
    let event: ScheduleEvent
    let isNew: Bool
}

struct RootView: View {
    @EnvironmentObject var store: ScheduleStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0
    @State private var editor: EditorRequest?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $tab) {
                TodayView(onEdit: edit, onAdd: add)
                    .tabItem { Label(L("Сегодня", "Today"), systemImage: "circle.lefthalf.filled") }
                    .tag(0)
                CalendarScreen(onEdit: edit, onAdd: add)
                    .tabItem { Label(L("Календарь", "Calendar"), systemImage: "calendar") }
                    .tag(1)
                AllEventsView(onEdit: edit)
                    .tabItem { Label(L("Все", "All"), systemImage: "list.bullet") }
                    .tag(2)
                StatsView()
                    .tabItem { Label(L("Статистика", "Stats"), systemImage: "chart.bar.fill") }
                    .tag(3)
                SettingsView()
                    .tabItem { Label(L("Ещё", "More"), systemImage: "ellipsis") }
                    .tag(4)
            }

            if tab <= 2 {
                AddButton { add(nil) }
                    .padding(.trailing, 20)
                    .padding(.bottom, 96)
            }
        }
        .sheet(item: $editor) { req in
            EventEditor(event: req.event, isNew: req.isNew,
                        onSave: { req.isNew ? store.add($0) : store.update($0) },
                        onDelete: { store.delete($0) })
        }
        .task {
            NotificationManager.shared.rescheduleAll(store.events)
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.reload() }
        }
    }

    private func edit(_ id: UUID) {
        if let e = store.event(id) { editor = EditorRequest(event: e, isNew: false) }
    }

    /// Новое дело: на выбранный день или на ближайший круглый час
    private func add(_ day: Date?) {
        let cal = Calendar.current
        let now = Date()
        let nextHour = cal.date(byAdding: .hour, value: 1, to: cal.dateInterval(of: .hour, for: now)?.start ?? now) ?? now
        var date = nextHour
        if let day, !cal.isDateInToday(day) {
            date = cal.date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? day
        }
        editor = EditorRequest(event: ScheduleEvent(title: "", date: date, colorIndex: store.events.count), isNew: true)
    }
}
