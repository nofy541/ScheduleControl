import Foundation

/// Хранилище в общей папке App Group.
///
/// Фикс оранжевой плашки: при переподписи (Sideloadly и т.п.) имя группы
/// может поменяться, например получить суффикс с ID команды. Поэтому мы не
/// хардкодим имя, а читаем реальный список групп из профиля подписи
/// (embedded.mobileprovision), который лежит внутри приложения и внутри виджета.
enum SharedStorage {
    static let defaultGroup = "group.com.nofy.raspisanie"
    private static let fileName = "events.json"

    // MARK: Профиль подписи

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

    /// Реально доступная группа (или nil, если доступа нет)
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

    static var localURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
    }

    static var fileURL: URL {
        groupContainer?.appendingPathComponent(fileName) ?? localURL
    }

    // MARK: Чтение / запись

    /// Если раньше данные лежали локально (когда группа не работала) — переносим в общую папку
    private static func migrateIfNeeded() {
        guard let group = groupContainer?.appendingPathComponent(fileName) else { return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: group.path) && fm.fileExists(atPath: localURL.path) {
            try? fm.copyItem(at: localURL, to: group)
        }
    }

    static func load() -> [ScheduleEvent] {
        migrateIfNeeded()
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([ScheduleEvent].self, from: data) else { return [] }
        return list
    }

    static func save(_ events: [ScheduleEvent]) {
        if let data = try? JSONEncoder().encode(events) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: Диагностика (экран «Ещё»)

    static var diagnostics: String {
        """
        Bundle ID: \(Bundle.main.bundleIdentifier ?? "—")
        App ID: \(provision.appID ?? "—")
        Профиль найден: \(provision.found ? "да" : "нет")
        Профиль: \(provision.profileName ?? "—")
        Группы в профиле: \(provision.groups.isEmpty ? "нет" : provision.groups.joined(separator: ", "))
        Используется: \(resolvedGroup ?? "нет доступа")
        """
    }
}
