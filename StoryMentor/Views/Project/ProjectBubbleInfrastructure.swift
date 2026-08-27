import SwiftUI

struct MajorBeatConstellationView: View {
  @State private var availableWidth: CGFloat = 1_080

  let beats: [ProjectMajorBeatBubble]
  let haloExpanded: Bool
  let reduceMotion: Bool
  let onSelect: (Int) -> Void

  private var geometry: BeatPathGeometry {
    BeatPathGeometry(width: availableWidth, count: beats.count)
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      BeatPathConnectorLayer(geometry: geometry, reduceMotion: reduceMotion)

      ForEach(beats) { beat in
        MajorBeatBubbleView(
          beat: beat,
          haloExpanded: haloExpanded,
          reduceMotion: reduceMotion
        ) {
          onSelect(beat.index)
        }
        .frame(width: geometry.bubbleWidth, height: geometry.bubbleHeight)
        .position(geometry.center(for: beat.index))
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: geometry.height)
    .onGeometryChange(
      for: CGFloat.self,
      of: { proxy in
        proxy.size.width
      }
    ) { newWidth in
      guard newWidth.isFinite, newWidth > 0 else { return }
      availableWidth = newWidth
    }
    .animation(reduceMotion ? nil : .smooth(duration: 0.34), value: geometry.columns)
  }
}

private struct BeatPathConnectorLayer: View {
  @Environment(\.scenePhase) private var scenePhase

  let geometry: BeatPathGeometry
  let reduceMotion: Bool

  var body: some View {
    if reduceMotion || scenePhase != .active {
      connectorCanvas(phase: 0)
    } else {
      TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { context in
        let elapsed = context.date.timeIntervalSinceReferenceDate
        connectorCanvas(phase: CGFloat(elapsed.truncatingRemainder(dividingBy: 1.4) / 1.4) * 18)
      }
    }
  }

  private func connectorCanvas(phase: CGFloat) -> some View {
    Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, _ in
      for segment in geometry.connectionSegments {
        var path = Path()
        path.move(to: segment.start)
        path.addLine(to: segment.end)

        context.stroke(
          path,
          with: .color(StudioTheme.accent.opacity(0.13)),
          style: StrokeStyle(lineWidth: 4, lineCap: .round)
        )
        context.stroke(
          path,
          with: .linearGradient(
            Gradient(colors: [StudioTheme.mint, StudioTheme.accent, StudioTheme.warm]),
            startPoint: segment.start,
            endPoint: segment.end
          ),
          style: StrokeStyle(
            lineWidth: 2.2,
            lineCap: .round,
            dash: [4, 9],
            dashPhase: -phase
          )
        )

        context.fill(
          arrowHead(for: segment),
          with: .color(StudioTheme.accent.opacity(0.72))
        )
      }
    }
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }

  private func arrowHead(for segment: BeatPathGeometry.Segment) -> Path {
    let deltaX = segment.end.x - segment.start.x
    let deltaY = segment.end.y - segment.start.y
    let length = max(hypot(deltaX, deltaY), 1)
    let unitX = deltaX / length
    let unitY = deltaY / length
    let mid = CGPoint(
      x: (segment.start.x + segment.end.x) / 2,
      y: (segment.start.y + segment.end.y) / 2
    )
    let tip = CGPoint(x: mid.x + unitX * 8, y: mid.y + unitY * 8)
    let base = CGPoint(x: mid.x - unitX * 6, y: mid.y - unitY * 6)
    let perpendicularX = -unitY * 6
    let perpendicularY = unitX * 6

    var arrow = Path()
    arrow.move(to: tip)
    arrow.addLine(to: CGPoint(x: base.x + perpendicularX, y: base.y + perpendicularY))
    arrow.addLine(to: CGPoint(x: base.x - perpendicularX, y: base.y - perpendicularY))
    arrow.closeSubpath()
    return arrow
  }
}

private struct BeatPathGeometry {
  struct Segment {
    let start: CGPoint
    let end: CGPoint
  }

  let width: CGFloat
  let count: Int

  let horizontalPadding: CGFloat = 20
  let horizontalSpacing: CGFloat = 20
  let verticalSpacing: CGFloat = 24
  let bubbleHeight: CGFloat = 240

  var columns: Int {
    switch width {
    case 1_680...: 6
    case 1_380...: 5
    case 1_100...: 4
    case 820...: 3
    case 570...: 2
    default: 1
    }
  }

  var bubbleWidth: CGFloat {
    let available = max(width - horizontalPadding * 2, 260)
    let proposed = (available - CGFloat(columns - 1) * horizontalSpacing) / CGFloat(columns)
    return min(max(proposed, 260), 420)
  }

  private var rows: Int {
    max(Int(ceil(Double(count) / Double(columns))), 1)
  }

  private var usedWidth: CGFloat {
    bubbleWidth * CGFloat(columns) + horizontalSpacing * CGFloat(columns - 1)
  }

  private var leadingInset: CGFloat {
    max((width - usedWidth) / 2, 0)
  }

  var height: CGFloat {
    CGFloat(rows) * bubbleHeight + CGFloat(rows - 1) * verticalSpacing
  }

  func center(for index: Int) -> CGPoint {
    let row = index / columns
    let sequenceColumn = index % columns
    let column =
      row.isMultiple(of: 2)
      ? sequenceColumn
      : columns - sequenceColumn - 1

    return CGPoint(
      x: leadingInset + bubbleWidth / 2 + CGFloat(column) * (bubbleWidth + horizontalSpacing),
      y: bubbleHeight / 2 + CGFloat(row) * (bubbleHeight + verticalSpacing)
    )
  }

  var connectionSegments: [Segment] {
    guard count > 1 else { return [] }

    return (0..<(count - 1)).map { index in
      clippedSegment(from: center(for: index), to: center(for: index + 1))
    }
  }

  private func clippedSegment(from startCenter: CGPoint, to endCenter: CGPoint) -> Segment {
    let deltaX = endCenter.x - startCenter.x
    let deltaY = endCenter.y - startCenter.y

    if abs(deltaX) > abs(deltaY) {
      let direction: CGFloat = deltaX >= 0 ? 1 : -1
      return Segment(
        start: CGPoint(x: startCenter.x + direction * bubbleWidth * 0.5, y: startCenter.y),
        end: CGPoint(x: endCenter.x - direction * bubbleWidth * 0.5, y: endCenter.y)
      )
    }

    let direction: CGFloat = deltaY >= 0 ? 1 : -1
    return Segment(
      start: CGPoint(x: startCenter.x, y: startCenter.y + direction * bubbleHeight * 0.5),
      end: CGPoint(x: endCenter.x, y: endCenter.y - direction * bubbleHeight * 0.5)
    )
  }
}

extension View {
  func universeBubbleSurface(
    tint: Color,
    cornerRadius: CGFloat,
    isHovered: Bool = false,
    isSelected: Bool = false
  ) -> some View {
    modifier(
      StoryBubbleSurfaceModifier(
        tint: tint,
        cornerRadius: cornerRadius,
        isHovered: isHovered,
        isSelected: isSelected
      )
    )
  }

  func animatedStoryBubble(
    tint: Color,
    cornerRadius: CGFloat = 30,
    isSelected: Bool = false
  ) -> some View {
    modifier(
      AnimatedStoryBubbleModifier(
        tint: tint,
        cornerRadius: cornerRadius,
        isSelected: isSelected
      )
    )
  }
}

private struct AnimatedStoryBubbleModifier: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isHovered = false
  @State private var hasAppeared = false

  let tint: Color
  let cornerRadius: CGFloat
  let isSelected: Bool

  func body(content: Content) -> some View {
    content
      .universeBubbleSurface(
        tint: tint,
        cornerRadius: cornerRadius,
        isHovered: isHovered,
        isSelected: isSelected
      )
      .scaleEffect(hasAppeared ? 1 : 0.965)
      .offset(y: hasAppeared ? (isHovered ? -2 : 0) : 10)
      .opacity(hasAppeared ? 1 : 0)
      .animation(
        reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.82),
        value: hasAppeared
      )
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
      .onHover { isHovered = $0 }
      .onAppear {
        if reduceMotion {
          hasAppeared = true
        } else {
          Task { @MainActor in
            await Task.yield()
            hasAppeared = true
          }
        }
      }
  }
}

private struct StoryBubbleSurfaceModifier: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

  let tint: Color
  let cornerRadius: CGFloat
  let isHovered: Bool
  let isSelected: Bool

  @ViewBuilder
  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    let emphasized = isHovered || isSelected
    let borderWidth: CGFloat = differentiateWithoutColor ? 1.8 : (emphasized ? 1.7 : 1)
    let borderDash: [CGFloat] = differentiateWithoutColor ? [8, 4] : []
    let surfaceShadow = emphasized ? tint.opacity(0.28) : Color.black.opacity(0.10)
    let surfaceShadowRadius: CGFloat = emphasized ? 18 : 14

    if reduceTransparency {
      content
        .background {
          shape
            .fill(StudioTheme.secondaryCanvas)
            .overlay {
              shape.fill(tint.opacity(emphasized ? 0.14 : 0.09))
            }
            .shadow(color: surfaceShadow, radius: surfaceShadowRadius, y: 6)
        }
        .overlay {
          shape.stroke(
            differentiateWithoutColor
              ? Color.primary.opacity(0.50)
              : tint.opacity(emphasized ? 0.72 : 0.30),
            style: StrokeStyle(lineWidth: borderWidth, dash: borderDash)
          )
        }
    } else {
      content
        .background {
          shape
            .fill(tint.opacity(emphasized ? 0.075 : 0.045))
            .shadow(color: surfaceShadow, radius: surfaceShadowRadius, y: 7)
        }
        .overlay {
          shape.stroke(
            LinearGradient(
              colors: differentiateWithoutColor
                ? [Color.primary.opacity(0.58), Color.primary.opacity(0.28)]
                : [
                  Color.white.opacity(emphasized ? 0.48 : 0.22),
                  tint.opacity(emphasized ? 0.72 : 0.24),
                  Color.primary.opacity(0.055),
                ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ),
            style: StrokeStyle(lineWidth: borderWidth, dash: borderDash)
          )
        }
        .glassEffect(
          .regular.tint(tint.opacity(emphasized ? 0.18 : 0.12)),
          in: shape
        )
    }
  }
}

extension String {
  var isBubbleBlank: Bool {
    trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var bubblePlainText: String {
    let meaningfulLines = split(separator: "\n", omittingEmptySubsequences: true)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && !$0.hasPrefix("【") }
    return
      meaningfulLines
      .joined(separator: " ")
      .replacingOccurrences(of: "  ", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func bubbleExcerpt(limit: Int) -> String {
    let text = bubblePlainText
    guard text.count > limit else { return text }
    return String(text.prefix(limit))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "…"
  }
}
