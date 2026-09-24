import SwiftUI
import UIKit
import UserNotifications
import WidgetKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: ScheduleStore
    @Environment(\.openURL) private var openURL

    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    @State private var showDiagnostics = false
    @State private var confirmCleanup = false
    @State private var importing = false
    @State private var toast: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(title: L("Ещё", "More"), subtitle: "Schedule Control")

                // Оформление
                SectionTitle(L("Оформление", "Appearance"))
                VStack(alignment: .leading, spacing: 14) {
                    Text(L("Тема", "Theme")).font(.subheadline.weight(.medium))
                    Picker("", selection: $store.settings.theme) {
                        Text(L("Система", "System")).tag(0)
                        Text(L("Светлая", "Light")).tag(1)
                        Text(L("Тёмная", "Dark")).tag(2)
                    }
                    .pickerStyle(.segmented)

                    Toggle(isOn: $store.settings.colorful) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Цветные метки", "Color labels")).font(.subheadline.weight(.medium))
                            Text(L("По умолчанию всё чёрно-белое", "Everything is black & white by default"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tint(.primary)

                    Divider()

                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("Язык: русский", "Language: English")).font(.subheadline.weight(.medium))
                                Text(L("Берётся из системы. Поменять можно в настройках приложения",
                                       "Follows the system. You can change it in the app settings"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .card()

                // Виджеты
                SectionTitle(L("Виджеты", "Widgets"))
                VStack(alignment: .leading, spacing: 12) {
                    statusLine(ok: SharedStorage.isShared,
                               title: SharedStorage.isShared ? L("Подключены", "Connected") : L("Нет доступа к данным", "No data access"),
                               subtitle: SharedStorage.isShared
                                   ? L("6 виджетов, стиль меняется долгим тапом → «Изменить виджет»",
                                       "6 widgets, change style via long press → Edit Widget")
                                   : L("Нажми «Диагностика» и скинь текст разработчику",
                                       "Tap Diagnostics and send the text to the developer"))
                    HStack(spacing: 8) {
                        pill(L("Обновить", "Refresh"), "arrow.clockwise") {
                            WidgetCenter.shared.reloadAllTimelines()
                            flash(L("Виджеты обновлены", "Widgets refreshed"))
                        }
                        pill(showDiagnostics ? L("Скрыть", "Hide") : L("Диагностика", "Diagnostics"), "stethoscope") {
                            withAnimation(.snappy) { showDiagnostics.toggle() }
                        }
                    }
                    if showDiagnostics {
                        Text(SharedStorage.diagnostics)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
                        pill(L("Скопировать", "Copy"), "doc.on.doc") {
                            UIPasteboard.general.string = SharedStorage.diagnostics
                            flash(L("Скопировано", "Copied"))
                        }
                    }
                }
                .card()

                // Уведомления
                SectionTitle(L("Уведомления", "Notifications"))
                VStack(alignment: .leading, spacing: 12) {
                    statusLine(ok: notifStatus == .authorized,
                               title: notifStatus == .authorized ? L("Включены", "On") : L("Выключены", "Off"),
                               subtitle: notifStatus == .authorized
                                   ? L("Напоминания придут вовремя", "Reminders will arrive on time")
                                   : L("Разреши уведомления в настройках", "Allow notifications in Settings"))
                    HStack(spacing: 8) {
                        pill(L("Тест через 5 сек", "Test in 5 sec"), "paperplane") {
                            NotificationManager.shared.sendTest()
                            flash(L("Жди уведомление", "Wait for it…"))
                        }
                        pill(L("Настройки", "Settings"), "gear") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                }
                .card()

                // Данные
                SectionTitle(L("Данные", "Data"))
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L("Всего дел", "Total tasks")).font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(store.events.count)").font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                    HStack(spacing: 8) {
                        ShareLink(item: store.exportURL(),
                                  preview: SharePreview(L("Бэкап расписания", "Schedule backup"))) {
                            Label(L("Экспорт", "Export"), systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(Capsule().fill(Color.primary.opacity(0.07)))
                        }
                        .buttonStyle(.plain)
                        pill(L("Импорт", "Import"), "square.and.arrow.down") { importing = true }
                    }
                    if !store.state.skipped.isEmpty {
                        pill(L("Вернуть пропущенные (\(store.state.skipped.count))",
                               "Restore skipped (\(store.state.skipped.count))"), "arrow.uturn.backward") {
                            store.restoreSkipped()
                            flash(L("Вернули", "Restored"))
                        }
                    }
                    pill(L("Удалить прошедшие разовые", "Delete past one-time tasks"), "trash", destructive: true) {
                        confirmCleanup = true
                    }
                }
                .card()

                Text("Schedule Control \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .screen()
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .glass(20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .confirmationDialog(L("Удалить все прошедшие разовые дела?", "Delete all past one-time tasks?"),
                            isPresented: $confirmCleanup, titleVisibility: .visible) {
            Button(L("Удалить", "Delete"), role: .destructive) {
                let n = store.deletePastOneTime()
                flash(n == 0 ? L("Нечего удалять", "Nothing to delete") : L("Удалено: \(n)", "Deleted: \(n)"))
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do {
                    let n = try store.importBackup(from: url)
                    flash(L("Импортировано дел: \(n)", "Imported tasks: \(n)"))
                } catch {
                    flash(L("Не получилось прочитать файл", "Couldn't read the file"))
                }
            case .failure:
                break
            }
        }
        .task { await refreshStatus() }
    }

    private func statusLine(ok: Bool, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ok ? "checkmark" : "exclamationmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(ok ? Color(uiColor: .systemBackground) : Color.primary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(ok ? Color.primary : Color.primary.opacity(0.1)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func pill(_ title: String, _ icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            haptic()
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(destructive ? Color.red : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }

    private func flash(_ text: String) {
        withAnimation(.snappy) { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation(.snappy) { toast = nil }
        }
    }

    private func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notifStatus = settings.authorizationStatus
    }
}
