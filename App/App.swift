import SwiftUI
import UserNotifications
import WidgetKit

// MARK: - Хранилище

@MainActor
final class ScheduleStore: ObservableObject {
    @Published private(set) var events: [ScheduleEvent] = []

    init() { events = SharedStorage.load() }

    func event(_ id: UUID) -> ScheduleEvent? { events.first { $0.id == id } }

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
        copy.title = e.title + " (копия)"
        add(copy)
    }

    func deletePastOneTime() -> Int {
        let now = Date()
        let past = events.filter { $0.repeatRule == .none && $0.date < now }
        past.forEach { NotificationManager.shared.cancel($0) }
        events.removeAll { e in past.contains { $0.id == e.id } }
        persist()
        return past.count
    }

    func occurrences(from: Date, to: Date) -> [Occurrence] {
        Schedule.occurrences(of: events, from: from, to: to, limit: 3000)
    }

    func day(_ d: Date) -> [Occurrence] { Schedule.day(d, events: events) }

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
        content.title = e.title
        let whenText = e.remindBefore > 0 ? "Через \(e.remindBefore) мин" : "Пора!"
        content.body = e.note.isEmpty ? whenText : "\(whenText) — \(e.note)"
        content.sound = .default

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
            // Напоминание «за N минут» может перескочить на предыдущий день
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
        content.body = "Уведомления работают 👌"
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

// MARK: - App

@main
struct ScheduleApp: App {
    @StateObject private var store = ScheduleStore()

    init() { NotificationManager.shared.setup() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environment(\.locale, ru)
        }
    }
}

// MARK: - Корневой экран с вкладками

struct EditorRequest: Identifiable {
    let id = UUID()
    let event: ScheduleEvent
    let isNew: Bool
}

struct RootView: View {
    @EnvironmentObject var store: ScheduleStore
    @State private var tab = 0
    @State private var editor: EditorRequest?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $tab) {
                TodayView(onEdit: edit, onAdd: add)
                    .tabItem { Label("Сегодня", systemImage: "sun.max.fill") }
                    .tag(0)
                CalendarScreen(onEdit: edit, onAdd: add)
                    .tabItem { Label("Календарь", systemImage: "calendar") }
                    .tag(1)
                AllEventsView(onEdit: edit)
                    .tabItem { Label("Все дела", systemImage: "list.bullet") }
                    .tag(2)
                SettingsView()
                    .tabItem { Label("Ещё", systemImage: "gearshape.fill") }
                    .tag(3)
            }

            if tab != 3 {
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
    }

    private func edit(_ id: UUID) {
        if let e = store.event(id) { editor = EditorRequest(event: e, isNew: false) }
    }

    /// Новое дело; если передан день — на этот день в ближайший круглый час
    private func add(_ day: Date?) {
        let cal = Calendar.current
        let now = Date()
        let nextHour = cal.date(byAdding: .hour, value: 1, to: cal.dateInterval(of: .hour, for: now)?.start ?? now) ?? now
        var date = nextHour
        if let day {
            let hm = cal.dateComponents([.hour, .minute], from: cal.isDateInToday(day) ? nextHour : cal.date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? day)
            date = cal.date(bySettingHour: hm.hour ?? 10, minute: hm.minute ?? 0, second: 0, of: day) ?? day
        }
        let color = store.events.count % Palette.colors.count
        editor = EditorRequest(event: ScheduleEvent(title: "", date: date, colorIndex: color), isNew: true)
    }
}
