import SwiftUI

/// A lightweight causal branch shared by the non-screenplay bubble workspaces.
/// It is decorative only; Reduce Motion and inactive windows render a static path.
struct BubbleWorkspaceConnector: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  let tint: Color
  var branchCount = 1
  var height: CGFloat = 48

  var body: some View {
    Group {
      if reduceMotion || scenePhase != .active {
        connector(phase: 0)
      } else {
        TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { context in
          let elapsed = context.date.timeIntervalSinceReferenceDate
          connector(
            phase: CGFloat(elapsed.truncatingRemainder(dividingBy: 1.4) / 1.4) * 18
          )
        }
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: height)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func connector(phase: CGFloat) -> some View {
    Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
      let count = max(branchCount, 1)
      let source = CGPoint(x: size.width / 2, y: 0)
      let laneWidth = size.width / CGFloat(count)

      for index in 0..<count {
        let target = CGPoint(x: laneWidth * (CGFloat(index) + 0.5), y: size.height)
        var path = Path()
        path.move(to: source)
        path.addCurve(
          to: target,
          control1: CGPoint(x: source.x, y: size.height * 0.55),
          control2: CGPoint(x: target.x, y: size.height * 0.55)
        )
        context.stroke(
          path,
          with: .linearGradient(
            Gradient(colors: [tint, StudioTheme.accent, StudioTheme.mint]),
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
