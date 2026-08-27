import SwiftUI

struct StoryNucleusBubble: View {
  let title: String
  let logline: String
  let dramaticQuestion: String
  let structureName: String
  let haloExpanded: Bool
  let reduceMotion: Bool

  var body: some View {
    VStack(spacing: 15) {
      HStack(spacing: 8) {
        Image(systemName: "sparkles")
        Text("故事核心")
          .tracking(1.1)
        Text("·")
          .foregroundStyle(.tertiary)
        Text(structureName)
      }
      .font(.system(size: 12, weight: .bold, design: .rounded))
      .foregroundStyle(StudioTheme.warm)

      Text(title.isBubbleBlank ? "未命名故事" : title)
        .font(.system(size: 31, weight: .semibold, design: .serif))
        .multilineTextAlignment(.center)
        .lineLimit(2)

      Text(logline)
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(.primary)
        .multilineTextAlignment(.center)
        .lineSpacing(5)
        .fixedSize(horizontal: false, vertical: true)

      if !dramaticQuestion.isBubbleBlank {
        VStack(spacing: 4) {
          Text("贯穿问题")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
          Text(dramaticQuestion)
            .font(.system(size: 14.5, weight: .medium, design: .serif))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
      }
    }
    .padding(.horizontal, 52)
    .padding(.vertical, 30)
    .frame(maxWidth: 780, minHeight: 240)
    .background {
      BubbleHalo(
        tint: StudioTheme.warm,
        cornerRadius: 86,
        expanded: haloExpanded,
        reduceMotion: reduceMotion,
        delay: 0
      )
    }
    .universeBubbleSurface(tint: StudioTheme.warm, cornerRadius: 86)
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("故事核心，\(title)，\(logline)")
  }
}

struct MissingStructureBubble: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 14) {
        Image(systemName: "square.grid.3x3.topleft.filled")
          .font(.system(size: 22, weight: .semibold))
          .foregroundStyle(StudioTheme.accent)
        VStack(alignment: .leading, spacing: 4) {
          Text("先选择并固定结构")
            .font(.system(size: 18, weight: .semibold))
          Text("固定结构后，大节拍会沿因果路径在这里展开。")
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 10)
        Image(systemName: "arrow.up.right")
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 24)
      .padding(.vertical, 20)
      .frame(maxWidth: 620)
      .animatedStoryBubble(tint: StudioTheme.accent, cornerRadius: 36)
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
  }
}

struct MajorBeatBubbleView: View {
  @State private var isHovering = false

  let beat: ProjectMajorBeatBubble
  let haloExpanded: Bool
  let reduceMotion: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 9) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(String(format: "%02d", beat.index + 1))
            .font(.system(size: 12.5, weight: .bold, design: .monospaced))
            .foregroundStyle(beat.tint)
          Text(beat.stageName)
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(isHovering ? Color.primary : Color.secondary)
            .lineLimit(2)
          Spacer(minLength: 4)
          Label(beat.statusLabel, systemImage: beat.statusIcon)
            .labelStyle(.iconOnly)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(beat.tint)
        }

        Text(beat.title)
          .font(.system(size: 19, weight: .semibold, design: .serif))
          .foregroundStyle(.primary)
          .multilineTextAlignment(.leading)
          .lineLimit(2)

        Text(beat.overviewSummary)
          .font(.system(size: 14.5))
          .foregroundStyle(isHovering ? Color.primary.opacity(0.90) : Color.secondary)
          .multilineTextAlignment(.leading)
          .lineSpacing(3.5)
          .lineLimit(4)

        Spacer(minLength: 0)

        HStack(spacing: 10) {
          Label(beat.sceneProgress, systemImage: "rectangle.stack")
          if let microBeatProgress = beat.microBeatProgress {
            Label(microBeatProgress, systemImage: "list.number")
          }
        }
        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
        .foregroundStyle(isHovering ? Color.primary.opacity(0.82) : Color.secondary)
        .lineLimit(1)
      }
      .padding(16)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background {
        BubbleHalo(
          tint: beat.tint,
          cornerRadius: 48,
          expanded: haloExpanded,
          reduceMotion: reduceMotion,
          delay: Double(beat.index % 4) * 0.16
        )
      }
      .universeBubbleSurface(
        tint: beat.tint,
        cornerRadius: 48,
        isHovered: isHovering,
        isSelected: beat.status == .current
      )
      .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: isHovering)
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .help("\(beat.stageName)：\(beat.title)\n\(beat.summary)")
    .accessibilityLabel(
      "第 \(beat.index + 1) 大节拍，\(beat.stageName)，\(beat.title)，\(beat.statusLabel)，\(beat.sceneProgress)，\(beat.microBeatProgress ?? "小节拍未展开")"
    )
    .accessibilityHint("进入这个大节拍")
  }
}

struct SatelliteBubble: View {
  @State private var isHovering = false

  let model: ProjectSatelliteBubble
  let haloExpanded: Bool
  let reduceMotion: Bool
  let animationDelay: Double
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 9) {
          Image(systemName: model.icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(model.tint)
          Text(model.eyebrow)
            .font(.system(size: 11.5, weight: .bold, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(model.tint)
          Spacer(minLength: 4)
          Image(systemName: "arrow.up.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.tertiary)
        }

        Text(model.title)
          .font(.system(size: 18, weight: .semibold, design: .serif))
          .lineLimit(2)

        Text(model.body.bubbleExcerpt(limit: 50))
          .font(.system(size: 14.5))
          .foregroundStyle(isHovering ? Color.primary.opacity(0.90) : Color.secondary)
          .lineSpacing(3.5)
          .lineLimit(3)

        Spacer(minLength: 2)

        Text(model.detail)
          .font(.system(size: 11.5, weight: .semibold, design: .rounded))
          .foregroundStyle(model.tint.opacity(0.92))
      }
      .padding(14)
      .frame(maxWidth: .infinity, minHeight: 190, maxHeight: 190, alignment: .topLeading)
      .background {
        BubbleHalo(
          tint: model.tint,
          cornerRadius: 46,
          expanded: haloExpanded,
          reduceMotion: reduceMotion,
          delay: animationDelay
        )
      }
      .universeBubbleSurface(
        tint: model.tint,
        cornerRadius: 46,
        isHovered: isHovering
      )
      .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: isHovering)
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .help("\(model.title)\n\(model.body)")
    .accessibilityLabel("\(model.eyebrow)，\(model.title)，\(model.body)，\(model.detail)")
    .accessibilityHint("进入\(model.eyebrow)模块")
  }
}

private struct BubbleHalo: View {
  let tint: Color
  let cornerRadius: CGFloat
  let expanded: Bool
  let reduceMotion: Bool
  let delay: Double

  var body: some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      .stroke(tint.opacity(expanded ? 0.34 : 0.16), lineWidth: 2)
      .blur(radius: expanded ? 12 : 7)
      .scaleEffect(expanded ? 1.035 : 0.992)
      .opacity(expanded ? 0.72 : 0.34)
      .animation(
        reduceMotion
          ? nil
          : .easeInOut(duration: 3.2)
            .repeatForever(autoreverses: true)
            .delay(delay),
        value: expanded
      )
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}
