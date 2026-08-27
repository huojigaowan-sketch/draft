import Foundation
import SwiftData

@MainActor
enum GuidedFinalDraftProjectWriter {
  static func apply(
    _ result: GuidedSceneCompilationResult,
    sourceScene: String,
    contract: SceneContract,
    project: StoryProject,
    session: GuidedFlowSession,
    workspaceState: ScreenplayWorkspaceState?,
    modelContext: ModelContext
  ) throws {
    let sceneIndex = max(0, contract.sceneIndex - 1)
    let scenes = FountainParser.scenes(in: project.screenplayText)
    guard scenes.indices.contains(sceneIndex) else {
      throw GuidedFinalDraftProjectWriterError.sceneMissing
    }

    workspaceState?.addRevision(
      title: "心流编译前 · 场 \(contract.sceneIndex)",
      fountainText: project.screenplayText
    )

    let updatedScreenplay = FountainParser.replacingScene(
      at: sceneIndex,
      in: project.screenplayText,
      with: result.fountainText
    )

    project.screenplayText = FountainParser.standardizingSceneFlow(
      in: updatedScreenplay
    )
    applySceneContract(
      result,
      contract: contract,
      project: project
    )
    applyCharacters(
      result.characters,
      project: project,
      modelContext: modelContext
    )
    preserveAuthorRound(
      sourceScene: sourceScene,
      result: result,
      contract: contract,
      project: project,
      modelContext: modelContext
    )

    let echo = GuidedScreenplayCompileEcho(
      sceneContractID: contract.id,
      headline: result.echoHeadline,
      findings: result.echoFindings,
      preservedQuotes: result.preservedQuotes
    )
    session.storeCompileEcho(echo)
    session.invalidateCompletedScreenplayApproval()
    session.setAnswer(
      ScreenplayDraftOptionPolicy.fingerprint(result.fountainText),
      for: "guided.screenplay.scene.\(contract.id.uuidString).fingerprint"
    )

    try commitStageIfComplete(
      stageIndex: contract.structureStageIndex,
      project: project,
      modelContext: modelContext
    )
    rebuildProjectIndexes(project)

    workspaceState?.updateScene(at: sceneIndex) {
      $0.status = .drafted
      $0.emotionalTurn = result.turn
      $0.aiNote = result.echoHeadline
      $0.continuityWarnings = []
      $0.choicesForAuthor = []
      $0.structureAnchor = contract.structureStageIndex.flatMap { index in
        project.structureTemplate.stages.indices.contains(index)
          ? project.structureTemplate.stages[index].name
          : nil
      }
      $0.knowledgeSources = result.knowledgeSources
    }

    DramaticProjectionEngine.markAllStale(in: project)
    project.touch()
    try ProjectPersistenceStore.savePendingChanges(in: modelContext)
  }

  private static func applySceneContract(
    _ result: GuidedSceneCompilationResult,
    contract: SceneContract,
    project: StoryProject
  ) {
    contract.heading = result.heading
    contract.pointOfView = result.pointOfView
    contract.characterGoal = result.characterGoal
    contract.obstacle = result.obstacle
    contract.turn = result.turn
    contract.outcome = result.outcome
    contract.nextPressure = result.nextPressure

    let mutations = result.beats
      .flatMap(\.mutations)
      .map {
        DramaticStateMutation(
          dimension: $0.dimension,
          subject: $0.subject,
          holder: $0.holder,
          beforeValue: $0.beforeValue,
          afterValue: $0.afterValue,
          observerNames: ["观众"]
        )
      }
      .filter(\.isEffective)
    let stateChanges = mutations.isEmpty
      ? [
        DramaticStateMutation(
          dimension: .world,
          subject: contract.scopeTitle,
          holder: result.pointOfView,
          beforeValue: contract.scopeEntryState.isEmpty
            ? "进入本场前"
            : contract.scopeEntryState,
          afterValue: result.outcome,
          observerNames: ["观众"]
        )
      ]
      : mutations
    let sceneOption = SceneChoiceOption(
      title: compactTitle(result.turn, fallback: "作者正式场景"),
      approach: "作者在 Final Draft 工作区长写，AI 只编译当前场",
      heading: result.heading,
      pointOfView: result.pointOfView,
      characterGoal: result.characterGoal,
      obstacle: result.obstacle,
      turn: result.turn,
      outcome: result.outcome,
      nextPressure: result.nextPressure,
      requiredStateChanges: stateChanges,
      audienceUpdate: result.beats.last?.audienceUpdate ?? result.outcome,
      forbiddenChanges: ["不得提前完成后续结构阶段"]
    )

    contract.sceneOptions = [sceneOption]
    contract.selectedSceneOptionID = sceneOption.id
    contract.stateContract = SceneStateContract(
      entrySnapshot: contract.scopeEntryState,
      requiredChanges: stateChanges,
      forbiddenChanges: ["不得提前完成后续结构阶段"],
      audienceOutcome: result.beats.last?.audienceUpdate ?? result.outcome,
      exitSnapshot: result.outcome,
      verificationRule: result.stageEvidence
    )

    contract.microBeats = result.beats.enumerated().map { offset, beat in
      let beatMutations = beat.mutations.map {
        DramaticStateMutation(
          dimension: $0.dimension,
          subject: $0.subject,
          holder: $0.holder,
          beforeValue: $0.beforeValue,
          afterValue: $0.afterValue,
          observerNames: ["观众"]
        )
      }
      let option = SceneBeatChoiceOption(
        title: "变化 \(offset + 1)",
        dramaticAction: beat.dramaticAction,
        characterAction: beat.characterAction,
        opposition: beat.opposition,
        turn: beat.turn,
        outcome: beat.outcome,
        screenplayText: beat.screenplayText,
        stateChanges: beatMutations,
        audienceUpdate: beat.audienceUpdate
      )
      return SceneMicroBeat(
        ordinal: offset + 1,
        purpose: beat.purpose,
        options: [option],
        selectedOptionID: option.id
      )
    }
    contract.status = GuidedScreenplayObligationEngine.guidedCompiledStatus
    contract.scopeExitState = result.outcome
    contract.updatedAt = .now
    project.touch()
  }

  private static func applyCharacters(
    _ compiledCharacters: [GuidedCompiledCharacter],
    project: StoryProject,
    modelContext: ModelContext
  ) {
    for item in compiledCharacters {
      let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty else { continue }
      let role = characterRole(item.roleRawValue, project: project)
      if let existing = project.characters.first(where: {
        $0.name.caseInsensitiveCompare(name) == .orderedSame
      }) {
        if existing.seedText.trimmedForGuidedWriter.isEmpty {
          existing.seedText = item.visibleBehavior
        } else if !existing.seedText.contains(item.visibleBehavior),
                  !item.visibleBehavior.trimmedForGuidedWriter.isEmpty {
          existing.seedText += "\n\(item.visibleBehavior)"
        }
        if existing.externalGoal.trimmedForGuidedWriter.isEmpty {
          existing.externalGoal = item.immediateGoal
        }
        if existing.fear.trimmedForGuidedWriter.isEmpty {
          existing.fear = item.fearOrDefense
        }
        existing.touch()
      } else {
        let character = StoryCharacter(
          name: name,
          role: role,
          seedText: item.visibleBehavior,
          externalGoal: item.immediateGoal,
          fear: item.fearOrDefense,
          project: project
        )
        modelContext.insert(character)
        project.characters.append(character)
      }
    }
  }

  private static func preserveAuthorRound(
    sourceScene: String,
    result: GuidedSceneCompilationResult,
    contract: SceneContract,
    project: StoryProject,
    modelContext: ModelContext
  ) {
    let sourceFingerprint = ScreenplayDraftOptionPolicy.fingerprint(sourceScene)
    let origin = "guided-final-draft-source-\(contract.id.uuidString)-\(sourceFingerprint)"
    guard !project.artifacts.contains(where: { $0.originLabel == origin }) else {
      return
    }
    let artifact = ProjectArtifact(
      title: "命题写作原文 · 场 \(contract.sceneIndex)",
      kind: .screenplay,
      status: .integrated,
      originLabel: origin,
      humanInput: sourceScene,
      lockedIdeas: result.preservedQuotes.joined(separator: "\n"),
      workingText: result.fountainText,
      acceptedText: result.fountainText,
      aiSummary: result.echoHeadline,
      sortIndex: project.artifacts.count,
      project: project
    )
    modelContext.insert(artifact)
    project.artifacts.append(artifact)
  }

  private static func commitStageIfComplete(
    stageIndex: Int?,
    project: StoryProject,
    modelContext: ModelContext
  ) throws {
    guard let stageIndex,
          project.structureTemplate.stages.indices.contains(stageIndex) else {
      return
    }
    let stageContracts = project.sceneContracts
      .filter { $0.structureStageIndex == stageIndex }
      .sorted { $0.stageSceneOrdinal < $1.stageSceneOrdinal }
    let scenes = FountainParser.scenes(in: project.screenplayText)
    let complete = !stageContracts.isEmpty && stageContracts.allSatisfy { contract in
      let index = contract.sceneIndex - 1
      return contract.selectedSceneOptionID != nil
        && contract.areMicroBeatsConfirmed
        && SceneCompilationEngine.isComplete(contract)
        && scenes.indices.contains(index)
        && ScreenplayDraftOptionPolicy.isProfessionalSceneText(scenes[index].text)
    }
    guard complete else { return }

    let stage = project.structureTemplate.stages[stageIndex]
    let decisionText = stageContracts
      .map(\.outcome)
      .filter { !$0.trimmedForGuidedWriter.isEmpty }
      .joined(separator: "；")
    let cost = stageContracts
      .map(\.obstacle)
      .filter { !$0.trimmedForGuidedWriter.isEmpty }
      .joined(separator: "；")
    let evidence = stageContracts
      .map(\.turn)
      .filter { !$0.trimmedForGuidedWriter.isEmpty }
      .joined(separator: "；")
    let before = project.decisions
      .filter { $0.stageIndex < stageIndex && $0.selectedOptionID != nil }
      .sorted { $0.stageIndex < $1.stageIndex }
      .last?.selectedOption?.pitch ?? "\(stage.name)发生前"
    let mutation = DramaticStateMutation(
      dimension: dimension(for: stage),
      subject: stage.name,
      holder: project.characters.first(where: { $0.role == .protagonist })?.name ?? "主人公",
      beforeValue: before,
      afterValue: decisionText,
      observerNames: ["观众"]
    )
    let option = StoryChoiceOption(
      title: compactTitle(decisionText, fallback: stage.name),
      pitch: decisionText,
      concreteDetail: evidence,
      consequence: cost,
      futurePressure: stageContracts.last?.nextPressure ?? cost,
      sampleMoment: evidence,
      evidenceBasis: ["由正式剧本场景反向确认"],
      sourceCount: 0,
      realityTexture: "",
      paceEffect: "由 \(stageContracts.count) 场正式正文共同兑现",
      emotionShift: "由人物行动和代价自然产生",
      eventScale: stage.name,
      plannedStateChanges: [mutation],
      audienceUpdate: stageContracts.last?.stateContract.audienceOutcome,
      forbiddenChanges: ["不得提前完成后续结构阶段"],
      isLiked: true,
      feedback: "从作者正式剧本确认",
      revisions: []
    )

    let decision: StoryDecision
    if let existing = project.decisions.first(where: { $0.stageIndex == stageIndex }) {
      decision = existing
      decision.phaseRawValue = stage.name
      decision.question = stage.choiceFocus
      decision.coachNote = stage.purpose
      decision.options = [option]
    } else {
      decision = StoryDecision(
        stageName: stage.name,
        stageIndex: stageIndex,
        question: stage.choiceFocus,
        coachNote: stage.purpose,
        options: [option],
        project: project
      )
      modelContext.insert(decision)
      project.decisions.append(decision)
    }
    decision.selectedOptionID = option.id
    decision.selectedAnswerText = """
    \(option.title)：\(option.pitch)
    可见证据：\(option.concreteDetail)
    必须付出：\(option.consequence)
    """
    decision.authorBrief = stageContracts
      .map { "场 \($0.sceneIndex)：\($0.outcome)" }
      .joined(separator: "\n")
    decision.authorBriefUpdatedAt = .now
    decision.resolvedAt = .now
  }

  private static func rebuildProjectIndexes(_ project: StoryProject) {
    project.storyPathText = project.decisions
      .filter { $0.selectedOptionID != nil }
      .sorted { $0.stageIndex < $1.stageIndex }
      .map { "第\($0.stageIndex + 1)阶段 · \($0.stageName)\n\($0.selectedAnswerText)" }
      .joined(separator: "\n\n")
    project.structureText = """
    【锁定结构】\(project.structureTemplate.name)

    \(project.storyPathText)
    """
    project.scenesText = project.sceneContracts
      .sorted { $0.sceneIndex < $1.sceneIndex }
      .map {
        """
        【场景 \($0.sceneIndex)】\($0.heading)
        视点：\($0.pointOfView)
        目标：\($0.characterGoal)
        阻碍：\($0.obstacle)
        转折：\($0.turn)
        结果：\($0.outcome)
        下一场压力：\($0.nextPressure)
        """
      }
      .joined(separator: "\n\n")

    let characterDigest = project.characters
      .map {
        "\($0.name)：\($0.seedText)；目标 \($0.externalGoal)；防御/恐惧 \($0.fear)"
      }
      .joined(separator: "\n")
    project.storyBibleDigest = """
    【人物小传】
    \(characterDigest.isEmpty ? "人物正在从正式场景中形成" : characterDigest)

    【世界规则】
    \(project.worldBibleText.isEmpty ? project.worldText : project.worldBibleText)

    【主题命题】
    \(project.themeBibleText.isEmpty ? project.themeText : project.themeBibleText)

    【核心冲突】
    \(project.coreConflictText)
    """
    project.storyBibleRevision += 1
    project.storyBibleUpdatedAt = .now
    project.storyBibleSyncNote = "由 Final Draft 心流写作同步"
    project.touch()
  }

  private static func characterRole(
    _ value: String,
    project: StoryProject
  ) -> CharacterRole {
    if value.contains("主人公") || value.contains("主角") {
      return .protagonist
    }
    if value.contains("对抗") || value.contains("反派") {
      return .antagonist
    }
    if !project.characters.contains(where: { $0.role == .protagonist }) {
      return .protagonist
    }
    return .supporting
  }

  private static func dimension(
    for stage: StructureStage
  ) -> DramaticStateDimension {
    let value = stage.name + stage.purpose + stage.choiceFocus
    if value.contains("关系") || value.contains("盟友") {
      return .relationship
    }
    if value.contains("认识") || value.contains("揭示") || value.contains("真相") {
      return .knowledge
    }
    if value.contains("选择") || value.contains("目标") || value.contains("计划") {
      return .goal
    }
    if value.contains("承诺") || value.contains("门槛") {
      return .norm
    }
    if value.contains("观众") || value.contains("悬念") {
      return .audience
    }
    return .world
  }

  private static func compactTitle(
    _ value: String,
    fallback: String
  ) -> String {
    let clean = value
      .components(separatedBy: .newlines)
      .first?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return clean.isEmpty ? fallback : String(clean.prefix(18))
  }
}

enum GuidedFinalDraftProjectWriterError: LocalizedError {
  case sceneMissing
  case sceneReplacementFailed

  var errorDescription: String? {
    switch self {
    case .sceneMissing:
      "当前命题对应的正式场景已经不存在。请重新定位后继续。"
    case .sceneReplacementFailed:
      "无法把本轮编译结果写回当前场景。作者原文和版本记录均未丢失。"
    }
  }
}

private extension String {
  var trimmedForGuidedWriter: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
