import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

struct SettingsView: View {
    @EnvironmentObject var store: ScheduleStore
    @Environment(\.openURL) private var openURL

    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    @State private var showDiagnostics = false
    @State private var confirmCleanup = false
    @State private var toast: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ещё")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .padding(.horizontal, 4)
                    .padding(.top, 8)

                // Виджеты
                SectionTitle("Виджеты")
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        EventIcon(icon: SharedStorage.isShared ? "checkmark" : "exclamationmark.triangle.fill",
                                  color: SharedStorage.isShared ? .green : .orange, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(SharedStorage.isShared ? "Виджеты подключены" : "Виджеты не видят данные")
                                .font(.headline)
                            Text(SharedStorage.isShared
                                 ? "Всё, что ты добавляешь, сразу видно в виджетах"
                                 : "Нет доступа к App Group. Нажми «Диагностика» и скинь текст разработчику")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 10) {
                        pill("Обновить", icon: "arrow.clockwise") {
                            WidgetCenter.shared.reloadAllTimelines()
                            flash("Виджеты обновлены")
                        }
                        pill(showDiagnostics ? "Скрыть" : "Диагностика", icon: "stethoscope") {
                            withAnimation(.snappy) { showDiagnostics.toggle() }
                        }
                    }
                    if showDiagnostics {
                        Text(SharedStorage.diagnostics)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .glass(12)
                        pill("Скопировать", icon: "doc.on.doc") {
                            UIPasteboard.general.string = SharedStorage.diagnostics
                            flash("Скопировано")
                        }
                    }
                }
                .padding(16)
                .glass(24, tint: SharedStorage.isShared ? .green : .orange)

                // Уведомления
                SectionTitle("Уведомления")
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        EventIcon(icon: "bell.fill", color: notifStatus == .authorized ? .blue : .red, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(notifStatus == .authorized ? "Включены" : "Выключены").font(.headline)
                            Text(notifStatus == .authorized
                                 ? "Напоминания придут вовремя"
                                 : "Разреши уведомления в настройках iPhone")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 10) {
                        pill("Тест через 5 сек", icon: "paperplane.fill") {
                            NotificationManager.shared.sendTest()
                            flash("Жди уведомление 👀")
                        }
                        pill("Настройки", icon: "gear") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                }
                .padding(16)
                .glass(24)

                // Данные
                SectionTitle("Данные")
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Всего дел").font(.headline)
                        Spacer()
                        Text("\(store.events.count)")
                            .font(.system(.headline, design: .rounded))
                            .monospacedDigit()
                    }
                    pill("Удалить прошедшие разовые", icon: "trash", destructive: true) {
                        confirmCleanup = true
                    }
                }
                .padding(16)
                .glass(24)

                Text("Расписание \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
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
        .confirmationDialog("Удалить все прошедшие разовые дела?", isPresented: $confirmCleanup, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                let n = store.deletePastOneTime()
                flash(n == 0 ? "Нечего удалять" : "Удалено: \(n)")
            }
        }
        .task { await refreshStatus() }
    }

    private func pill(_ title: String, icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(destructive ? Color.red : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .glass(18, interactive: true)
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
