import Foundation

// MARK: - Состояние (выполнено / пропущено) и настройки

struct AppState: Codable, Equatable {
    var done: Set<String> = []
    var skipped: Set<String> = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        done = (try? c.decode(Set<String>.self, forKey: .done)) ?? []
        skipped = (try? c.decode(Set<String>.self, forKey: .skipped)) ?? []
    }

    enum CodingKeys: String, CodingKey { case done, skipped }

    /// Убираем отметки старше 120 дней, чтобы файл не рос бесконечно
    mutating func prune(now: Date = Date()) {
        let limit = Int(now.timeIntervalSince1970) - 120 * 86400
        func fresh(_ key: String) -> Bool {
            guard let ts = key.split(separator: "|").last, let t = Int(ts) else { return false }
            return t >= limit
        }
        done = done.filter(fresh)
        skipped = skipped.filter(fresh)
    }
}

struct AppSettings: Codable, Equatable {
    var colorful = false   // цветные метки (по умолчанию ЧБ)
    var theme = 0          // 0 — как в системе, 1 — светлая, 2 — тёмная

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        colorful = (try? c.decode(Bool.self, forKey: .colorful)) ?? false
        theme = (try? c.decode(Int.self, forKey: .theme)) ?? 0
    }

    enum CodingKeys: String, CodingKey { case colorful, theme }
}

struct Backup: Codable {
    var version = 1
    var events: [ScheduleEvent]
    var state: AppState
}

// MARK: - Хранилище в общей папке App Group

enum SharedStorage {
    static let defaultGroup = "group.com.nofy.raspisanie"

    // MARK: Профиль подписи (реальное имя группы после переподписи)

    struct ProvisionInfo {
        var groups: [String] = []
        var appID: String?
        var profileName: String?
        var found = false
    }

    static let provision: ProvisionInfo = {
        var info = ProvisionInfo()
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .isoLatin1),
              let start = raw.range(of: "<?xml"),
              let end = raw.range(of: "</plist>"),
              let xml = String(raw[start.lowerBound..<end.upperBound]).data(using: .isoLatin1),
              let plist = (try? PropertyListSerialization.propertyList(from: xml, format: nil)) as? [String: Any]
        else { return info }

        info.found = true
        info.profileName = plist["Name"] as? String
        if let ent = plist["Entitlements"] as? [String: Any] {
            info.groups = ent["com.apple.security.application-groups"] as? [String] ?? []
            info.appID = ent["application-identifier"] as? String
        }
        return info
    }()

    static let resolvedGroup: String? = {
        var candidates = provision.groups.filter { $0.contains("raspisanie") }
        candidates += provision.groups
        candidates.append(defaultGroup)
        for g in candidates where FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: g) != nil {
            return g
        }
        return nil
    }()

    static var isShared: Bool { resolvedGroup != nil }

    static var groupContainer: URL? {
        resolvedGroup.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    }

    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func url(_ name: String) -> URL {
        (groupContainer ?? documents).appendingPathComponent(name)
    }

    /// Если раньше файлы лежали локально — переносим в общую папку
    private static func migrate(_ name: String) {
        guard let group = groupContainer?.appendingPathComponent(name) else { return }
        let local = documents.appendingPathComponent(name)
        let fm = FileManager.default
        if !fm.fileExists(atPath: group.path) && fm.fileExists(atPath: local.path) {
            try? fm.copyItem(at: local, to: group)
        }
    }

    private static func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        migrate(name)
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T, _ name: String) {
        if let data = try? JSONEncoder().encode(value) {
            try? data.write(to: url(name), options: .atomic)
        }
    }

    // MARK: События

    static func load() -> [ScheduleEvent] { read([ScheduleEvent].self, "events.json") ?? [] }
    static func save(_ events: [ScheduleEvent]) { write(events, "events.json") }

    // MARK: Отметки

    static func loadState() -> AppState { read(AppState.self, "state.json") ?? AppState() }
    static func saveState(_ state: AppState) {
        var s = state
        s.prune()
        write(s, "state.json")
    }

    /// Используется и приложением, и интерактивным виджетом
    static func toggleDone(_ key: String) {
        var s = loadState()
        if s.done.contains(key) { s.done.remove(key) } else { s.done.insert(key) }
        saveState(s)
    }

    // MARK: Настройки

    static func loadSettings() -> AppSettings { read(AppSettings.self, "settings.json") ?? AppSettings() }
    static func saveSettings(_ settings: AppSettings) { write(settings, "settings.json") }

    // MARK: Диагностика

    static var diagnostics: String {
        """
        Bundle ID: \(Bundle.main.bundleIdentifier ?? "—")
        App ID: \(provision.appID ?? "—")
        Profile: \(provision.found ? (provision.profileName ?? "—") : "not found")
        Groups: \(provision.groups.isEmpty ? "none" : provision.groups.joined(separator: ", "))
        Using: \(resolvedGroup ?? "no access")
        Language: \(isRU ? "ru" : "en")
        """
    }
}
