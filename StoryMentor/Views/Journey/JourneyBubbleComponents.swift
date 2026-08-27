import SwiftUI

struct JourneyStageBubbleModel: Identifiable {
  enum Status: Equatable {
    case resolved
    case current
    case upcoming

    var label: String {
      switch self {
      case .resolved: "已确认"
      case .current: "当前"
      case .upcoming: "待展开"
      }
    }

    var icon: String {
      switch self {
      case .resolved: "checkmark.seal.fill"
      case .current: "scope"
      case .upcoming: "circle.dotted"
      }
    }

    var tint: Color {
      switch self {
      case .resolved: StudioTheme.mint
      case .current: StudioTheme.accent
      case .upcoming: StudioTheme.sky
      }
    }
  }

  let index: Int
  let stageName: String
  let summary: String
  let status: Status
  let isSelected: Bool

  var id: Int { index }
}

struct JourneyStagePathView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var availableWidth: CGFloat = 1_200

  let nodes: [JourneyStageBubbleModel]
  let onSelect: (Int) -> Void

  private var geometry: JourneyStagePathGeometry {
    JourneyStagePathGeometry(width: availableWidth, count: nodes.count)
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      JourneyStageConnectorLayer(geometry: geometry, reduceMotion: reduceMotion)

      ForEach(nodes) { node in
        JourneyStageNodeBubble(node: node) {
          onSelect(node.index)
        }
        .frame(width: geometry.bubbleWidth, height: geometry.bubbleHeight)
        .position(geometry.center(for: node.index))
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: geometry.height)
    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
      guard width.isFinite, width > 0 else { return }
      availableWidth = width
    }
    .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: geometry.columns)
  }
}

private struct JourneyStageNodeBubble: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isHovering = false

  let node: JourneyStageBubbleModel
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 9) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(String(format: "%02d", node.index + 1))
            .font(.system(size: 12.5, weight: .bold, design: .monospaced))
            .foregroundStyle(node.status.tint)

          Spacer(minLength: 4)

          Label(node.status.label, systemImage: node.status.icon)
            .font(.system(size: 10.5, weight: .bold, design: .rounded))
            .foregroundStyle(node.status.tint)
        }

        Text(node.stageName)
          .font(.system(size: 18, weight: .semibold, design: .serif))
          .foregroundStyle(.primary)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)

        Text(node.summary)
          .font(.system(size: 13.5))
          .foregroundStyle(
            isHovering
              ? Color.primary.opacity(0.94)
              : (node.status == .upcoming ? Color.secondary : Color.primary)
          )
          .multilineTextAlignment(.leading)
          .lineSpacing(3)
          .fixedSize(horizontal: false, vertical: true)

        Spacer(minLength: 0)

        HStack(spacing: 6) {
          Circle()
            .fill(node.status.tint)
            .frame(width: 6, height: 6)
          Text(node.isSelected ? "正在查看" : "查看节拍")
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(
              node.isSelected
                ? node.status.tint
                : (isHovering ? Color.primary.opacity(0.82) : Color.secondary)
            )
        }
      }
      .padding(15)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .universeBubbleSurface(
        tint: node.status.tint,
        cornerRadius: 42,
        isHovered: isHovering,
        isSelected: node.isSelected
      )
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .help("第 \(node.index + 1) 大节拍 · \(node.stageName)\n\(node.summary)")
    .accessibilityLabel(
      "第 \(node.index + 1) 大节拍，\(node.stageName)，\(node.status.label)，\(node.summary)"
    )
    .accessibilityHint("查看这个大节拍")
  }
}

private struct JourneyStageConnectorLayer: View {
  @Environment(\.scenePhase) private var scenePhase

  let geometry: JourneyStagePathGeometry
  let reduceMotion: Bool

  var body: some View {
    if reduceMotion || scenePhase != .active {
      connectorCanvas(phase: 0)
    } else {
      TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { context in
        let elapsed = context.date.timeIntervalSinceReferenceDate
        connectorCanvas(
          phase: CGFloat(elapsed.truncatingRemainder(dividingBy: 1.5) / 1.5) * 18
        )
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
          with: .color(StudioTheme.accent.opacity(0.12)),
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
            lineWidth: 2,
            lineCap: .round,
            dash: [4, 9],
            dashPhase: -phase
          )
        )
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

private struct JourneyStagePathGeometry {
  struct Segment {
    let start: CGPoint
    let end: CGPoint
  }

  let width: CGFloat
  let count: Int

  let horizontalPadding: CGFloat = 10
  let horizontalSpacing: CGFloat = 18
  let verticalSpacing: CGFloat = 22
  let bubbleHeight: CGFloat = 230

  var columns: Int {
    switch width {
    case 1_520...: 6
    case 1_250...: 5
    case 990...: 4
    case 740...: 3
    case 500...: 2
    default: 1
    }
  }

  var bubbleWidth: CGFloat {
    let available = max(width - horizontalPadding * 2, 220)
    let proposed = (available - CGFloat(columns - 1) * horizontalSpacing) / CGFloat(columns)
    return min(max(proposed, 220), 330)
  }

  private var rows: Int {
    max(Int(ceil(Double(max(count, 1)) / Double(columns))), 1)
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
    let itemsInRow = min(columns, max(count - row * columns, 0))
    let column =
      row.isMultiple(of: 2)
      ? sequenceColumn
      : max(itemsInRow - sequenceColumn - 1, 0)
    let rowWidth =
      bubbleWidth * CGFloat(itemsInRow)
      + horizontalSpacing * CGFloat(max(itemsInRow - 1, 0))
    let rowInset = max((width - rowWidth) / 2, leadingInset)

    return CGPoint(
      x: rowInset + bubbleWidth / 2 + CGFloat(column) * (bubbleWidth + horizontalSpacing),
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

struct JourneyChoiceBranchGuide: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var availableWidth: CGFloat = 1_000

  let optionCount: Int

  private var branchColumns: Int {
    availableWidth >= 1_380 ? 4 : availableWidth >= 720 ? 2 : 1
  }

  var body: some View {
    Group {
      if reduceMotion || scenePhase != .active {
        branchCanvas(phase: 0)
      } else {
        TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { context in
          let elapsed = context.date.timeIntervalSinceReferenceDate
          branchCanvas(
            phase: CGFloat(elapsed.truncatingRemainder(dividingBy: 1.4) / 1.4) * 16
          )
        }
      }
    }
    .frame(height: 68)
    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
      guard width.isFinite, width > 0 else { return }
      availableWidth = width
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func branchCanvas(phase: CGFloat) -> some View {
    Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
      let source = CGPoint(x: size.width / 2, y: 0)
      let targetY = size.height
      let branchCount = max(optionCount, 1)
      let columns = max(min(branchColumns, branchCount), 1)
      let laneWidth = size.width / CGFloat(columns)
      let rows = Int(ceil(Double(branchCount) / Double(columns)))

      for index in 0..<branchCount {
        let column = index % columns
        let row = index / columns
        let siblingOffset =
          rows > 1
          ? (CGFloat(row) - CGFloat(rows - 1) / 2) * 14
          : 0
        let target = CGPoint(
          x: laneWidth * (CGFloat(column) + 0.5) + siblingOffset,
          y: targetY
        )
        var path = Path()
        path.move(to: source)
        path.addCurve(
          to: target,
          control1: CGPoint(x: source.x, y: size.height * 0.48),
          control2: CGPoint(x: target.x, y: size.height * 0.48)
        )
        context.stroke(
          path,
          with: .linearGradient(
            Gradient(colors: [StudioTheme.warm, StudioTheme.accent, StudioTheme.mint]),
            startPoint: source,
            endPoint: target
          ),
          style: StrokeStyle(
            lineWidth: 2,
            lineCap: .round,
            dash: [4, 8],
            dashPhase: -phase
          )
        )
      }
    }
  }
}

struct JourneyChoiceOptionsLayout: Layout {
  var spacing: CGFloat = 16

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) -> CGSize {
    let width = max(proposal.width ?? 900, 280)
    let metrics = layoutMetrics(width: width, subviews: subviews)
    return CGSize(width: width, height: metrics.totalHeight)
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    let metrics = layoutMetrics(width: bounds.width, subviews: subviews)
    var y = bounds.minY

    for row in 0..<metrics.rowHeights.count {
      let firstIndex = row * metrics.columns
      let lastIndex = min(firstIndex + metrics.columns, subviews.count)
      let itemCount = lastIndex - firstIndex
      let usedWidth =
        metrics.itemWidth * CGFloat(itemCount)
        + spacing * CGFloat(max(itemCount - 1, 0))
      var x = bounds.minX + max((bounds.width - usedWidth) / 2, 0)

      for index in firstIndex..<lastIndex {
        subviews[index].place(
          at: CGPoint(x: x, y: y),
          anchor: .topLeading,
          proposal: ProposedViewSize(
            width: metrics.itemWidth,
            height: metrics.rowHeights[row]
          )
        )
        x += metrics.itemWidth + spacing
      }
      y += metrics.rowHeights[row] + spacing
    }
  }

  private func layoutMetrics(width: CGFloat, subviews: Subviews) -> Metrics {
    let columns: Int
    if width >= 1_380, subviews.count >= 4 {
      columns = 4
    } else if width >= 720, subviews.count >= 2 {
      columns = 2
    } else {
      columns = 1
    }

    let itemWidth = max(
      (width - spacing * CGFloat(columns - 1)) / CGFloat(columns),
      260
    )
    let rowCount = Int(ceil(Double(max(subviews.count, 1)) / Double(columns)))
    var rowHeights = Array(repeating: CGFloat.zero, count: rowCount)

    for (index, subview) in subviews.enumerated() {
      let size = subview.sizeThatFits(
        ProposedViewSize(width: itemWidth, height: nil)
      )
      rowHeights[index / columns] = max(rowHeights[index / columns], size.height)
    }

    let totalHeight =
      rowHeights.reduce(0, +)
      + spacing * CGFloat(max(rowHeights.count - 1, 0))
    return Metrics(
      columns: columns,
      itemWidth: itemWidth,
      rowHeights: rowHeights,
      totalHeight: totalHeight
    )
  }

  private struct Metrics {
    let columns: Int
    let itemWidth: CGFloat
    let rowHeights: [CGFloat]
    let totalHeight: CGFloat
  }
}
