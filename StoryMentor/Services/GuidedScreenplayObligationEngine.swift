import Foundation
import SwiftData

@MainActor
enum GuidedScreenplayObligationEngine {
  static let guidedPlaceholderStatus = "心流命题待写"
  static let guidedCompiledStatus = "心流正文已编译"

  static func selectStructure(
    template: StoryStructureTemplate,
    scale: GuidedScriptScale,
    project: StoryProject,
    session: GuidedFlowSession,
    modelContext: ModelContext
  ) throws {
    guard !project.isStructureLocked else { return }

    project.structureTemplateID = template.id
    project.structureTemplateName = template.name
    project.structureRulesText = template.rulesPrompt
    project.lockStructure()
    session.guidedScriptScale = scale
    session.phase = .structure
    session.itemIndex = 0
    session.subitemIndex = 0
    session.stepIndex = 0
    session.invalidateCompletedScreenplayApproval()

    try bootstrapSceneSlotsIfNeeded(
      project: project,
      session: session,
      modelContext: modelContext
    )
    try ProjectPersistenceStore.savePendingChanges(in: modelContext)
  }

  static func bootstrapSceneSlotsIfNeeded(
    project: StoryProject,
    session: GuidedFlowSession,
    modelContext: ModelContext
  ) throws {
    guard project.isStructureLocked,
          project.hasSelectedStructureTemplate else {
      return
    }

    let template = project.structureTemplate
    guard !template.stages.isEmpty else { return }

    if project.sceneContracts.isEmpty {
      let counts = distributedSceneCounts(
        stageCount: template.stages.count,
        target: max(template.stages.count, session.guidedScriptScale.targetSceneCount)
      )
      var sceneIndex = 1

      for (stageIndex, stage) in template.stages.enumerated() {
        let count = counts[stageIndex]
        for ordinal in 1...count {
          let contract = SceneContract(
            sceneIndex: sceneIndex,
            structureStageIndex: stageIndex,
            stageSceneOrdinal: ordinal,
            scopeTitle: "\(stage.name) · 场景 \(ordinal)",
            scopePurpose: stage.purpose,
            scopeEntryState: stageIndex == 0 && ordinal == 1
              ? "故事开始前仍维持原有生活"
              : "承接上一场已经成立的结果",
            scopeExitState: stage.choiceFocus,
            heading: placeholderHeading(
              stageName: stage.name,
              ordinal: ordinal
            ),
            status: guidedPlaceholderStatus
          )
          contract.project = project
          modelContext.insert(contract)
          sceneIndex += 1
        }
      }
      modelContext.processPendingChanges()
      SceneMappingEngine.renumber(project.sceneContracts)
    }

    if project.screenplayText.trimmedForGuidedObligations.isEmpty
      || isSingleEmptyPlaceholder(project.screenplayText)
    {
      project.screenplayText = screenplaySkeleton(
        contracts: project.sceneContracts.sorted { $0.sceneIndex < $1.sceneIndex }
      )
    }

    project.scenesText = project.sceneContracts
      .sorted { $0.sceneIndex < $1.sceneIndex }
      .map { contract in
        """
        【场景 \(contract.sceneIndex)】\(contract.scopeTitle)
        结构职责：\(contract.scopePurpose)
        必须到达：\(contract.scopeExitState)
        """
      }
      .joined(separator: "\n\n")
    project.touch()
  }

  static func snapshot(
    project: StoryProject,
    session: GuidedFlowSession,
    workspaceState: ScreenplayWorkspaceState?
  ) -> GuidedScreenplayCompletionSnapshot {
    let fingerprint = ScreenplayReviewEngine.fingerprint(project.screenplayText)
    var obligations: [GuidedScreenplayObligation] = []

    let structureSelected = project.hasSelectedStructureTemplate
      && project.isStructureLocked
    obligations.append(
      GuidedScreenplayObligation(
        id: "structure.selection",
        kind: .structureSelection,
        status: structureSelected ? .satisfied : .active,
        title: structureSelected
          ? "已锁定 \(project.structureTemplate.name)"
          : "选择全本结构",
        detail: structureSelected
          ? project.structureTemplate.experience
          : "三幕剧、英雄之旅等结构将成为后台完成地图。",
        stageIndex: nil,
        sceneContractID: nil,
        reviewKindRawValue: nil,
        blocker: nil
      )
    )

    guard structureSelected else {
      return GuidedScreenplayCompletionSnapshot(
        obligations: obligations,
        nextObligation: obligations.first,
        hardCompleted: 0,
        hardTotal: 1,
        sceneCompleted: 0,
        sceneTotal: 0,
        blockerCount: 0,
        screenplayFingerprint: fingerprint,
        isAuthorApproved: false
      )
    }

    let template = project.structureTemplate
    let scenes = FountainParser.scenes(in: project.screenplayText)
    let contracts = project.sceneContracts.sorted { $0.sceneIndex < $1.sceneIndex }
    var sceneCompleted = 0
    var nextSceneObligation: GuidedScreenplayObligation?

    for (stageIndex, stage) in template.stages.enumerated() {
      let stageContracts = contracts.filter { $0.structureStageIndex == stageIndex }
      let stageDecisionComplete = project.decisions.contains {
        $0.stageIndex == stageIndex && $0.selectedOptionID != nil
      }
      let stageScenesComplete = !stageContracts.isEmpty
        && stageContracts.allSatisfy {
          isSceneComplete($0, scenes: scenes)
        }
      obligations.append(
        GuidedScreenplayObligation(
          id: "structure.stage.\(stage.id)",
          kind: .structureStage,
          status: stageDecisionComplete && stageScenesComplete
            ? .satisfied
            : .pending,
          title: stage.name,
          detail: stage.purpose,
          stageIndex: stageIndex,
          sceneContractID: stageContracts.first(where: {
            !isSceneComplete($0, scenes: scenes)
          })?.id,
          reviewKindRawValue: nil,
          blocker: nil
        )
      )

      for contract in stageContracts {
        let complete = isSceneComplete(contract, scenes: scenes)
        if complete { sceneCompleted += 1 }
        let obligation = GuidedScreenplayObligation(
          id: "scene.\(contract.id.uuidString)",
          kind: .sceneDraft,
          status: complete
            ? .satisfied
            : (nextSceneObligation == nil ? .active : .pending),
          title: "场 \(contract.sceneIndex) · \(stage.name)",
          detail: sceneObligationDetail(
            contract,
            scenes: scenes
          ),
          stageIndex: stageIndex,
          sceneContractID: contract.id,
          reviewKindRawValue: nil,
          blocker: nil
        )
        obligations.append(obligation)
        if !complete, nextSceneObligation == nil {
          nextSceneObligation = obligation
        }
      }
    }

    let allScenesComplete = !contracts.isEmpty && sceneCompleted == contracts.count
    var blockerCount = 0
    var firstReviewObligation: GuidedScreenplayObligation?

    for kind in ScreenplayReviewKind.allCases {
      let round = workspaceState?.latestReview(for: kind)
      let current = ScreenplayReviewEngine.isCurrent(round, project: project)
      let blockers = current
        ? (round?.findings.filter { $0.severity == .blocker } ?? [])
        : []
      blockerCount += blockers.count
      let status: GuidedScreenplayObligationStatus
      if !allScenesComplete {
        status = .pending
      } else if !current {
        status = firstReviewObligation == nil ? .active : .pending
      } else if blockers.isEmpty {
        status = .satisfied
      } else {
        status = .blocked
      }
      let firstBlocker = blockers.first
      let target = firstBlocker.flatMap {
        contractForFinding(
          $0,
          contracts: contracts
        )
      }
      let obligation = GuidedScreenplayObligation(
        id: "review.\(kind.rawValue)",
        kind: .screenplayReview,
        status: status,
        title: kind.rawValue,
        detail: firstBlocker?.detail ?? kind.purpose,
        stageIndex: target?.structureStageIndex,
        sceneContractID: target?.id,
        reviewKindRawValue: kind.rawValue,
        blocker: firstBlocker?.title
      )
      obligations.append(obligation)
      if allScenesComplete,
         firstReviewObligation == nil,
         status != .satisfied {
        firstReviewObligation = obligation
      }
    }

    let reviewsComplete = allScenesComplete
      && ScreenplayReviewEngine.isReady(
        state: workspaceState,
        project: project
      )
    let approved = reviewsComplete
      && session.guidedApprovalFingerprint == fingerprint
    let approval = GuidedScreenplayObligation(
      id: "author.approval",
      kind: .authorApproval,
      status: approved
        ? .satisfied
        : (reviewsComplete ? .active : .pending),
      title: "作者最终确认",
      detail: "确认全本已经回答核心戏剧问题，并可以作为完整剧本交付。",
      stageIndex: nil,
      sceneContractID: nil,
      reviewKindRawValue: nil,
      blocker: nil
    )
    obligations.append(approval)

    let next = nextSceneObligation
      ?? firstReviewObligation
      ?? (approved ? nil : approval)
    let hardCompleted = obligations.count { $0.status == .satisfied }

    return GuidedScreenplayCompletionSnapshot(
      obligations: obligations,
      nextObligation: next,
      hardCompleted: hardCompleted,
      hardTotal: obligations.count,
      sceneCompleted: sceneCompleted,
      sceneTotal: contracts.count,
      blockerCount: blockerCount,
      screenplayFingerprint: fingerprint,
      isAuthorApproved: approved
    )
  }

  static func prompt(
    snapshot: GuidedScreenplayCompletionSnapshot,
    project: StoryProject
  ) -> GuidedScreenplayPrompt? {
    guard let obligation = snapshot.nextObligation else { return nil }

    switch obligation.kind {
    case .structureSelection:
      return nil

    case .structureStage, .sceneDraft:
      guard let contractID = obligation.sceneContractID,
            let contract = project.sceneContracts.first(where: {
              $0.id == contractID
            }) else {
        return nil
      }
      let stageIndex = contract.structureStageIndex ?? 0
      let stage = project.structureTemplate.stages.indices.contains(stageIndex)
        ? project.structureTemplate.stages[stageIndex]
        : StructureStage(
          id: "unknown",
          name: contract.scopeTitle,
          purpose: contract.scopePurpose,
          choiceFocus: contract.scopeExitState
        )
      let ordinalCount = project.sceneContracts.count {
        $0.structureStageIndex == stageIndex
      }
      return GuidedScreenplayPrompt(
        obligationID: obligation.id,
        eyebrow: "\(project.structureTemplate.name) · \(stage.name)",
        title: "写第 \(contract.stageSceneOrdinal)/\(max(ordinalCount, 1)) 场",
        question: stage.choiceFocus,
        writingDirection: "在当前 Final Draft 场景里自由写。可以写动作、对白、停顿、回忆和生活细节；不必先会剧本格式。让这场最终兑现：\(stage.purpose)",
        completionHint: "写到你已经看见人物做出选择、遭遇反作用，并让局面发生变化时，完成本轮。",
        targetSceneContractID: contract.id,
        actionTitle: "完成本轮写作"
      )

    case .screenplayReview:
      if let blocker = obligation.blocker {
        return GuidedScreenplayPrompt(
          obligationID: obligation.id,
          eyebrow: "全本检查 · \(obligation.reviewKind?.rawValue ?? "修订")",
          title: blocker,
          question: obligation.detail,
          writingDirection: obligation.sceneContractID == nil
            ? "检查全本并处理这个阻断问题。系统只会修复必要范围，不会重写已经成立的部分。"
            : "回到当前场景，只修改造成这个阻断问题的部分；保留作者已经写下的有效动作、对白和语气。",
          completionHint: "修复后重新检查全本。没有阻断问题时，这一项会自动完成。",
          targetSceneContractID: obligation.sceneContractID,
          actionTitle: obligation.sceneContractID == nil
            ? "重新检查全本"
            : "完成这次修订"
        )
      }
      return GuidedScreenplayPrompt(
        obligationID: obligation.id,
        eyebrow: "全本完成检查",
        title: obligation.reviewKind?.rawValue ?? "检查全本",
        question: obligation.detail,
        writingDirection: "系统将对当前正式剧本运行确定性检查，只把阻断完整交付的问题带回写作区。",
        completionHint: "警告和润色建议不会阻止剧本完成。",
        targetSceneContractID: nil,
        actionTitle: "检查这一项"
      )

    case .authorApproval:
      return GuidedScreenplayPrompt(
        obligationID: obligation.id,
        eyebrow: "所有硬性剧作义务已经完成",
        title: "确认这就是你的完整剧本",
        question: "全本结构、场景、正文元素和阻断检查均已通过。",
        writingDirection: "你仍可继续润色；确认后系统会停止生成新命题，并把当前版本标记为完整剧本。",
        completionHint: "任何后续正文修改都会自动撤销完成标记，并重新检查。",
        targetSceneContractID: nil,
        actionTitle: "确认剧本完成"
      )
    }
  }

  static func refreshReviews(
    state: ScreenplayWorkspaceState,
    project: StoryProject
  ) {
    let fingerprint = ScreenplayReviewEngine.fingerprint(project.screenplayText)
    for kind in ScreenplayReviewKind.allCases {
      let findings = ScreenplayReviewEngine.deterministicFindings(
        kind: kind,
        project: project
      )
      let blockers = findings.count { $0.severity == .blocker }
      let summary = blockers == 0
        ? "没有阻断完整交付的问题。"
        : "发现 \(blockers) 个必须处理的阻断问题。"
      state.addReviewRound(
        ScreenplayReviewRound(
          kind: kind,
          screenplayFingerprint: fingerprint,
          summary: summary,
          findings: findings
        )
      )
    }
  }

  static func targetContract(
    for snapshot: GuidedScreenplayCompletionSnapshot,
    project: StoryProject
  ) -> SceneContract? {
    guard let id = snapshot.nextObligation?.sceneContractID else { return nil }
    return project.sceneContracts.first { $0.id == id }
  }

  static func sceneText(
    for contract: SceneContract,
    in project: StoryProject
  ) -> String {
    let scenes = FountainParser.scenes(in: project.screenplayText)
    let index = max(0, contract.sceneIndex - 1)
    guard scenes.indices.contains(index) else { return "" }
    return scenes[index].text
  }

  private static func distributedSceneCounts(
    stageCount: Int,
    target: Int
  ) -> [Int] {
    guard stageCount > 0 else { return [] }
    var counts = Array(repeating: 1, count: stageCount)
    var remaining = max(0, target - stageCount)
    let center = Double(max(stageCount - 1, 1)) / 2.0
    let order = (0..<stageCount).sorted { lhs, rhs in
      let lhsWeight = 1.7 - abs(Double(lhs) - center) / max(center, 1)
      let rhsWeight = 1.7 - abs(Double(rhs) - center) / max(center, 1)
      if lhsWeight == rhsWeight { return lhs < rhs }
      return lhsWeight > rhsWeight
    }
    var cursor = 0
    while remaining > 0 {
      counts[order[cursor % order.count]] += 1
      cursor += 1
      remaining -= 1
    }
    return counts
  }

  private static func screenplaySkeleton(
    contracts: [SceneContract]
  ) -> String {
    contracts.map { contract in
      "\(contract.heading)\n\n"
    }
    .joined(separator: "\n")
  }

  private static func placeholderHeading(
    stageName: String,
    ordinal: Int
  ) -> String {
    "内. 待定地点·\(stageName)·\(ordinal) - 日"
  }

  private static func isSingleEmptyPlaceholder(_ text: String) -> Bool {
    let scenes = FountainParser.scenes(in: text)
    guard scenes.count == 1, let scene = scenes.first else { return false }
    let body = FountainParser.paragraphs(in: scene.text).dropFirst()
    return body.allSatisfy { $0.trimmedText.isEmpty }
  }

  private static func isSceneComplete(
    _ contract: SceneContract,
    scenes: [FountainSceneSnapshot]
  ) -> Bool {
    let index = contract.sceneIndex - 1
    guard scenes.indices.contains(index) else { return false }
    return contract.selectedSceneOptionID != nil
      && SceneCompilationEngine.isComplete(contract)
      && contract.areMicroBeatsConfirmed
      && ScreenplayDraftOptionPolicy.isProfessionalSceneText(
        scenes[index].text
      )
  }

  private static func sceneObligationDetail(
    _ contract: SceneContract,
    scenes: [FountainSceneSnapshot]
  ) -> String {
    let index = contract.sceneIndex - 1
    guard scenes.indices.contains(index) else {
      return "正式剧本中还没有这场。"
    }
    if !ScreenplayDraftOptionPolicy.isProfessionalSceneText(scenes[index].text) {
      return "当前仍是空场或创作材料，需要编译为可拍摄的正式场景。"
    }
    if contract.selectedSceneOptionID == nil
      || !SceneCompilationEngine.isComplete(contract) {
      return "正文已经出现，但后台仍需确认目标、阻碍、转折和离场结果。"
    }
    if !contract.areMicroBeatsConfirmed {
      return "场景成立，但还需要从正文中确认必要的情境更新。"
    }
    return "这场已经完成。"
  }

  private static func contractForFinding(
    _ finding: ScreenplayReviewFinding,
    contracts: [SceneContract]
  ) -> SceneContract? {
    let digits = finding.location
      .components(separatedBy: CharacterSet.decimalDigits.inverted)
      .first { !$0.isEmpty }
    guard let digits, let sceneNumber = Int(digits) else { return nil }
    return contracts.first { $0.sceneIndex == sceneNumber }
  }
}

private extension String {
  var trimmedForGuidedObligations: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
