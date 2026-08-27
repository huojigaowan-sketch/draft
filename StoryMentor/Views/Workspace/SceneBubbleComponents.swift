import SwiftUI

struct SceneStageGroup: Identifiable {
  let stageIndex: Int
  let stageName: String
  let stageTitle: String
  let stageSummary: String
  let contracts: [SceneContract]

  var id: Int { stageIndex }
}

struct SceneBubbleTreeView: View {
  let groups: [SceneStageGroup]
  let selectedContractID: UUID?
  let onSelect: (UUID) -> Void
  let onAddScene: (Int) -> Void

  var body: some View {
    LazyVStack(spacing: 24) {
      ForEach(groups) { group in
        stageBranch(group)
      }
    }
  }

  private func stageBranch(_ group: SceneStageGroup) -> some View {
    VStack(spacing: 12) {
      stageBubble(group)

      SceneBranchConnector(childCount: group.contracts.count)

      LazyVGrid(
        columns: [
          GridItem(
            .adaptive(minimum: 250, maximum: 390),
            spacing: 16,
            alignment: .top
          )
        ],
        alignment: .center,
        spacing: 16
      ) {
        ForEach(Array(group.contracts.enumerated()), id: \.element.id) { index, contract in
          sceneBubble(
            contract,
            ordinal: index + 1,
            totalInStage: group.contracts.count
          )
        }
      }
    }
    .padding(.vertical, 4)
  }

  private func stageBubble(_ group: SceneStageGroup) -> some View {
    let confirmed = group.contracts.filter { $0.selectedSceneOptionID != nil }.count

    return HStack(alignment: .center, spacing: 14) {
      Button {
        if let first = group.contracts.first {
          onSelect(first.id)
        }
      } label: {
        HStack(alignment: .top, spacing: 15) {
          Text(group.stageIndex == Int.max ? "—" : String(format: "%02d", group.stageIndex + 1))
            .font(.system(size: 15, weight: .bold, design: .monospaced))
            .foregroundStyle(StudioTheme.mint)
            .frame(width: 32, alignment: .leading)

          VStack(alignment: .leading, spacing: 6) {
            Text(group.stageName)
              .font(.system(size: 13.5, weight: .semibold))
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)

            Text(group.stageTitle.bubbleFallback("已确认大节拍"))
              .font(.system(size: 21, weight: .semibold, design: .serif))
              .foregroundStyle(.primary)
              .multilineTextAlignment(.leading)
              .fixedSize(horizontal: false, vertical: true)

            Text(group.stageSummary.bubbleFallback("等待展开为一个或多个场景。"))
              .font(.system(size: 14.5))
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.leading)
              .lineSpacing(3)
              .fixedSize(horizontal: false, vertical: true)
          }

          Spacer(minLength: 8)

          Label("\(confirmed)/\(group.contracts.count) 场", systemImage: "rectangle.stack")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(confirmed == group.contracts.count ? StudioTheme.mint : .secondary)
            .lineLimit(1)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity, alignment: .leading)

      if group.stageIndex != Int.max {
        Button {
          onAddScene(group.stageIndex)
        } label: {
          Image(systemName: "plus")
            .font(.system(size: 14, weight: .bold))
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .help("为这个大节拍增加一个场景")
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 17)
    .frame(maxWidth: 760, alignment: .leading)
    .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 46)
  }

  private func sceneBubble(
    _ contract: SceneContract,
    ordinal: Int,
    totalInStage: Int
  ) -> some View {
    let selected = selectedContractID == contract.id
    let appearance = sceneAppearance(contract)

    return Button {
      onSelect(contract.id)
    } label: {
      VStack(alignment: .leading, spacing: 9) {
        HStack(spacing: 8) {
          Text("场景 \(ordinal)/\(totalInStage)")
            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
            .foregroundStyle(appearance.tint)
          Spacer(minLength: 4)
          Label(appearance.label, systemImage: appearance.icon)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(appearance.tint)
            .labelStyle(.titleAndIcon)
        }

        Text(contract.scopeTitle.bubbleFallback("场景待生成"))
          .font(.system(size: 18, weight: .semibold, design: .serif))
          .foregroundStyle(.primary)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)

        Text(contract.scopePurpose.bubbleFallback("等待明确这一场必须完成的状态变化。"))
          .font(.system(size: 14))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.leading)
          .lineSpacing(3)
          .fixedSize(horizontal: false, vertical: true)

        Spacer(minLength: 0)

        if contract.selectedSceneOptionID != nil {
          Label(
            contract.heading.bubbleFallback("已确认场景"),
            systemImage: "location.fill"
          )
          .font(.system(size: 11.5, weight: .medium))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
      .contentShape(Rectangle())
      .animatedStoryBubble(
        tint: appearance.tint,
        cornerRadius: 42,
        isSelected: selected
      )
    }
    .buttonStyle(.plain)
    .help("\(contract.scopeTitle)\n\(contract.scopePurpose)")
    .accessibilityLabel(
      "场景 \(ordinal)，\(contract.scopeTitle)，\(appearance.label)"
    )
    .accessibilityHint("聚焦这个场景")
  }

  private func sceneAppearance(_ contract: SceneContract) -> (
    label: String,
    icon: String,
    tint: Color
  ) {
    if contract.selectedSceneOptionID != nil {
      return ("已确认", "checkmark.seal.fill", StudioTheme.mint)
    }
    if !contract.sceneOptions.isEmpty {
      return ("四选一", "4.circle.fill", StudioTheme.accent)
    }
    if contract.status == "待拆分场景" || contract.status == "范围待生成" {
      return ("待拆分", "rectangle.split.3x1", StudioTheme.warm)
    }
    return ("待生成", "sparkles.rectangle.stack", StudioTheme.sky)
  }
}

private struct SceneBranchConnector: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  let childCount: Int

  var body: some View {
    Group {
      if reduceMotion || scenePhase != .active {
        connector(phase: 0)
      } else {
        TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { context in
          let elapsed = context.date.timeIntervalSinceReferenceDate
          connector(phase: CGFloat(elapsed.truncatingRemainder(dividingBy: 1.4) / 1.4) * 18)
        }
      }
    }
    .frame(height: 30)
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }

  private func connector(phase: CGFloat) -> some View {
    Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
      let center = size.width / 2
      let branchInset = childCount > 1 ? min(size.width * 0.16, 130) : center
      var path = Path()
      path.move(to: CGPoint(x: center, y: 0))
      path.addLine(to: CGPoint(x: center, y: 14))
      if childCount > 1 {
        path.move(to: CGPoint(x: branchInset, y: 14))
        path.addLine(to: CGPoint(x: size.width - branchInset, y: 14))
      }
      path.move(to: CGPoint(x: center, y: 14))
      path.addLine(to: CGPoint(x: center, y: size.height))

      context.stroke(
        path,
        with: .linearGradient(
          Gradient(colors: [StudioTheme.mint, StudioTheme.accent, StudioTheme.warm]),
          startPoint: .zero,
          endPoint: CGPoint(x: size.width, y: size.height)
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

extension String {
  fileprivate func bubbleFallback(_ fallback: String) -> String {
    let clean = trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.isEmpty ? fallback : clean
  }
}
