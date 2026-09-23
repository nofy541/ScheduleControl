import SwiftUI

// MARK: - Liquid Glass
// На iOS 26+ (при сборке в Xcode 26) — настоящий Liquid Glass (.glassEffect).
// На iOS 17–18 — аккуратный фолбэк на «матовое стекло» (.ultraThinMaterial).

struct GlassModifier: ViewModifier {
    let radius: CGFloat
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(glass, in: .rect(cornerRadius: radius))
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint.opacity(0.35)) }
        if interactive { g = g.interactive() }
        return g
    }
    #endif

    private func fallback(_ content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .background((tint ?? .clear).opacity(0.18), in: shape)
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
    }
}

extension View {
    func glass(_ radius: CGFloat = 24, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassModifier(radius: radius, tint: tint, interactive: interactive))
    }

    func screenBackground() -> some View {
        background(AppBackground())
    }
}

// MARK: - Фон с цветными пятнами (чтобы стеклу было что преломлять)

struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            (scheme == .dark ? Color.black : Color(white: 0.95))
            blob(.blue, size: 380, x: -150, y: -300, opacity: 0.55)
            blob(.purple, size: 320, x: 170, y: -120, opacity: 0.45)
            blob(.pink, size: 300, x: -120, y: 260, opacity: 0.35)
            blob(.teal, size: 340, x: 160, y: 460, opacity: 0.35)
        }
        .ignoresSafeArea()
    }

    private func blob(_ color: Color, size: CGFloat, x: CGFloat, y: CGFloat, opacity: Double) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: 90)
            .offset(x: x, y: y)
            .opacity(scheme == .dark ? opacity : opacity * 0.7)
    }
}

// MARK: - Иконка события в цветном кружке

struct EventIcon: View {
    let icon: String
    let color: Color
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(color.gradient)
            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Карточка наступления события

struct OccurrenceCard: View {
    let occ: Occurrence
    var past = false
    var showDay = false

    var body: some View {
        HStack(spacing: 12) {
            EventIcon(icon: occ.icon, color: occ.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(occ.title)
                    .font(.body.weight(.semibold))
                    .strikethrough(past)
                    .lineLimit(1)
                if !occ.note.isEmpty {
                    Text(occ.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(timeString(occ.date))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                if showDay {
                    Text(dayLabel(occ.date)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .glass(20, tint: occ.color)
        .opacity(past ? 0.55 : 1)
        .contentShape(Rectangle())
    }
}

// MARK: - Кольцо прогресса

struct ProgressRing: View {
    let progress: Double
    var color: Color = .blue
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.6), value: progress)
        }
    }
}

// MARK: - Плавающая кнопка «+»

struct AddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .frame(width: 60, height: 60)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glass(30, tint: .blue, interactive: true)
    }
}

// MARK: - Заголовок секции

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Пустое состояние

struct EmptyCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glass(24)
    }
}
