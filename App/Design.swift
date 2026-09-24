import SwiftUI

// MARK: - Стекло (для плавающих элементов). iOS 26 — Liquid Glass, раньше — материал.

struct GlassModifier: ViewModifier {
    let radius: CGFloat
    let interactive: Bool

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: .rect(cornerRadius: radius))
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .background(.regularMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}

extension View {
    func glass(_ radius: CGFloat = 24, interactive: Bool = false) -> some View {
        modifier(GlassModifier(radius: radius, interactive: interactive))
    }

    /// Плоская минималистичная карточка
    func card(_ radius: CGFloat = 20, padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
    }

    func screen() -> some View {
        self
            .scrollIndicators(.hidden)
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }
}

// MARK: - Заголовок экрана

struct ScreenHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let subtitle {
                Text(subtitle.uppercased(with: appLocale))
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

struct SectionTitle: View {
    let text: String
    var trailing: String? = nil
    init(_ text: String, trailing: String? = nil) { self.text = text; self.trailing = trailing }

    var body: some View {
        HStack {
            Text(text.uppercased(with: appLocale))
            Spacer()
            if let trailing { Text(trailing) }
        }
        .font(.caption.weight(.semibold))
        .tracking(1)
        .foregroundStyle(.secondary)
        .padding(.top, 14)
        .padding(.horizontal, 4)
    }
}

// MARK: - Иконка события

struct EventIcon: View {
    let icon: String
    let colorIndex: Int
    var size: CGFloat = 36

    var body: some View {
        let c = Palette.color(colorIndex)
        Image(systemName: icon)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(c)
            .frame(width: size, height: size)
            .background(Circle().fill(c.opacity(Palette.colorful ? 0.16 : 0.07)))
    }
}

// MARK: - Галочка «выполнено»

struct CheckCircle: View {
    let done: Bool
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.primary.opacity(done ? 1 : 0.3), lineWidth: 1.5)
            if done {
                Circle().fill(Color.primary)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(Color(uiColor: .systemBackground))
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .animation(.snappy(duration: 0.2), value: done)
    }
}

// MARK: - Строка дела

struct OccurrenceRow: View {
    let occ: Occurrence
    var done = false
    var showCheck = true
    var showDay = false
    var now = Date()
    var onToggle: (() -> Void)? = nil

    var body: some View {
        let past = !occ.isNow(now) && occ.end < now && occ.date < now
        HStack(spacing: 14) {
            if showCheck {
                CheckCircle(done: done)
                    .onTapGesture { haptic(); onToggle?() }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(occ.title)
                        .font(.body.weight(.medium))
                        .strikethrough(done)
                        .lineLimit(1)
                    if occ.important {
                        Image(systemName: "star.fill").font(.caption2)
                    }
                    if occ.isNow(now) {
                        Text(L("СЕЙЧАС", "NOW"))
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.8)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary))
                            .foregroundStyle(Color(uiColor: .systemBackground))
                    }
                }
                HStack(spacing: 6) {
                    Text(showDay ? "\(dayLabel(occ.date)), \(occ.timeRange)" : occ.timeRange)
                        .monospacedDigit()
                    if !occ.note.isEmpty {
                        Text("·")
                        Text(occ.note).lineLimit(1)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            EventIcon(icon: occ.icon, colorIndex: occ.colorIndex, size: 32)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .opacity(done || (past && !showCheck) ? 0.45 : 1)
        .contentShape(Rectangle())
    }
}

/// Список строк в одной карточке с тонкими разделителями
struct RowGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5).padding(.leading, 52)
    }
}

// MARK: - Полоска прогресса

struct ProgressBar: View {
    let value: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(Color.primary)
                    .frame(width: max(height, geo.size.width * min(max(value, 0), 1)))
                    .opacity(value > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .animation(.snappy, value: value)
    }
}

// MARK: - Плавающая кнопка «+»

struct AddButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            haptic()
            action()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 58, height: 58)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glass(29, interactive: true)
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
    }
}

// MARK: - Пустое состояние

struct EmptyState: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .card()
    }
}

// MARK: - Чипсы-фильтры

struct Chip: View {
    let title: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: { haptic(); action() }) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(active ? Color(uiColor: .systemBackground) : Color.primary)
                .background(
                    Capsule().fill(active ? Color.primary : Color(uiColor: .secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: active)
    }
}
