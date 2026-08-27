import AppKit
import SwiftUI

enum StudioTheme {
    static let accent = Color.accentColor
    static let ink = Color(red: 0.12, green: 0.14, blue: 0.16)
    static let warm = Color(red: 0.92, green: 0.60, blue: 0.24)
    static let mint = Color(red: 0.31, green: 0.70, blue: 0.55)
    static let sky = Color(red: 0.32, green: 0.58, blue: 0.78)
    static let canvas = Color(nsColor: .underPageBackgroundColor)
    static let secondaryCanvas = Color(nsColor: .controlBackgroundColor)
}

struct StudioCanvas: View {
    var body: some View {
        ZStack {
            StudioTheme.canvas

            LinearGradient(
                colors: [
                    StudioTheme.accent.opacity(0.065),
                    Color.clear,
                    StudioTheme.warm.opacity(0.025)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(StudioTheme.mint.opacity(0.055))
                .frame(width: 560, height: 560)
                .blur(radius: 110)
                .offset(x: -360, y: -300)

            Circle()
                .fill(StudioTheme.warm.opacity(0.035))
                .frame(width: 500, height: 500)
                .blur(radius: 120)
                .offset(x: 420, y: 330)

            Canvas { context, size in
                let spacing: CGFloat = 72
                var path = Path()
                stride(from: spacing, through: size.width, by: spacing).forEach { x in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                stride(from: spacing, through: size.height, by: spacing).forEach { y in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(Color.primary.opacity(0.012)), lineWidth: 0.5)
            }
        }
        .ignoresSafeArea()
    }
}

struct StudioCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .animatedStoryBubble(tint: StudioTheme.accent, cornerRadius: 28)
    }
}

struct EyebrowLabel: View {
    let text: String
    var color: Color = StudioTheme.accent

    var body: some View {
        Text(text.uppercased())
            .font(.callout.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(color)
    }
}

struct ProgressRing: View {
    let value: Double
    var lineWidth: CGFloat = 8
    var diameter: CGFloat = 68

    private var clampedValue: Double {
        min(max(value, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: clampedValue)
                .stroke(
                    AngularGradient(
                        colors: [StudioTheme.accent, StudioTheme.warm],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text(clampedValue, format: .percent.precision(.fractionLength(0)))
                .font(.system(.callout, design: .rounded, weight: .bold))
                .contentTransition(.numericText())
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel("完成度")
        .accessibilityValue(
            Text(clampedValue, format: .percent.precision(.fractionLength(0)))
        )
    }
}

struct MetricTile: View {
    let icon: String
    let value: String
    let label: String
    var tint: Color = StudioTheme.accent

    var body: some View {
        StudioCard(padding: 16) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
    }
}

struct PhaseBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(StudioTheme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(StudioTheme.accent.opacity(0.09), in: Capsule())
    }
}

struct LocalCheckRow: View {
    enum State {
        case present
        case missing
        case neutral

        var icon: String {
            switch self {
            case .present: "checkmark.circle.fill"
            case .missing: "circle.dashed"
            case .neutral: "arrow.right.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .present: StudioTheme.mint
            case .missing: StudioTheme.warm
            case .neutral: StudioTheme.sky
            }
        }
    }

    let text: String
    let state: State

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: state.icon)
                .foregroundStyle(state.color)
                .padding(.top, 1)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
