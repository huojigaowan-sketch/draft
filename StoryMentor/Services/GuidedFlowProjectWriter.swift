import Foundation
import SwiftData

@MainActor
extension GuidedFlowCoordinator {

  static func apply(
    _ answer: String,
    challenge: GuidedFlowChallenge,
    session: GuidedFlowSession,
    project: StoryProject,
    modelContext: ModelContext
  ) throws {
    switch session.phase {
    case .foundation:
      applyFoundation(
        answer,
        stepIndex: session.stepIndex,
        project: project,
        modelContext: modelContext
      )
      session.stepIndex += 1

    case .structure:
      if session.stepIndex < 2 {
        session.stepIndex += 1
      } else {
        try commitStructureStage(
          session: session,
          project: project,
          modelContext: modelContext
        )
        session.stepIndex = 0
        session.subitemIndex = 0
        session.itemIndex =
          project.nextStructureStageIndex
          ?? project.structureTemplate.stages.count
      }

    case .scene:
      try applyScene(
        answer,
        session: session,
        project: project
      )
      if session.stepIndex < 6 {
        session.stepIndex += 1
      } else {
        try commitScene(
          session: session,
          project: project
        )
        session.stepIndex = 0
        session.subitemIndex = 0
        let scenes = orderedScenes(in: project)
        session.itemIndex =
          scenes.firstIndex(where: {
            $0.selectedSceneOptionID == nil
          }) ?? scenes.count
      }

    case .beat:
      if session.stepIndex < 4 {
        session.stepIndex += 1
      } else if session.stepIndex == 4 {
        try commitBeat(
          session: session,
          project: project
        )
        session.stepIndex = 5
      } else {
        try applyBeatGate(
          answer,
          session: session,
          project: project
        )
      }

    case .screenplay:
      try applyScreenplayReview(
        answer,
        session: session,
        project: project
      )

    case .completed:
      break
    }
  }

  static func recordPromptedWritingContribution(
    rawText: String,
    canonicalDecision: String,
    echo: GuidedFlowContributionEcho,
    challenge: GuidedFlowChallenge,
    session: GuidedFlowSession,
    project: StoryProject,
    modelContext: ModelContext
  ) {
    let stageIndex = contributionStageIndex(
      session: session,
      project: project
    )
    let kind = contributionModuleKind(for: challenge)
    let discoverySummary = echo.discoveries
      .map { "【\($0.kind.rawValue)】\($0.finding)" }
      .joined(separator: "\n")
    let artifact = ProjectArtifact(
      title: "命题写作 · \(String(challenge.title.prefix(30)))",
      kind: kind,
      status: .integrated,
      originLabel: "作者命题写作",
      humanInput: rawText,
      lockedIdeas: echo.preservedLines.joined(separator: "\n"),
      workingText: canonicalDecision,
      acceptedText: rawText,
      aiInstruction: challenge.promptedWritingPrompt,
      aiSummary: [echo.impactSummary, discoverySummary]
        .filter { !$0.guidedTrimmed.isEmpty }
        .joined(separator: "\n\n"),
      sortIndex: project.artifacts.count,
      project: project
    )
    artifact.authorGuidanceText = "全文是作者原始创作，不得被AI摘要覆盖。当前小步只使用提炼决定：\(canonicalDecision)"
    modelContext.insert(artifact)
    project.artifacts.append(artifact)

    let stageLabel = stageIndex.map { "第 \($0 + 1) 个结构阶段" } ?? "全项目"
    let promptContext = """
      【作者命题写作 · \(challenge.title) · \(stageLabel)】
      命题：\(challenge.question)
      原文：
      \(String(rawText.prefix(3_600)))

      【当前小步提炼】
      \(canonicalDecision)

      【从原文确认的故事材料】
      \(discoverySummary)
      """
    _ = project.addCreativeIdea(
      text: promptContext,
      scope: .project,
      stageIndex: nil
    )

    let contribution = GuidedFlowContribution(
      challengeID: challenge.id,
      prompt: challenge.promptedWritingPrompt,
      rawText: rawText,
      echo: echo,
      projectArtifactID: artifact.id
    )
    session.recordContribution(contribution)
    project.touch()
  }

  static func applyFoundation(
    _ answer: String,
    stepIndex: Int,
    project: StoryProject,
    modelContext: ModelContext
  ) {
    switch stepIndex {
    case 0:
      if project.creativeDirectionText.guidedTrimmed.isEmpty {
        project.creativeDirectionText = answer
      } else if !project.creativeDirectionText.contains(answer) {
        project.creativeDirectionText += "\n\(answer)"
      }
    case 1:
      if let protagonist = protagonist(in: project) {
        protagonist.seedText = answer
        protagonist.touch()
      } else {
        let character = StoryCharacter(
          name: "主人公",
          role: .protagonist,
          seedText: answer,
          project: project
        )
        modelContext.insert(character)
        project.characters.append(character)
      }
    case 2:
      if let protagonist = protagonist(in: project) {
        protagonist.externalGoal = answer
        protagonist.touch()
      }
    case 3:
      project.dramaticPromise = answer
      if project.coreConflictText.guidedTrimmed.isEmpty {
        project.coreConflictText = answer
      }
    case 4:
      if let protagonist = protagonist(in: project) {
        protagonist.falseBelief = answer
        if protagonist.flaw.guidedTrimmed.isEmpty {
          protagonist.flaw = answer
        }
        protagonist.touch()
      }
    case 5:
      project.logline = answer
      ensureDefaultStructure(for: project)
    default:
      break
    }
    project.touch()
  }

  static func commitStructureStage(
    session: GuidedFlowSession,
    project: StoryProject,
    modelContext: ModelContext
  ) throws {
    let template = project.structureTemplate
    guard template.stages.indices.contains(session.itemIndex) else { return }
    let stage = template.stages[session.itemIndex]
    let prefix = "structure.\(stage.id)"
    let decisionText = session.answer(for: "\(prefix).decision").guidedTrimmed
    let cost = session.answer(for: "\(prefix).cost").guidedTrimmed
    let evidence = session.answer(for: "\(prefix).evidence").guidedTrimmed
    let protagonistName = protagonist(in: project)?.name ?? "主人公"
    let previous =
      project.decisions
      .filter { $0.selectedOptionID != nil && $0.stageIndex < session.itemIndex }
      .sorted { $0.stageIndex < $1.stageIndex }
      .last?.selectedOption?.pitch
      ?? "\(stage.name)尚未发生"
    let mutation = DramaticStateMutation(
      dimension: dimension(for: stage),
      subject: stage.name,
      holder: protagonistName,
      beforeValue: previous,
      afterValue: decisionText,
      observerNames: ["观众"]
    )
    let option = StoryChoiceOption(
      title: compactTitle(decisionText, fallback: stage.name),
      pitch: decisionText,
      concreteDetail: evidence,
      consequence: cost,
      futurePressure: cost,
      sampleMoment: evidence,
      evidenceBasis: ["作者在心流引导中逐步确认"],
      sourceCount: 0,
      realityTexture: "",
      paceEffect: "由当前结构节点产生一次明确状态变化",
      emotionShift: "由行动后果自然产生",
      eventScale: stage.name,
      plannedStateChanges: [mutation],
      audienceUpdate: evidence.isEmpty ? nil : "观众看到：\(evidence)",
      forbiddenChanges: ["不得提前完成后续结构阶段"],
      isLiked: true,
      feedback: "作者逐步完成",
      revisions: []
    )

    let existing = project.decisions.first {
      $0.stageIndex == session.itemIndex && $0.selectedOptionID == nil
    }
    let decision: StoryDecision
    if let existing {
      decision = existing
      decision.phaseRawValue = stage.name
      decision.question = stage.choiceFocus
      decision.coachNote = stage.purpose
      decision.options = [option]
    } else {
      decision = StoryDecision(
        stageName: stage.name,
        stageIndex: session.itemIndex,
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
    decision.authorBrief = [decisionText, cost, evidence]
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
    decision.authorBriefUpdatedAt = .now
    decision.resolvedAt = .now

    project.storyPathText = project.decisions
      .filter { $0.selectedOptionID != nil }
      .sorted { $0.stageIndex < $1.stageIndex }
      .map { "第\($0.stageIndex + 1)阶段 · \($0.stageName)\n\($0.selectedAnswerText)" }
      .joined(separator: "\n\n")
    project.touch()
  }

  static func applyScene(
    _ answer: String,
    session: GuidedFlowSession,
    project: StoryProject
  ) throws {
    let scenes = orderedScenes(in: project)
    guard scenes.indices.contains(session.itemIndex) else {
      throw GuidedFlowError.sceneMissing
    }
    let contract = scenes[session.itemIndex]
    switch session.stepIndex {
    case 0: contract.heading = normalizedHeading(answer)
    case 1: contract.pointOfView = answer
    case 2: contract.characterGoal = answer
    case 3: contract.obstacle = answer
    case 4: contract.turn = answer
    case 5: contract.outcome = answer
    case 6: contract.nextPressure = answer
    default: break
    }
    contract.updatedAt = .now
    project.touch()
  }

  static func commitScene(
    session: GuidedFlowSession,
    project: StoryProject
  ) throws {
    let scenes = orderedScenes(in: project)
    guard scenes.indices.contains(session.itemIndex) else {
      throw GuidedFlowError.sceneMissing
    }
    let contract = scenes[session.itemIndex]
    let before =
      contract.scopeEntryState.guidedTrimmed.isEmpty
      ? "进入本场前的原状态"
      : contract.scopeEntryState
    let after =
      contract.outcome.guidedTrimmed.isEmpty
      ? contract.scopeExitState
      : contract.outcome
    let mutation = DramaticStateMutation(
      dimension: inferredDimension(from: [contract.turn, contract.outcome].joined(separator: " ")),
      subject: contract.scopeTitle.guidedTrimmed.isEmpty ? "场景状态" : contract.scopeTitle,
      holder: contract.pointOfView,
      beforeValue: before,
      afterValue: after,
      observerNames: ["观众"]
    )
    let option = SceneChoiceOption(
      title: compactTitle(contract.turn, fallback: "作者场景方案"),
      approach: "作者在心流引导中逐字段完成",
      heading: contract.heading,
      pointOfView: contract.pointOfView,
      characterGoal: contract.characterGoal,
      obstacle: contract.obstacle,
      turn: contract.turn,
      outcome: contract.outcome,
      nextPressure: contract.nextPressure,
      requiredStateChanges: [mutation],
      audienceUpdate: "观众看到：\(contract.outcome)",
      forbiddenChanges: ["不得提前完成后续场景的状态变化"]
    )
    contract.sceneOptions = [option]
    try SceneMappingEngine.confirm(option, for: contract, in: project)
  }

  static func commitBeat(
    session: GuidedFlowSession,
    project: StoryProject
  ) throws {
    let scenes = orderedScenes(in: project)
    guard scenes.indices.contains(session.itemIndex) else {
      throw GuidedFlowError.sceneMissing
    }
    let contract = scenes[session.itemIndex]
    let prefix = "beat.\(contract.id.uuidString).\(session.subitemIndex)"
    let purpose = session.answer(for: "\(prefix).purpose").guidedTrimmed
    let action = session.answer(for: "\(prefix).action").guidedTrimmed
    let opposition = session.answer(for: "\(prefix).opposition").guidedTrimmed
    let turn = session.answer(for: "\(prefix).turn").guidedTrimmed
    let text = session.answer(for: "\(prefix).text").guidedTrimmed
    let before =
      contract.microBeats.sorted().last?.selectedOption?.outcome
      ?? contract.scopeEntryState
    let mutation = DramaticStateMutation(
      dimension: inferredDimension(from: purpose + " " + turn),
      subject: purpose,
      holder: contract.pointOfView,
      beforeValue: before.guidedTrimmed.isEmpty ? "此前状态" : before,
      afterValue: turn,
      observerNames: ["观众"]
    )
    let option = SceneBeatChoiceOption(
      title: "变化 \(contract.microBeats.count + 1)",
      dramaticAction: action,
      characterAction: action,
      opposition: opposition,
      turn: turn,
      outcome: turn,
      screenplayText: text,
      stateChanges: [mutation],
      audienceUpdate: "观众看到：\(turn)"
    )
    let microBeat = SceneMicroBeat(
      ordinal: contract.microBeats.count + 1,
      purpose: purpose,
      options: [option],
      selectedOptionID: option.id
    )
    var beats = contract.microBeats
    beats.append(microBeat)
    contract.microBeats = beats
    contract.status = "情境更新进行中"
    contract.updatedAt = .now
    project.touch()
  }

  static func applyBeatGate(
    _ answer: String,
    session: GuidedFlowSession,
    project: StoryProject
  ) throws {
    let scenes = orderedScenes(in: project)
    guard scenes.indices.contains(session.itemIndex) else {
      throw GuidedFlowError.sceneMissing
    }
    let contract = scenes[session.itemIndex]
    if answer.contains("继续") || answer.contains("还需要") {
      session.subitemIndex = contract.microBeats.count
      session.stepIndex = 0
    } else {
      contract.status = beatCompleteStatus
      contract.updatedAt = .now
      rebuildScreenplay(project: project)
      let refreshed = orderedScenes(in: project)
      if let next = refreshed.firstIndex(where: { $0.status != beatCompleteStatus }) {
        session.itemIndex = next
        session.subitemIndex = refreshed[next].microBeats.count
        session.stepIndex = 0
      } else {
        session.phase = .screenplay
        session.itemIndex = 0
        session.subitemIndex = 0
        session.stepIndex = 0
      }
    }
  }

  static func applyScreenplayReview(
    _ answer: String,
    session: GuidedFlowSession,
    project: StoryProject
  ) throws {
    let scenes = orderedScenes(in: project)
    guard scenes.indices.contains(session.itemIndex) else {
      throw GuidedFlowError.sceneMissing
    }
    let contract = scenes[session.itemIndex]
    if answer.contains("确认") {
      session.setAnswer("已确认", for: "screenplay.verify.\(contract.id.uuidString)")
      session.itemIndex += 1
      session.stepIndex = 0
    } else {
      contract.status = "已确认"
      contract.updatedAt = .now
      session.removeAnswers(withPrefix: "screenplay.verify.\(contract.id.uuidString)")
      session.phase = .beat
      session.subitemIndex = contract.microBeats.count
      let prefix = "beat.\(contract.id.uuidString).\(session.subitemIndex)"
      session.setAnswer(answer, for: "\(prefix).purpose")
      session.stepIndex = 1
    }
    project.touch()
  }

  private static func contributionStageIndex(
    session: GuidedFlowSession,
    project: StoryProject
  ) -> Int? {
    switch session.phase {
    case .structure:
      return session.itemIndex
    case .scene, .beat:
      let scenes = orderedScenes(in: project)
      guard scenes.indices.contains(session.itemIndex) else { return nil }
      return scenes[session.itemIndex].structureStageIndex
    case .foundation, .screenplay, .completed:
      return nil
    }
  }

  private static func contributionModuleKind(
    for challenge: GuidedFlowChallenge
  ) -> ProjectModuleKind {
    switch challenge.skill {
    case .ideaDiscovery:
      return .inspiration
    case .characterCausality:
      return .character
    case .oppositionAndStakes, .structuralReasoning, .dramaticStateControl:
      return challenge.phase == .scene || challenge.phase == .beat ? .scene : .storyPath
    case .sceneConstruction:
      return .scene
    case .dialogueAndAction, .revisionAndContinuity:
      return .screenplay
    }
  }

}
