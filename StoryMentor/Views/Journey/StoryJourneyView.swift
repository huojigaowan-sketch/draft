import SwiftData
import SwiftUI

struct StoryJourneyView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(AISettingsStore.self) private var settings

  @Bindable var project: StoryProject
  let onNavigate: (WorkspaceSection) -> Void

  @State private var selectedStageIndex: Int?
  @State private var isGenerating = false
  @State private var isResearching = false
  @State private var isBuildingBlueprint = false
  @State private var isSyncingBible = false
  @State private var generationRequestID: UUID?
  @State private var progressMessage = ""
  @State private var bibleSyncMessage = ""
  @State private var errorMessage = ""
  @State private var showingError = false

  private var template: StoryStructureTemplate { project.structureTemplate }

  private var decisions: [StoryDecision] {
    project.decisions.sorted {
      if $0.stageIndex == $1.stageIndex { return $0.createdAt < $1.createdAt }
      return $0.stageIndex < $1.stageIndex
    }
  }

  private var resolvedDecisions: [StoryDecision] {
    decisions.filter { $0.selectedOptionID != nil }
  }

  private var activeDecision: StoryDecision? {
    guard let nextIndex = project.nextStructureStageIndex else { return nil }
    return decisions.first {
      $0.stageIndex == nextIndex && $0.selectedOptionID == nil
    }
  }

  private var displayedDecision: StoryDecision? {
    if let selectedStageIndex {
      return decisions.first { $0.stageIndex == selectedStageIndex }
    }
    return activeDecision ?? resolvedDecisions.last
  }

  private var progress: Double {
    guard !template.stages.isEmpty else { return 0 }
    return Double(project.resolvedDecisionCount) / Double(template.stages.count)
  }

  var body: some View {
    ZStack {
      StudioCanvas()

      VStack(spacing: 0) {
        workflowHeader
        Divider().opacity(0.45)

        ScrollView {
          GlassEffectContainer(spacing: 24) {
            centralWorkflow
          }
          .padding(.horizontal, 24)
          .padding(.vertical, 26)
          .frame(maxWidth: 1_680)
          .frame(maxWidth: .infinity)
        }
      }
    }
    .onAppear {
      ensureActiveStage()
      if SceneMappingEngine.synchronizeConfirmedStages(
        in: project,
        modelContext: modelContext
      ) {
        saveSilently()
      }
      if let requestedIndex = project.requestedStructureStageIndex,
        template.stages.indices.contains(requestedIndex)
      {
        selectedStageIndex = requestedIndex
        project.requestedStructureStageIndex = nil
      }
      bootstrapStoryBibleIfNeeded()
    }
    .alert("本轮没有完成", isPresented: $showingError) {
      Button("好", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  private var workflowHeader: some View {
    VStack(spacing: 13) {
      HStack(spacing: 18) {
        VStack(alignment: .leading, spacing: 5) {
          EyebrowLabel(text: "FIXED STRUCTURE", color: StudioTheme.mint)
          Text("结构地图 · 第 2 层")
            .font(.system(size: 29, weight: .semibold, design: .serif))
        }

        Spacer()

        HStack(spacing: 8) {
          Image(systemName: "lock.fill")
          Text(template.name)
        }
        .font(.system(size: 13.5, weight: .semibold))
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(StudioTheme.mint.opacity(0.10), in: Capsule())
        .foregroundStyle(StudioTheme.mint)

        VStack(alignment: .trailing, spacing: 5) {
          Text("\(project.resolvedDecisionCount) / \(template.stages.count)")
            .font(.system(size: 13, weight: .bold, design: .monospaced))
          ProgressView(value: progress)
            .tint(StudioTheme.mint)
            .frame(width: 150)
        }
      }

      StoryHierarchyBar(selection: .journey, onSelect: onNavigate)
        .frame(maxWidth: .infinity, alignment: .center)
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 15)
    .background(.ultraThinMaterial)
  }

  private var centralWorkflow: some View {
    VStack(alignment: .leading, spacing: 30) {
      structureConstellation

      if let decision = displayedDecision {
        stageWorkspace(decision)
      } else if let selectedStageIndex,
        template.stages.indices.contains(selectedStageIndex)
      {
        stagePreview(template.stages[selectedStageIndex], index: selectedStageIndex)
        researchUnavailableBubble
      } else if project.resolvedDecisionCount >= template.stages.count {
        blueprintWorkspace
      } else {
        ProgressView("正在准备当前大节拍…")
          .frame(maxWidth: .infinity, minHeight: 280)
      }
    }
  }

  private var structureConstellation: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .bottom, spacing: 18) {
        VStack(alignment: .leading, spacing: 5) {
          EyebrowLabel(text: "WHOLE STORY PATH", color: StudioTheme.mint)
          Text(project.title)
            .font(.system(size: 24, weight: .semibold, design: .serif))
          Text("每个气泡是一枚大节拍；沿发光路径依次确认，故事才会向下一层展开。")
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        Spacer()

        VStack(alignment: .trailing, spacing: 6) {
          Text("全本大节拍")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          Text("\(project.resolvedDecisionCount) / \(template.stages.count)")
            .font(.system(size: 16, weight: .bold, design: .monospaced))
            .foregroundStyle(StudioTheme.mint)
        }
      }

      JourneyStagePathView(nodes: stagePathNodes) { index in
        selectedStageIndex = index
      }
    }
    .padding(20)
    .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 52)
  }

  private var stagePathNodes: [JourneyStageBubbleModel] {
    let visibleIndex = selectedStageIndex ?? displayedDecision?.stageIndex

    return template.stages.enumerated().map { index, stage in
      let decision = decisions.first { $0.stageIndex == index }
      let status: JourneyStageBubbleModel.Status
      if decision?.selectedOptionID != nil {
        status = .resolved
      } else if project.nextStructureStageIndex == index {
        status = .current
      } else {
        status = .upcoming
      }

      let summary =
        decision?.selectedOption?.title
        ?? (status == .current ? stage.choiceFocus : stage.purpose)

      return JourneyStageBubbleModel(
        index: index,
        stageName: stage.name,
        summary: summary,
        status: status,
        isSelected: visibleIndex == index
      )
    }
  }

  private func stagePreview(_ stage: StructureStage, index: Int) -> some View {
    stageCoreBubble(
      stage,
      index: index,
      phase: "结构预览",
      tint: StudioTheme.sky,
      footer: "它依赖前面大节拍形成的状态。完成前序选择后，这里会自动成为当前工作区。"
    )
  }

  private func stageCoreBubble(
    _ stage: StructureStage,
    index: Int,
    phase: String,
    tint: Color,
    question: String = "",
    coachNote: String = "",
    footer: String = ""
  ) -> some View {
    let plan = project.pacingPlan(for: index, total: template.stages.count)
    let realizedPacing = DramaticProjectionEngine.projection(
      .stage,
      key: String(index),
      in: project
    )

    return VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top, spacing: 16) {
        Text(String(format: "%02d", index + 1))
          .font(.title2.monospacedDigit().weight(.bold))
          .foregroundStyle(tint)
          .frame(width: 48, height: 48)
          .background(tint.opacity(0.11), in: Circle())

        VStack(alignment: .leading, spacing: 6) {
          EyebrowLabel(text: "CURRENT MAJOR BEAT", color: tint)
          Text(stage.name)
            .font(.system(size: 31, weight: .semibold, design: .serif))
          Text(stage.purpose)
            .font(.system(size: 16))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 12)
        PhaseBadge(text: phase)
      }

      VStack(alignment: .leading, spacing: 6) {
        Label("这一枚大节拍要决定什么", systemImage: "scope")
          .font(.caption.weight(.bold))
          .foregroundStyle(StudioTheme.warm)
        Text(stage.choiceFocus)
          .font(.system(size: 16, weight: .medium))
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(15)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(StudioTheme.warm.opacity(0.075), in: RoundedRectangle(cornerRadius: 18))

      if !question.isEmpty {
        VStack(alignment: .leading, spacing: 7) {
          Text(question)
            .font(.system(size: 23, weight: .semibold, design: .serif))
            .fixedSize(horizontal: false, vertical: true)
          if !coachNote.isEmpty {
            Text(coachNote)
              .font(.callout)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }

      HStack(spacing: 16) {
        Label(plan.paceMode.rawValue, systemImage: "waveform.path.ecg")
        Text("目标强度 \(Int(plan.intensity))")
          .monospacedDigit()
        Text(plan.targetEmotion.rawValue)
        Text(plan.eventScale)
      }
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)

      if let realizedPacing {
        HStack(spacing: 14) {
          Label("正文实测", systemImage: "function")
            .foregroundStyle(StudioTheme.mint)
          Text("密度 \(realizedPacing.metrics.updateDensity, format: .number.precision(.fractionLength(2)))")
          Text("平均影响 \(realizedPacing.metrics.averageImpact, format: .number.precision(.fractionLength(2)))")
          Text("不可逆 \(realizedPacing.metrics.irreversibility, format: .number.precision(.fractionLength(2)))")
          Text("\(realizedPacing.metrics.effectiveUpdateCount) 次")
        }
        .font(.caption.monospacedDigit().weight(.semibold))
        .foregroundStyle(.secondary)
      }

      if !footer.isEmpty {
        Label(footer, systemImage: "arrow.triangle.branch")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.horizontal, 30)
    .padding(.vertical, 26)
    .frame(maxWidth: 920)
    .animatedStoryBubble(tint: tint, cornerRadius: 72, isSelected: true)
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private func stageWorkspace(_ decision: StoryDecision) -> some View {
    let isEditable = decision.selectedOptionID == nil
    let stage =
      template.stages.indices.contains(decision.stageIndex)
      ? template.stages[decision.stageIndex]
      : StructureStage(
        id: "legacy",
        name: decision.stageName,
        purpose: decision.coachNote,
        choiceFocus: ""
      )

    stageCoreBubble(
      stage,
      index: decision.stageIndex,
      phase: isEditable ? "当前阶段" : "已经确认",
      tint: isEditable ? StudioTheme.accent : StudioTheme.mint,
      question: decision.question,
      coachNote: decision.coachNote
    )

    if decision.options.isEmpty {
      generateStageCard(decision)
    } else {
      if isEditable, optionsNeedCreativeRefresh(decision) {
        creativeRefreshBanner(decision)
      }

      JourneyChoiceBranchGuide(optionCount: decision.options.count)

      JourneyChoiceOptionsLayout(spacing: 16) {
        ForEach(Array(decision.options.enumerated()), id: \.element.id) { index, option in
          optionCard(option, index: index, decision: decision, editable: isEditable)
        }
      }
    }

    if !isEditable, let selected = decision.selectedOption {
      confirmedStageFooter(selected)
    }

    researchSatellite(decision)

    stageSceneBridge(stageIndex: decision.stageIndex)

    if project.resolvedDecisionCount >= template.stages.count,
      decision.stageIndex == template.stages.count - 1
    {
      blueprintWorkspace
    }
  }

  @ViewBuilder
  private func stageSceneBridge(stageIndex: Int) -> some View {
    let scenes = project.sceneContracts
      .filter { $0.structureStageIndex == stageIndex }
      .sorted { $0.sceneIndex < $1.sceneIndex }

    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          EyebrowLabel(text: "SCENE SATELLITES", color: StudioTheme.accent)
          Text("这个大节拍里的场景")
            .font(.system(size: 22, weight: .semibold, design: .serif))
        }
        Spacer()
        Text("第 2 层 → 第 3 层")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }

      if scenes.isEmpty {
        Text(
          "先完成第二层的全部节拍；随后系统才会进入第三层，让每个节拍展开为一个或多个场景。"
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

        if project.resolvedDecisionCount >= template.stages.count {
          Button("进入场景工作台", systemImage: "rectangle.stack.fill") {
            onNavigate(.scenes)
          }
          .buttonStyle(.borderedProminent)
        }
      } else {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 260), spacing: 12)],
          spacing: 12
        ) {
          ForEach(scenes) { scene in
            Button {
              project.requestedSceneContractID = scene.id
              onNavigate(.scenes)
            } label: {
              VStack(alignment: .leading, spacing: 8) {
                HStack {
                  Text("场 \(scene.sceneIndex)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(StudioTheme.accent)
                  Spacer()
                  Image(systemName: "arrow.down.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                }
                Text(scene.heading.isEmpty ? "未命名场景" : scene.heading)
                  .font(.callout.weight(.semibold))
                  .foregroundStyle(.primary)
                  .fixedSize(horizontal: false, vertical: true)
                Text(scene.scopeTitle.isEmpty ? "场景待生成" : scene.scopeTitle)
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.primary)
                  .fixedSize(horizontal: false, vertical: true)
                Text(
                  scene.scopeExitState.isEmpty
                    ? "等待明确这一场的关键状态变化"
                    : scene.scopeExitState
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
              }
              .padding(14)
              .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
              .animatedStoryBubble(tint: StudioTheme.accent, cornerRadius: 34)
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .padding(20)
    .animatedStoryBubble(tint: StudioTheme.accent, cornerRadius: 52)
  }

  private func creativeRefreshBanner(_ decision: StoryDecision) -> some View {
    HStack(spacing: 12) {
      Image(systemName: "sparkles.rectangle.stack.fill")
        .font(.title3)
        .foregroundStyle(StudioTheme.warm)

      VStack(alignment: .leading, spacing: 3) {
        Text("这四个选项还没有吸收你刚刚的调整")
          .font(.callout.weight(.semibold))
        Text("创意、节奏或调查变化后，旧选项会保留到你主动更新；已确认历史不会改变。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Button("按最新输入更新 4 个选项", systemImage: "arrow.clockwise") {
        generateOptions(for: decision)
      }
      .buttonStyle(.borderedProminent)
      .disabled(isGenerating || isSyncingBible)
    }
    .padding(14)
    .animatedStoryBubble(tint: StudioTheme.warm, cornerRadius: 36)
  }

  private func optionsNeedCreativeRefresh(_ decision: StoryDecision) -> Bool {
    guard !decision.options.isEmpty,
      decision.selectedOptionID == nil
    else {
      return false
    }

    let currentFingerprint = StoryJourneyEngine(settings: settings)
      .optionsContextFingerprint(for: project, decision: decision)
    if !decision.optionsContextFingerprint.isEmpty {
      return currentFingerprint != decision.optionsContextFingerprint
    }

    let changes = [
      decision.authorBriefUpdatedAt,
      project.latestCreativeChange(for: decision.stageIndex),
      decision.researchUpdatedAt,
      project.pacingPlan(
        for: decision.stageIndex,
        total: template.stages.count
      ).updatedAt,
    ].compactMap { $0 }
    guard let latestChange = changes.max() else { return false }
    guard let generatedAt = decision.optionsGeneratedAt else { return true }
    return latestChange > generatedAt
  }

  private func generateStageCard(_ decision: StoryDecision) -> some View {
    VStack(spacing: 18) {
      Image(systemName: "square.grid.2x2.fill")
        .font(.system(size: 32))
        .foregroundStyle(StudioTheme.accent)
      VStack(spacing: 6) {
        Text("准备本阶段的四条道路")
          .font(.title3.weight(.semibold))
        Text("可以先在下方调查真实制度、历史与风俗，再让 DeepSeek 把资料、结构和你的想法合并成四个不同选项。")
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: 660)
      }
      Button {
        generateOptions(for: decision)
      } label: {
        if isGenerating {
          HStack {
            ProgressView().controlSize(.small)
            Text(progressMessage.isEmpty ? "正在生成四个选项…" : progressMessage)
          }
        } else {
          Label(
            decision.researchResult == nil
              ? "生成四个结构选项"
              : "结合调查生成四个选项",
            systemImage: "sparkles"
          )
        }
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .disabled(isGenerating || isSyncingBible)
    }
    .padding(28)
    .frame(maxWidth: .infinity, minHeight: 220)
    .animatedStoryBubble(tint: StudioTheme.accent, cornerRadius: 58)
  }

  private func optionCard(
    _ option: StoryChoiceOption,
    index: Int,
    decision: StoryDecision,
    editable: Bool
  ) -> some View {
    let isSelected = decision.selectedOptionID == option.id
    let tint = optionTint(for: index, isSelected: isSelected)

    return VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top) {
        Text(["A", "B", "C", "D"][min(index, 3)])
          .font(.caption.monospaced().bold())
          .foregroundStyle(.white)
          .frame(width: 28, height: 28)
          .background(tint, in: Circle())
        VStack(alignment: .leading, spacing: 3) {
          Text(option.title)
            .font(.system(.title3, design: .serif, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
      }

      Text(option.pitch)
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)

      optionFact("具体抓手", option.concreteDetail, "pin.fill", StudioTheme.accent)
      optionFact("必须付出", option.consequence, "scalemass.fill", StudioTheme.warm)
      optionFact("后续压力", option.futurePressure, "arrow.up.right", StudioTheme.mint)
      ForEach(option.plannedStateChanges ?? []) { mutation in
        optionFact(
          "\(mutation.dimension.rawValue) · \(mutation.subject)",
          "\(mutation.beforeValue) → \(mutation.afterValue)",
          mutation.dimension.symbol,
          StudioTheme.mint
        )
      }
      if let audience = option.audienceUpdate, !audience.isEmpty {
        optionFact("观众认知更新", audience, "eye.fill", StudioTheme.sky)
      }
      if let forbidden = option.forbiddenChanges, !forbidden.isEmpty {
        optionFact("不得提前改变", forbidden.joined(separator: "；"), "lock.fill", StudioTheme.warm)
      }

      if !option.realityTexture.isEmpty {
        optionFact("现实质感", option.realityTexture, "globe.asia.australia.fill", .cyan)
      }
      if !option.paceEffect.isEmpty {
        optionFact("节奏执行", option.paceEffect, "metronome.fill", StudioTheme.warm)
      }
      if !option.emotionShift.isEmpty {
        optionFact("情绪变化", option.emotionShift, "waveform.path.ecg", .pink)
      }
      if !option.eventScale.isEmpty {
        optionFact("事件尺度", option.eventScale, "arrow.up.forward.circle.fill", StudioTheme.mint)
      }

      if !option.sampleMoment.isEmpty {
        Text("“\(option.sampleMoment)”")
          .font(.callout.italic())
          .foregroundStyle(.secondary)
          .padding(11)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
      }

      if editable {
        Divider()
        Button("选择这条道路", systemImage: "checkmark.seal.fill") {
          confirm(option, in: decision)
        }
        .buttonStyle(.borderedProminent)
        .tint(StudioTheme.mint)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .disabled(isGenerating || isSyncingBible)
      } else if isSelected {
        Label("本阶段正式选择", systemImage: "checkmark.seal.fill")
          .font(.caption.weight(.semibold))
          .foregroundStyle(StudioTheme.mint)
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .animatedStoryBubble(tint: tint, cornerRadius: 48, isSelected: isSelected)
  }

  private func optionTint(for index: Int, isSelected: Bool) -> Color {
    if isSelected { return StudioTheme.mint }
    switch index % 4 {
    case 0: return StudioTheme.accent
    case 1: return StudioTheme.sky
    case 2: return StudioTheme.warm
    default: return .pink
    }
  }

  private func optionFact(
    _ title: String,
    _ value: String,
    _ icon: String,
    _ tint: Color
  ) -> some View {
    HStack(alignment: .top, spacing: 9) {
      Image(systemName: icon)
        .foregroundStyle(tint)
        .frame(width: 18)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.caption2.weight(.bold))
          .foregroundStyle(.secondary)
        Text(value.isEmpty ? "尚未形成" : value)
          .font(.caption)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func confirmedStageFooter(_ option: StoryChoiceOption) -> some View {
    HStack(spacing: 12) {
      Image(systemName: "checkmark.seal.fill")
        .font(.title2)
        .foregroundStyle(StudioTheme.mint)
      VStack(alignment: .leading, spacing: 3) {
        Text("这一阶段已成为正式故事事实")
          .font(.headline)
        Text("你仍可查看全部候选和历史，但后续写作只会沿“\(option.title)”继续。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(16)
    .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 42, isSelected: true)
  }

  private var researchUnavailableBubble: some View {
    ContentUnavailableView(
      "阶段调查尚未开放",
      systemImage: "globe.desk.fill",
      description: Text("完成前序大节拍后，这一阶段会自动开放调查与四方案生成。")
    )
    .padding(24)
    .frame(maxWidth: .infinity, minHeight: 190)
    .animatedStoryBubble(tint: StudioTheme.sky, cornerRadius: 52)
  }

  private func researchSatellite(_ decision: StoryDecision) -> some View {
    researchContent(decision)
      .padding(22)
      .animatedStoryBubble(tint: StudioTheme.sky, cornerRadius: 52)
  }

  private func researchContent(_ decision: StoryDecision) -> some View {
    let isEditable = decision.selectedOptionID == nil
    return VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 6) {
        EyebrowLabel(text: "RESEARCH SATELLITE", color: StudioTheme.sky)
        Text("本阶段调查")
          .font(.system(.title2, design: .serif, weight: .semibold))
        Text("只收集当前结构节点真正需要的制度、历史、风俗与现实细节。")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(alignment: .leading, spacing: 10) {
        TextField(
          "例如：伊拉克婚礼习俗、美国国会听证流程",
          text: binding(
            get: { decision.researchQuery },
            set: { decision.researchQuery = $0 }
          ),
          axis: .vertical
        )
        .textFieldStyle(.roundedBorder)
        .lineLimit(2...4)

        Picker(
          "深度",
          selection: binding(
            get: { decision.researchDepth },
            set: { decision.researchDepth = $0 }
          )
        ) {
          ForEach(ResearchDepth.allCases) { depth in
            Text(depth.rawValue).tag(depth)
          }
        }
        .pickerStyle(.segmented)

        Button {
          runResearch(for: decision)
        } label: {
          if isResearching {
            HStack {
              ProgressView().controlSize(.small)
              Text("正在跨来源调查…")
            }
          } else {
            Label(
              decision.researchResult == nil ? "开始全网调查" : "更新本阶段调查",
              systemImage: "network"
            )
          }
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity)
        .keyboardShortcut(.return, modifiers: [.command])
        .disabled(
          !isEditable || isResearching
            || decision.researchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        if !isEditable {
          Text("阶段确认后，调查随该阶段一起封存。")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }

      if let result = decision.researchResult {
        researchResultSections(result)
      } else {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 240), spacing: 12)],
          spacing: 12
        ) {
          researchHint("概念与机构", "解释陌生名词、权力关系和实际流程", "building.columns")
          researchHint("地域与风俗", "补足语言、礼仪、物件与生活质感", "globe.asia.australia")
          researchHint("历史与时间线", "识别因果背景、相似事件和时代限制", "clock.arrow.circlepath")
          researchHint("戏剧可用性", "把事实转成关系压力、选择与代价", "theatermasks.fill")
        }
        .padding(.top, 4)
      }
    }
  }

  @ViewBuilder
  private func researchResultSections(_ result: RealityResearchResult) -> some View {
    Divider()

    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("事实底座", systemImage: "checkmark.shield.fill")
          .font(.headline)
        Spacer()
        Text("\(result.sources.count) 个来源")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      Text(result.summary)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    if !result.entities.isEmpty {
      researchSection("人物、机构与概念", icon: "person.2.badge.gearshape.fill") {
        ForEach(result.entities.prefix(10)) { entity in
          VStack(alignment: .leading, spacing: 2) {
            HStack {
              Text(entity.name).font(.caption.weight(.semibold))
              Text(entity.kind)
                .font(.caption2)
                .foregroundStyle(StudioTheme.accent)
            }
            Text(entity.detail)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
      }
    }

    if !result.claims.isEmpty {
      researchSection("制度、风俗与现实机制", icon: "building.columns.fill") {
        ForEach(result.claims.prefix(10)) { claim in
          VStack(alignment: .leading, spacing: 2) {
            Text(claim.dimension)
              .font(.caption2.weight(.bold))
              .foregroundStyle(StudioTheme.mint)
            Text(claim.text)
              .font(.caption)
          }
        }
      }
    }

    if !result.timeline.isEmpty {
      researchSection("历史与时间线", icon: "clock.fill") {
        ForEach(result.timeline.prefix(8)) { item in
          HStack(alignment: .top, spacing: 8) {
            Text(item.date)
              .font(.caption2.monospacedDigit().weight(.bold))
              .foregroundStyle(StudioTheme.warm)
              .frame(width: 70, alignment: .leading)
            Text(item.event)
              .font(.caption)
          }
        }
      }
    }

    if !result.dramaticPressures.isEmpty {
      researchSection("可转化的戏剧压力", icon: "bolt.heart.fill") {
        ForEach(result.dramaticPressures.prefix(8)) { pressure in
          VStack(alignment: .leading, spacing: 3) {
            Text(pressure.title)
              .font(.caption.weight(.semibold))
            Text(pressure.question)
              .font(.caption)
            Text(pressure.angle)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          .padding(9)
          .background(StudioTheme.warm.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
        }
      }
    }

    if !result.sources.isEmpty {
      researchSection("来源账本", icon: "books.vertical.fill") {
        ForEach(result.sources.prefix(10)) { source in
          if let url = URL(string: source.url) {
            Link(destination: url) {
              VStack(alignment: .leading, spacing: 2) {
                Text(source.title)
                  .font(.caption.weight(.semibold))
                  .lineLimit(2)
                Text(
                  [source.publisher, source.kind]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }
      }
    }

    Label("这些资料会自动进入本阶段的四选一与单项重做，不会污染其他项目。", systemImage: "lock.doc.fill")
      .font(.caption2)
      .foregroundStyle(.secondary)
      .padding(.top, 4)
  }

  private func researchSection<Content: View>(
    _ title: String,
    icon: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(title, systemImage: icon)
        .font(.headline)
      content()
    }
    .padding(13)
    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 13))
  }

  private func researchHint(
    _ title: String,
    _ detail: String,
    _ icon: String
  ) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: icon)
        .foregroundStyle(StudioTheme.accent)
        .frame(width: 22)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.caption.weight(.semibold))
        Text(detail).font(.caption2).foregroundStyle(.secondary)
      }
    }
  }

  private var blueprintWorkspace: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Image(systemName: "checkmark.seal.fill")
          .font(.title)
          .foregroundStyle(StudioTheme.mint)
        VStack(alignment: .leading, spacing: 3) {
          EyebrowLabel(text: "BLUEPRINT SATELLITE", color: StudioTheme.mint)
          Text("结构骨架已经完成")
            .font(.system(.title2, design: .serif, weight: .semibold))
          Text("全部阶段已确认，可以整理第二层的全本路线，然后进入第三层逐节拍拆分场景。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      if !project.blueprintText.isEmpty {
        Text(project.blueprintText)
          .font(.callout)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }

      Button {
        if project.blueprintText.isEmpty {
          buildBlueprint(navigateToScenes: true)
        } else {
          onNavigate(.scenes)
        }
      } label: {
        if isBuildingBlueprint {
          HStack {
            ProgressView().controlSize(.small)
            Text("正在整理全本路线…")
          }
        } else {
          Label(
            project.blueprintText.isEmpty
              ? "整理全本路线"
              : "进入场景工作台",
            systemImage: "rectangle.stack.badge.plus"
          )
        }
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .disabled(
        isBuildingBlueprint
          || (project.blueprintText.isEmpty && !settings.hasAPIKey)
      )

      if !settings.hasAPIKey {
        Text("先在设置中保存 DeepSeek API 密钥。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(24)
    .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 54, isSelected: true)
  }

  private func generateOptions(for decision: StoryDecision) {
    let generationStartedAt = Date.now
    let requestID = UUID()
    let requestedStageIndex = decision.stageIndex
    let engine = StoryJourneyEngine(settings: settings)
    let requestedFingerprint = engine.optionsContextFingerprint(
      for: project,
      decision: decision
    )
    decision.optionsRequestToken = requestID
    generationRequestID = requestID
    isGenerating = true
    Task {
      progressMessage =
        settings.useApplePreprocessing
        ? "本机整理项目记忆，再请求四个选项…"
        : "正在请求四个选项…"
      defer {
        if decision.optionsRequestToken == requestID {
          decision.optionsRequestToken = nil
        }
        if generationRequestID == requestID {
          generationRequestID = nil
          isGenerating = false
          progressMessage = ""
        }
      }
      do {
        let outcome = try await engine.nextDecision(
          for: project,
          stageResearch: decision.researchResult?.promptContext ?? "",
          authorBrief: decision.authorBrief
        )
        guard generationRequestID == requestID,
          decision.optionsRequestToken == requestID,
          decision.selectedOptionID == nil,
          decision.stageIndex == requestedStageIndex,
          project.nextStructureStageIndex == requestedStageIndex
        else {
          return
        }
        guard
          engine.optionsContextFingerprint(
            for: project,
            decision: decision
          ) == requestedFingerprint
        else {
          presentMessage("生成期间项目输入发生了变化。旧响应已丢弃，请按最新输入重新生成。")
          return
        }
        decision.phaseRawValue = outcome.stage.name
        decision.stageIndex = outcome.stageIndex
        decision.question = outcome.result.question
        decision.coachNote = outcome.result.coachNote
        decision.options = outcome.result.options
        decision.optionsGeneratedAt = generationStartedAt
        decision.optionsContextFingerprint = requestedFingerprint
        project.touch()
        try ProjectPersistenceStore.savePendingChanges(in: modelContext)
      } catch {
        if decision.optionsRequestToken == requestID {
          present(error)
        }
      }
    }
  }

  private func confirm(_ option: StoryChoiceOption, in decision: StoryDecision) {
    guard !isGenerating,
      decision.selectedOptionID == nil,
      decision.options.contains(where: { $0.id == option.id })
    else {
      return
    }
    decision.selectedOptionID = option.id
    decision.selectedAnswerText = """
      \(option.title)：\(option.pitch)
      具体抓手：\(option.concreteDetail)
      必须付出：\(option.consequence)
      """
    decision.resolvedAt = .now
    ProjectPreferenceEngine.record(.selected, option: option, in: project)
    rebuildStoryPath()
    SceneMappingEngine.synchronizeConfirmedStages(
      in: project,
      modelContext: modelContext
    )
    selectedStageIndex = nil
    saveSilently()
    ensureActiveStage()
    synchronizeStoryBible(fallbackSeed: option.pitch)
  }

  private func synchronizeStoryBible(fallbackSeed: String) {
    Task {
      isSyncingBible = true
      bibleSyncMessage = ""
      defer { isSyncingBible = false }
      do {
        if !project.characters.contains(where: { $0.role == .protagonist }) {
          let protagonist = StoryCharacter(
            name: "主人公",
            role: .protagonist,
            seedText: fallbackSeed,
            project: project
          )
          modelContext.insert(protagonist)
          project.characters.append(protagonist)
        }
        let outcome = await StoryBibleSyncEngine(settings: settings)
          .synchronize(project)
        try ProjectPersistenceStore.savePendingChanges(in: modelContext)
        bibleSyncMessage = outcome.note
      } catch {
        present(error)
      }
    }
  }

  private func bootstrapStoryBibleIfNeeded() {
    guard !isSyncingBible,
      project.storyBibleDigest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let fallback = resolvedDecisions.last?.selectedOption?.pitch
    else {
      return
    }
    synchronizeStoryBible(fallbackSeed: fallback)
  }

  private func runResearch(for decision: StoryDecision) {
    Task {
      isResearching = true
      defer { isResearching = false }
      do {
        let firecrawlKey = (try? ResearchCredentialStore.readFirecrawlKey()) ?? ""
        let stage =
          template.stages.indices.contains(decision.stageIndex)
          ? template.stages[decision.stageIndex]
          : nil
        let request = RealityResearchRequest(
          title: "\(project.title) · \(decision.stageName)",
          query: decision.researchQuery,
          sourceURL: "",
          sourceText: String(project.sourceText.prefix(8_000)),
          authorIntent: """
            当前结构：\(template.name)
            当前阶段：\(stage?.name ?? decision.stageName)
            阶段目标：\(stage?.purpose ?? "")
            作者注入：\(decision.authorBrief)
            作者创意方向与后来注入：\(project.creativeContext(for: decision.stageIndex))
            """,
          depth: decision.researchDepth.rawValue,
          maxSources: decision.researchDepth.sourceLimit,
          firecrawlAPIKey: firecrawlKey
        )
        let result = try await RealityResearchEngine().research(request)
        decision.researchResult = result
        project.touch()
        try ProjectPersistenceStore.savePendingChanges(in: modelContext)
      } catch {
        present(error)
      }
    }
  }

  private func buildBlueprint(navigateToScenes: Bool = false) {
    Task {
      isBuildingBlueprint = true
      defer { isBuildingBlueprint = false }
      do {
        let outcome = try await StoryJourneyEngine(settings: settings).blueprint(for: project)
        applyBlueprint(outcome.blueprint)
        try ProjectPersistenceStore.savePendingChanges(in: modelContext)
        if navigateToScenes {
          onNavigate(.scenes)
        }
      } catch {
        present(error)
      }
    }
  }

  private func applyBlueprint(_ blueprint: JourneyBlueprint) {
    if project.logline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      project.logline = blueprint.logline
    }
    if project.themeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      project.themeText = blueprint.theme
    }
    project.structureText = """
      【锁定结构】\(template.name)

      【主人公弧线】
      \(blueprint.protagonistArc)

      【对抗力量】
      \(blueprint.antagonistDesign)

      【第一部分】
      \(blueprint.actOne)

      【第二部分】
      \(blueprint.actTwo)

      【第三部分】
      \(blueprint.actThree)
      """
    project.blueprintText = """
      \(blueprint.title)
      \(blueprint.logline)

      主题：\(blueprint.theme)
      主人公：\(blueprint.protagonistArc)
      对抗力量：\(blueprint.antagonistDesign)

      下一步：\(blueprint.nextWritingTask)
      """
    project.characterBibleText = blueprint.protagonistArc
    project.themeBibleText = blueprint.theme
    if project.coreConflictText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      project.coreConflictText = blueprint.antagonistDesign
    }
    project.storyBibleDigest = """
      【人物小传】
      \(project.characterBibleText)

      【世界规则】
      \(project.worldBibleText.isEmpty ? "以项目世界模块为准" : project.worldBibleText)

      【主题命题】
      \(project.themeBibleText)

      【核心冲突】
      \(project.coreConflictText)
      """
    project.storyBibleRevision += 1
    project.storyBibleUpdatedAt = .now
    project.storyBibleSyncNote = "全本路线已回写剧本圣经"
    if let protagonist = project.characters.first(where: { $0.role == .protagonist }) {
      if protagonist.arc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        protagonist.arc = blueprint.protagonistArc
      }
      protagonist.touch()
    }
    project.touch()
  }

  private func ensureActiveStage() {
    guard project.isStructureLocked,
      activeDecision == nil,
      let index = project.nextStructureStageIndex
    else {
      return
    }
    let stage = template.stages[index]
    let queryParts = [
      project.sourceTitle,
      project.logline,
      stage.name,
      stage.choiceFocus,
    ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    let decision = StoryDecision(
      stageName: stage.name,
      stageIndex: index,
      question: "",
      coachNote: "",
      options: [],
      researchQuery: queryParts.joined(separator: " "),
      project: project
    )
    project.decisions.append(decision)
    modelContext.insert(decision)
    saveSilently()
  }

  private func rebuildStoryPath() {
    project.storyPathText = project.decisions
      .filter { $0.selectedOptionID != nil }
      .sorted { $0.stageIndex < $1.stageIndex }
      .map { "第\($0.stageIndex + 1)阶段 · \($0.stageName)\n\($0.selectedAnswerText)" }
      .joined(separator: "\n\n")
    project.touch()
  }

  private func binding<Value>(
    get: @escaping @MainActor @Sendable () -> Value,
    set: @escaping @MainActor @Sendable (Value) -> Void
  ) -> Binding<Value> {
    Binding(get: get, set: set)
  }

  private func saveSilently() {
    do {
      try ProjectPersistenceStore.savePendingChanges(in: modelContext)
    } catch {
      present(error)
    }
  }

  private func present(_ error: Error) {
    presentMessage(error.localizedDescription)
  }

  private func presentMessage(_ message: String) {
    errorMessage = message
    showingError = true
  }
}
