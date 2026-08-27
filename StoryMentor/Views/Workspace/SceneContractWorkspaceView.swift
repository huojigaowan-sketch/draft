import SwiftData
import SwiftUI

struct SceneContractWorkspaceView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(AISettingsStore.self) private var aiSettings
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @Bindable var project: StoryProject
  let onNavigate: (WorkspaceSection) -> Void

  @State private var selectedContractID: UUID?
  @State private var previewOptionID: UUID?
  @State private var generatingContractID: UUID?
  @State private var planningStageIndex: Int?
  @State private var workspaceScrollRequest = 0
  @State private var errorMessage = ""
  @State private var showingError = false

  private var contracts: [SceneContract] {
    project.sceneContracts.sorted { $0.sceneIndex < $1.sceneIndex }
  }

  private var selectedContract: SceneContract? {
    guard let selectedContractID else { return contracts.first }
    return contracts.first { $0.id == selectedContractID } ?? contracts.first
  }

  private var selectedPreviewOption: SceneChoiceOption? {
    guard let selectedContract else { return nil }
    return selectedContract.sceneOptions.first { $0.id == previewOptionID }
      ?? selectedContract.sceneOptions.first
  }

  private var stageGroups: [SceneStageGroup] {
    let confirmedDecisions = project.decisions.filter { $0.selectedOptionID != nil }
    let nsirTransitionIDs = Set(project.nsirWorkspace.transitions.map(\.id))
    return Dictionary(grouping: contracts) { $0.structureStageIndex ?? Int.max }
      .map { stageIndex, groupedContracts in
        let decision =
          confirmedDecisions
          .filter { $0.stageIndex == stageIndex }
          .max { $0.createdAt < $1.createdAt }
        let isNSIRGroup = stageIndex == Int.max && groupedContracts.contains {
          $0.sourceKindRawValue == SceneContractSourceKind.nsirTransition.rawValue
            || nsirTransitionIDs.contains($0.id)
        }
        return SceneStageGroup(
          stageIndex: stageIndex,
          stageName: decision?.stageName
            ?? (isNSIRGroup ? "来自叙事结构推演" : stageName(for: groupedContracts[0])),
          stageTitle: decision?.selectedOption?.title
            ?? (isNSIRGroup ? "已提交结构转移" : ""),
          stageSummary: decision?.selectedOption?.pitch
            ?? (isNSIRGroup ? "已确认的因果转移按顺序进入场景四选一。" : ""),
          contracts: groupedContracts.sorted {
            if $0.stageSceneOrdinal == $1.stageSceneOrdinal {
              return $0.sceneIndex < $1.sceneIndex
            }
            return $0.stageSceneOrdinal < $1.stageSceneOrdinal
          }
        )
      }
      .sorted { $0.stageIndex < $1.stageIndex }
  }

  private var confirmedCount: Int {
    contracts.count { $0.selectedSceneOptionID != nil }
  }

  private var structureReady: Bool {
    !project.nsirWorkspace.transitions.isEmpty
      || (project.isStructureLocked
        && !project.structureTemplate.stages.isEmpty
        && project.nextStructureStageIndex == nil)
  }

  private var allScenesConfirmed: Bool {
    !contracts.isEmpty
      && contracts.allSatisfy { $0.selectedSceneOptionID != nil }
      && contracts.allSatisfy(SceneCompilationEngine.isComplete)
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider().opacity(0.42)

      ScrollViewReader { proxy in
        ScrollView {
          GlassEffectContainer(spacing: 8) {
            VStack(alignment: .leading, spacing: 34) {
              sceneTreeOverview
              sceneWorkspace
                .id("scene-workspace")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: workspaceScrollRequest) {
          if reduceMotion {
            proxy.scrollTo("scene-workspace", anchor: .top)
          } else {
            withAnimation(.smooth(duration: 0.35)) {
              proxy.scrollTo("scene-workspace", anchor: .top)
            }
          }
        }
      }
    }
    .background(StudioCanvas())
    .task {
      let addedNSIRMappings = SceneMappingEngine.synchronizeNSIRTransitions(
        in: project,
        document: project.nsirWorkspace,
        modelContext: modelContext
      )
      let addedLegacyMappings = SceneMappingEngine.synchronizeConfirmedStages(
        in: project,
        modelContext: modelContext
      )
      if addedNSIRMappings || addedLegacyMappings {
        savePendingChanges()
      }
      if let requestedID = project.requestedSceneContractID,
        contracts.contains(where: { $0.id == requestedID })
      {
        selectedContractID = requestedID
        project.requestedSceneContractID = nil
        workspaceScrollRequest += 1
      } else {
        selectFirstIfNeeded()
      }
      syncPreviewSelection()
    }
    .onChange(of: project.sceneContracts.count) {
      selectFirstIfNeeded()
    }
    .onChange(of: selectedContractID) {
      syncPreviewSelection()
    }
    .alert("场景工作台", isPresented: $showingError) {
      Button("好", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  private var header: some View {
    VStack(spacing: 12) {
      HStack(spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
          Text("场景工作台")
            .font(.system(size: 27, weight: .semibold, design: .serif))
          Text("实验命题 → 结构转移 → 场景四选一 · \(confirmedCount)/\(contracts.count) 场已确认")
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
        }

        Spacer()

        primaryAction
      }

      StoryHierarchyBar(selection: .scenes, onSelect: onNavigate)
        .frame(maxWidth: .infinity, alignment: .center)
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 13)
    .background(.thinMaterial)
  }

  @ViewBuilder
  private var primaryAction: some View {
    if !structureReady {
      Button("返回叙事编译台", systemImage: "arrow.up.left") {
        onNavigate(.compiler)
      }
      .buttonStyle(.borderedProminent)
    } else if allScenesConfirmed {
      Button(
        project.screenplayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? "进入小节拍选择"
          : "进入小节拍与剧本",
        systemImage: "arrow.right"
      ) {
        openScreenplay()
      }
      .buttonStyle(.borderedProminent)
    } else if let contract = selectedContract {
      if needsScopePlanning(contract) {
        Button("拆分这个大节拍", systemImage: "rectangle.split.3x1") {
          planStageScopes(for: contract)
        }
        .buttonStyle(.borderedProminent)
        .disabled(planningStageIndex != nil || !aiSettings.hasAPIKey)
      } else if contract.sceneOptions.isEmpty && !canGenerateOptions(for: contract) {
        Button("返回叙事编译台", systemImage: "arrow.up.left") {
          onNavigate(.compiler)
        }
        .buttonStyle(.borderedProminent)
      } else {
        Button(
          contract.sceneOptions.isEmpty ? "生成 4 个场景方案" : "查看 4 个方案",
          systemImage: "sparkles.rectangle.stack"
        ) {
          if contract.sceneOptions.isEmpty {
            generateOptions(for: contract)
          } else {
            workspaceScrollRequest += 1
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(
          contract.selectedSceneOptionID != nil
            || generatingContractID != nil
            || !aiSettings.hasAPIKey
        )
      }
    }
  }

  @ViewBuilder
  private var sceneTreeOverview: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Label("结构转移 → 场景树", systemImage: "point.3.connected.trianglepath.dotted")
          .font(.system(size: 22, weight: .semibold, design: .rounded))
        Spacer(minLength: 12)
        Text("全部场景 · \(confirmedCount)/\(contracts.count) 已确认")
          .font(.system(size: 13, weight: .semibold, design: .monospaced))
          .foregroundStyle(.secondary)
          .contentTransition(.numericText())
      }

      if stageGroups.isEmpty {
        ContentUnavailableView(
          structureReady ? "正在建立场景树" : "第 3 层尚未解锁",
          systemImage: "point.3.connected.trianglepath.dotted",
          description: Text(
            structureReady
              ? "全部大节拍已确认，系统正在逐一建立场景。"
              : "先在叙事编译台确认必要的状态转移；随后每个已确认的因果单元会展开为一个或多个场景。"
          )
        )
        .frame(maxWidth: .infinity, minHeight: 260)
        .animatedStoryBubble(tint: StudioTheme.accent, cornerRadius: 52)
      } else {
        SceneBubbleTreeView(
          groups: stageGroups,
          selectedContractID: selectedContract?.id
        ) { contractID in
          selectedContractID = contractID
          workspaceScrollRequest += 1
        } onAddScene: { stageIndex in
          let contract = SceneMappingEngine.appendScope(
            toStage: stageIndex,
            in: project,
            modelContext: modelContext
          )
          savePendingChanges()
          selectedContractID = contract.id
          workspaceScrollRequest += 1
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private var sceneWorkspace: some View {
    if let contract = selectedContract {
      VStack(alignment: .leading, spacing: 24) {
        Label("当前场景", systemImage: "scope")
          .font(.system(size: 22, weight: .semibold, design: .rounded))

        VStack(alignment: .leading, spacing: 14) {
          sceneIdentity(contract)
          scopeCard(contract)
        }

        if needsScopePlanning(contract) {
          scopePlanningPrompt(contract)
        } else if contract.selectedSceneOptionID == nil {
          optionWorkshop(contract)
        } else {
          confirmedSceneEditor(contract)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      ContentUnavailableView(
        structureReady ? "等待大节拍映射" : "先完成全部大节拍",
        systemImage: "rectangle.stack",
        description: Text(
          structureReady
            ? "每个大节拍会对应一个场景组。"
            : "第二层全部完成后，第三层才开始逐场选择。"
        )
      )
    }
  }

  private func sceneIdentity(_ contract: SceneContract) -> some View {
    let position = scenePosition(for: contract)
    return HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(stageName(for: contract))
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(StudioTheme.accent)
      Image(systemName: "chevron.right")
        .font(.caption2.weight(.bold))
        .foregroundStyle(.tertiary)
      Text("场景 \(position.ordinal)/\(position.total)")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.secondary)
      Spacer()
      PhaseBadge(text: needsScopePlanning(contract) ? "场景待生成" : contract.status)
    }
  }

  private func scopeCard(_ contract: SceneContract) -> some View {
    let source = sourceContext(for: contract)
    return VStack(alignment: .leading, spacing: 15) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          EyebrowLabel(
            text: source?.kind == .nsirTransition
              ? "STRUCTURE TRANSITION → SCENES"
              : "MAJOR BEAT → SCENES",
            color: source == nil ? StudioTheme.warm : StudioTheme.mint
          )
          Text(contract.scopeTitle.nonemptyFallback("这个大节拍中的场景"))
            .font(.system(size: 28, weight: .semibold, design: .serif))
        }
        Spacer()
        Label(
          source?.sourceBadge ?? "来源尚未确认",
          systemImage: source == nil ? "exclamationmark.triangle.fill" : "link"
        )
          .font(.caption.weight(.semibold))
          .foregroundStyle(source == nil ? StudioTheme.warm : StudioTheme.mint)
      }

      Text(contract.scopePurpose.nonemptyFallback("等待 DeepSeek 把已确认大节拍拆成必要且最少的场景。"))
        .font(.system(size: 17))
        .lineSpacing(5)
        .fixedSize(horizontal: false, vertical: true)

      HStack(alignment: .top, spacing: 14) {
        scopeState(
          "进入状态",
          contract.scopeEntryState,
          icon: "arrow.right.to.line.compact",
          tint: StudioTheme.warm
        )
        scopeState(
          "必须发生的变化",
          contract.scopeExitState,
          icon: "bolt.fill",
          tint: StudioTheme.accent
        )
      }
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 22)
    .frame(maxWidth: 1_080, alignment: .leading)
    .animatedStoryBubble(
      tint: sceneStatusColor(contract),
      cornerRadius: 58,
      isSelected: true
    )
    .frame(maxWidth: .infinity)
  }

  private func scopeState(_ title: String, _ value: String, icon: String, tint: Color) -> some View
  {
    VStack(alignment: .leading, spacing: 6) {
      Label(title, systemImage: icon)
        .font(.system(size: 13.5, weight: .semibold))
        .foregroundStyle(tint)
      Text(value.nonemptyFallback("待明确"))
        .font(.system(size: 15))
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(14)
    .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
    .animatedStoryBubble(tint: tint, cornerRadius: 30)
  }

  private func scopePlanningPrompt(_ contract: SceneContract) -> some View {
    HStack(alignment: .center, spacing: 16) {
      Image(systemName: "rectangle.split.3x1")
        .font(.system(size: 27))
        .foregroundStyle(StudioTheme.accent)
      VStack(alignment: .leading, spacing: 4) {
        Text("先确定这个大节拍需要几场")
          .font(.system(size: 19, weight: .semibold, design: .serif))
        Text("DeepSeek 会按最少必要原则拆成 1–4 个场景；每个场景围绕一个明确任务，并可由多个小节拍完成。")
          .font(.system(size: 14.5))
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button {
        planStageScopes(for: contract)
      } label: {
        if planningStageIndex == contract.structureStageIndex {
          ProgressView().controlSize(.small)
        } else {
          Label("生成场景", systemImage: "sparkles")
        }
      }
      .buttonStyle(.borderedProminent)
      .disabled(planningStageIndex != nil || !aiSettings.hasAPIKey)
    }
    .padding(.horizontal, 22)
    .padding(.vertical, 20)
    .animatedStoryBubble(tint: StudioTheme.accent, cornerRadius: 44)
  }

  @ViewBuilder
  private func optionWorkshop(_ contract: SceneContract) -> some View {
    let canGenerate = canGenerateOptions(for: contract)
    VStack(alignment: .leading, spacing: 15) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("选择这一场如何发生")
            .font(.system(size: 23, weight: .semibold, design: .serif))
          Text("四个方案必须兑现同一个 before → after 状态契约，只改变造成变化的行动机制。")
            .font(.system(size: 14.5))
            .foregroundStyle(.secondary)
        }
        Spacer()
        if !contract.sceneOptions.isEmpty {
          Button("重新生成", systemImage: "arrow.clockwise") {
            generateOptions(for: contract)
          }
          .buttonStyle(.bordered)
          .disabled(generatingContractID != nil || !canGenerate)
        }
      }

      if contract.sceneOptions.isEmpty {
        if canGenerate {
          HStack(spacing: 16) {
            Image(systemName: "sparkles.rectangle.stack")
              .font(.system(size: 29))
              .foregroundStyle(StudioTheme.accent)
            VStack(alignment: .leading, spacing: 5) {
              Text("还没有场景方案")
                .font(.headline)
              Text("DeepSeek 将结合已提交结构来源、前后场景和剧本圣经，生成恰好四个选项。")
                .font(.system(size: 14.5))
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
              generateOptions(for: contract)
            } label: {
              if generatingContractID == contract.id {
                HStack {
                  ProgressView().controlSize(.small)
                  Text("生成中…")
                }
              } else {
                Label("生成 4 个方案", systemImage: "sparkles")
              }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(generatingContractID != nil || !aiSettings.hasAPIKey)
          }
          .padding(.horizontal, 22)
          .padding(.vertical, 20)
          .animatedStoryBubble(tint: StudioTheme.accent, cornerRadius: 44)
        } else {
          sourceUnavailablePrompt
        }
      } else {
        LazyVGrid(
          columns: [
            GridItem(
              .adaptive(minimum: 280, maximum: 430),
              spacing: 16,
              alignment: .top
            )
          ],
          spacing: 16
        ) {
          ForEach(contract.sceneOptions) { option in
            optionCard(option)
          }
        }

        if let option = selectedPreviewOption {
          optionDetail(option, contract: contract)
        }
      }
    }
  }

  private var sourceUnavailablePrompt: some View {
    HStack(spacing: 16) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 27))
        .foregroundStyle(StudioTheme.warm)
      VStack(alignment: .leading, spacing: 5) {
        Text("场景来源尚未确认")
          .font(.headline)
        Text("请先提交结构转移或确认大节拍；来源恢复前不会生成可能错挂的场景方案。")
          .font(.system(size: 14.5))
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("返回叙事编译台", systemImage: "arrow.up.left") {
        onNavigate(.compiler)
      }
      .buttonStyle(.borderedProminent)
    }
    .padding(.horizontal, 22)
    .padding(.vertical, 20)
    .animatedStoryBubble(tint: StudioTheme.warm, cornerRadius: 44)
  }

  private func optionCard(_ option: SceneChoiceOption) -> some View {
    let selected = selectedPreviewOption?.id == option.id
    let hitShape = RoundedRectangle(cornerRadius: 44, style: .continuous)

    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(option.title)
          .font(.system(size: 18, weight: .semibold, design: .serif))
          .foregroundStyle(.primary)
        Spacer()
        Label(
          selected ? "正在预览" : "预览",
          systemImage: selected ? "eye.fill" : "eye"
        )
        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
        .foregroundStyle(selected ? StudioTheme.mint : .secondary)
      }
      Text(option.approach)
        .font(.system(size: 14.5))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.leading)
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)

      Text(option.heading)
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
      Text("转折：\(option.turn)")
        .font(.system(size: 12.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(17)
    .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
    .animatedStoryBubble(
      tint: selected ? StudioTheme.mint : StudioTheme.accent,
      cornerRadius: 44,
      isSelected: selected
    )
    .contentShape(hitShape)
    .overlay {
      Button {
        previewOptionID = option.id
      } label: {
        hitShape
          .fill(Color.clear)
          .contentShape(hitShape)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("预览场景方案：\(option.title)")
      .accessibilityHint("只更新下方预览，不会确认场景")
    }
    .help("\(option.title)\n\(option.approach)")
  }

  private func optionDetail(_ option: SceneChoiceOption, contract: SceneContract) -> some View {
    VStack(alignment: .leading, spacing: 15) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          EyebrowLabel(text: "SCENE CONTRACT · 当前预览", color: StudioTheme.accent)
          Text(option.title)
            .font(.system(size: 24, weight: .semibold, design: .serif))
        }
        Spacer()
        Button("确认这个场景", systemImage: "checkmark.seal.fill") {
          confirm(option, for: contract)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(StudioTheme.mint)
      }

      Text(option.heading)
        .font(.system(size: 17, weight: .semibold))

      Text(option.approach)
        .font(.system(size: 15.5))
        .foregroundStyle(.secondary)
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)

      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 290), spacing: 12)],
        spacing: 12
      ) {
        optionFact("视点", option.pointOfView, "eye.fill")
        optionFact("即时目标", option.characterGoal, "scope")
        optionFact("阻碍", option.obstacle, "xmark.octagon.fill")
        optionFact("转折", option.turn, "bolt.fill")
        optionFact("结果", option.outcome, "arrow.right.to.line")
        optionFact("下一场压力", option.nextPressure, "point.3.connected.trianglepath.dotted")
        ForEach(option.requiredStateChanges ?? []) { mutation in
          optionFact(
            "\(mutation.dimension.rawValue) · \(mutation.subject)",
            "\(mutation.beforeValue) → \(mutation.afterValue)",
            mutation.dimension.symbol
          )
        }
        if let audience = option.audienceUpdate, !audience.isEmpty {
          optionFact("观众认知更新", audience, "eye.fill")
        }
        if let forbidden = option.forbiddenChanges, !forbidden.isEmpty {
          optionFact("不得提前改变", forbidden.joined(separator: "；"), "lock.fill")
        }
      }
    }
    .padding(.horizontal, 22)
    .padding(.vertical, 20)
    .animatedStoryBubble(
      tint: StudioTheme.mint,
      cornerRadius: 50,
      isSelected: true
    )
  }

  private func optionFact(_ title: String, _ value: String, _ icon: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(title, systemImage: icon)
        .font(.system(size: 13.5, weight: .semibold))
        .foregroundStyle(StudioTheme.accent)
      Text(value)
        .font(.system(size: 15))
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(13)
    .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
    .animatedStoryBubble(tint: StudioTheme.accent, cornerRadius: 28)
  }

  private func confirmedSceneEditor(_ contract: SceneContract) -> some View {
    VStack(alignment: .leading, spacing: 17) {
      if !contract.microBeats.isEmpty {
        Label(
          "这个场景已经展开小节拍。为避免上下层分叉，场景事实现已固定。",
          systemImage: "lock.fill"
        )
        .font(.callout.weight(.semibold))
        .foregroundStyle(StudioTheme.warm)
      }

      HStack {
        VStack(alignment: .leading, spacing: 3) {
          EyebrowLabel(text: "CONFIRMED SCENE", color: StudioTheme.mint)
          TextField("场景标题（地点与时间）", text: binding(contract, \.heading))
            .font(.system(size: 24, weight: .semibold, design: .serif))
            .textFieldStyle(.plain)
            .disabled(!contract.microBeats.isEmpty)
        }
        Spacer()
        Label("已确认", systemImage: "checkmark.seal.fill")
          .font(.callout.weight(.semibold))
          .foregroundStyle(StudioTheme.mint)
      }

      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 320), spacing: 12)],
        spacing: 12
      ) {
        contractField("视点", prompt: "观众通过谁经历这一场？", text: binding(contract, \.pointOfView))
        contractField("即时目标", prompt: "人物此刻要取得什么具体结果？", text: binding(contract, \.characterGoal))
        contractField("阻碍", prompt: "谁或什么正在阻止他？", text: binding(contract, \.obstacle))
        contractField("转折", prompt: "什么可见事件改变了策略或权力？", text: binding(contract, \.turn))
        contractField("结果", prompt: "离场时，人物得到或失去了什么？", text: binding(contract, \.outcome))
        contractField("下一场压力", prompt: "这一结果为何迫使下一场发生？", text: binding(contract, \.nextPressure))
      }
      .disabled(!contract.microBeats.isEmpty)

      atomicInspector(contract)
    }
    .padding(.horizontal, 22)
    .padding(.vertical, 20)
    .animatedStoryBubble(
      tint: StudioTheme.mint,
      cornerRadius: 52,
      isSelected: true
    )
  }

  private func contractField(
    _ title: String,
    prompt: String,
    text: Binding<String>
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(title)
        .font(.system(size: 13.5, weight: .semibold))
        .foregroundStyle(.secondary)
      TextField(prompt, text: text, axis: .vertical)
        .font(.system(size: 15.5))
        .lineLimit(2...6)
        .textFieldStyle(.plain)
        .padding(13)
        .animatedStoryBubble(tint: StudioTheme.sky, cornerRadius: 28)
    }
  }

  private func atomicInspector(_ contract: SceneContract) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Divider()
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          EyebrowLabel(text: "ATOMIC VIEW", color: StudioTheme.mint)
          Text("原子显微镜")
            .font(.system(size: 24, weight: .semibold, design: .serif))
        }
        Spacer()
        Text("W/K/G/R/D/E · before → after")
          .font(.system(size: 13, weight: .semibold, design: .monospaced))
          .foregroundStyle(StudioTheme.mint)
      }

      let stateContract = contract.stateContract
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 290), spacing: 12)],
        spacing: 12
      ) {
        atomCard(
          "进入状态", stateContract.entrySnapshot.nonemptyFallback(atomicEntryState(contract)),
          "arrow.right.to.line.compact", StudioTheme.warm)
        ForEach(stateContract.requiredChanges) { mutation in
          atomCard(
            "\(mutation.dimension.rawValue) · \(mutation.subject)",
            "\(mutation.beforeValue) → \(mutation.afterValue)",
            mutation.dimension.symbol,
            StudioTheme.accent
          )
        }
        atomCard("实现机制", contract.turn, "bolt.fill", StudioTheme.accent)
        atomCard(
          "观众离场认知", stateContract.audienceOutcome,
          "eye.fill", StudioTheme.mint)
        atomCard(
          "不得提前改变", stateContract.forbiddenChanges.joined(separator: "；"),
          "lock.fill", StudioTheme.warm)
        atomCard(
          "因果关系", contract.nextPressure, "point.3.connected.trianglepath.dotted", StudioTheme.warm)
        atomCard("时间与空间", contract.heading, "location.fill", StudioTheme.sky)
      }

      if let projection = realizedProjection(for: contract) {
        VStack(alignment: .leading, spacing: 7) {
          Label("正文实现证据", systemImage: "checkmark.seal.fill")
            .font(.headline)
            .foregroundStyle(StudioTheme.mint)
          Text(projection.summary)
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
          if !projection.realizationGap.isEmpty {
            Text(projection.realizationGap)
              .font(.caption)
              .foregroundStyle(.orange)
          }
        }
        .padding(14)
        .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 30)
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 17)
    .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 44)
  }

  private func realizedProjection(for contract: SceneContract) -> NarrativeProjectionRecord? {
    guard let sceneID = project.dramaticUpdates.first(where: {
      $0.sceneContractID == contract.id && $0.status != .stale
    })?.sceneRecordID else { return nil }
    return DramaticProjectionEngine.projection(
      .scene,
      key: sceneID.uuidString,
      in: project
    )
  }

  private func atomCard(_ title: String, _ value: String, _ icon: String, _ tint: Color)
    -> some View
  {
    VStack(alignment: .leading, spacing: 7) {
      Label(title, systemImage: icon)
        .font(.system(size: 14.5, weight: .semibold))
        .foregroundStyle(tint)
      Text(value.nonemptyFallback("待明确"))
        .font(.system(size: 17))
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }
    .padding(14)
    .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
    .animatedStoryBubble(tint: tint, cornerRadius: 30)
  }

  private func planStageScopes(for contract: SceneContract) {
    guard let stageIndex = contract.structureStageIndex,
      let decision = project.decisions.first(where: {
        $0.stageIndex == stageIndex && $0.selectedOptionID != nil
      }),
      planningStageIndex == nil
    else {
      return
    }
    planningStageIndex = stageIndex
    Task {
      defer { planningStageIndex = nil }
      do {
        let scopes = try await SceneChoiceEngine.planScopes(
          for: decision,
          project: project,
          configuration: try aiSettings.configuration()
        )
        SceneMappingEngine.replaceUnconfirmedScopes(
          scopes,
          for: decision,
          in: project,
          modelContext: modelContext
        )
        try ProjectPersistenceStore.savePendingChanges(in: modelContext)
        selectedContractID =
          project.sceneContracts
          .filter { $0.structureStageIndex == stageIndex }
          .sorted { $0.stageSceneOrdinal < $1.stageSceneOrdinal }
          .first?.id
      } catch {
        present(error)
      }
    }
  }

  private func generateOptions(for contract: SceneContract) {
    guard generatingContractID == nil else { return }
    generatingContractID = contract.id
    Task {
      defer { generatingContractID = nil }
      do {
        let options = try await SceneChoiceEngine.generateOptions(
          for: contract,
          project: project,
          configuration: try aiSettings.configuration()
        )
        guard contract.selectedSceneOptionID == nil else { return }
        contract.sceneOptions = options
        contract.status = "四选一"
        project.touch()
        try ProjectPersistenceStore.savePendingChanges(in: modelContext)
        previewOptionID = options.first?.id
      } catch {
        present(error)
      }
    }
  }

  private func confirm(_ option: SceneChoiceOption, for contract: SceneContract) {
    do {
      try SceneMappingEngine.confirm(option, for: contract, in: project)
      try ProjectPersistenceStore.savePendingChanges(in: modelContext)
      previewOptionID = option.id
    } catch {
      present(error)
    }
  }

  private func openScreenplay() {
    do {
      let state = try ProjectPersistenceStore.screenplayState(
        for: project,
        in: modelContext
      )
      try ProjectPersistenceStore.transaction(in: modelContext) {
        if let selectedContract {
          state.activeSceneIndex = max(selectedContract.sceneIndex - 1, 0)
        }
        if project.screenplayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          project.screenplayText = SceneCompilationEngine.screenplaySkeleton(for: project)
          project.touch()
          StoryCompiler.insertSnapshot(
            project: project,
            title: "场景工作台完成",
            reason: "所有场景均经四选一确认",
            in: modelContext
          )
        }
      }
      onNavigate(.screenplay)
    } catch {
      present(error)
    }
  }

  private func binding(
    _ contract: SceneContract,
    _ keyPath: ReferenceWritableKeyPath<SceneContract, String>
  ) -> Binding<String> {
    Binding(
      get: { contract[keyPath: keyPath] },
      set: { value in
        contract[keyPath: keyPath] = value
        contract.updatedAt = .now
        project.touch()
      }
    )
  }

  private func needsScopePlanning(_ contract: SceneContract) -> Bool {
    contract.status == "待拆分场景" || contract.status == "范围待生成"
  }

  private func sourceContext(for contract: SceneContract) -> SceneChoiceSourceContext? {
    try? SceneChoiceEngine.sourceContext(for: contract, project: project)
  }

  private func canGenerateOptions(for contract: SceneContract) -> Bool {
    SceneChoiceEngine.canGenerateOptions(for: contract, project: project)
  }

  private func scenePosition(for contract: SceneContract) -> (ordinal: Int, total: Int) {
    guard let group = stageGroups.first(where: {
      $0.contracts.contains { $0.id == contract.id }
    }), let index = group.contracts.firstIndex(where: { $0.id == contract.id }) else {
      return (max(contract.stageSceneOrdinal, 1), 1)
    }
    return (index + 1, group.contracts.count)
  }

  private func sceneStatusColor(_ contract: SceneContract) -> Color {
    if contract.selectedSceneOptionID != nil { return StudioTheme.mint }
    if !contract.sceneOptions.isEmpty { return StudioTheme.accent }
    return StudioTheme.warm
  }

  private func atomicEntities(_ contract: SceneContract) -> String {
    [contract.pointOfView, contract.obstacle]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " · ")
  }

  private func atomicEntryState(_ contract: SceneContract) -> String {
    [contract.characterGoal, contract.obstacle]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "；")
  }

  private func selectFirstIfNeeded() {
    if selectedContract == nil {
      selectedContractID = contracts.first?.id
    }
  }

  private func syncPreviewSelection() {
    previewOptionID =
      selectedContract?.selectedSceneOptionID
      ?? selectedContract?.sceneOptions.first?.id
  }

  private func stageName(for contract: SceneContract) -> String {
    if let source = sourceContext(for: contract) {
      return source.hierarchyLabel
    }
    guard let index = contract.structureStageIndex,
      project.structureTemplate.stages.indices.contains(index)
    else {
      return "来源尚未确认"
    }
    return "第 \(index + 1) 大节拍 · \(project.structureTemplate.stages[index].name)"
  }

  private func present(_ error: Error) {
    errorMessage = error.localizedDescription
    showingError = true
  }

  private func savePendingChanges() {
    do {
      try ProjectPersistenceStore.savePendingChanges(in: modelContext)
    } catch {
      present(error)
    }
  }
}

extension String {
  fileprivate func nonemptyFallback(_ fallback: String) -> String {
    let clean = trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.isEmpty ? fallback : clean
  }
}
