import Foundation
import SwiftData

@MainActor
enum GuidedFlowCoordinator {
  static let beatCompleteStatus = "引导小节拍已完成"

  static func makeSession(for project: StoryProject) -> GuidedFlowSession {
    let location = inferredLocation(for: project)
    return GuidedFlowSession(
      projectID: project.id,
      phase: location.phase,
      itemIndex: location.itemIndex,
      subitemIndex: location.subitemIndex,
      stepIndex: location.stepIndex,
      targetStretch: 0
    )
  }

  static func bootstrap(
    _ session: GuidedFlowSession,
    project: StoryProject,
    modelContext: ModelContext
  ) {
    if session.phase == .structure {
      ensureDefaultStructure(for: project)
    }
    if session.phase == .scene,
      project.isStructureLocked,
      project.nextStructureStageIndex == nil
    {
      _ = SceneMappingEngine.synchronizeConfirmedStages(
        in: project,
        modelContext: modelContext
      )
      modelContext.processPendingChanges()
    }
    normalize(session, project: project, modelContext: modelContext)
  }

  static func challenge(
    for session: GuidedFlowSession,
    project: StoryProject
  ) -> GuidedFlowChallenge? {
    switch session.phase {
    case .foundation:
      foundationChallenge(index: session.stepIndex, stretch: session.targetStretch)
    case .structure:
      structureChallenge(session: session, project: project)
    case .scene:
      sceneChallenge(session: session, project: project)
    case .beat:
      beatChallenge(session: session, project: project)
    case .screenplay:
      screenplayChallenge(session: session, project: project)
    case .completed:
      nil
    }
  }

  static func localEvaluation(
    answer: String,
    challenge: GuidedFlowChallenge,
    responseMode: GuidedFlowResponseMode = .focused
  ) -> GuidedFlowEvaluation {
    let clean = answer.guidedTrimmed
    let minimum = challenge.minimumCharacters(for: responseMode)
    let maximum = challenge.maximumCharacters(for: responseMode)
    guard !clean.isEmpty else {
      return GuidedFlowEvaluation(
        isReady: false,
        feedback: responseMode == .promptedWriting
          ? "先写下一个具体时刻。这里不要求剧本格式，也不要求一次写完整故事。"
          : "先留下一个具体判断。这里没有标准答案，但不能是空白。",
        singleNudge: responseMode == .promptedWriting
          ? challenge.promptedWritingPlaceholder
          : challenge.reframe,
        acceptedSummary: ""
      )
    }
    guard clean.count >= minimum else {
      return GuidedFlowEvaluation(
        isReady: false,
        feedback: responseMode == .promptedWriting
          ? "这段文字还没有展开到足以看见人物、动作或局面变化。"
          : "现在的回答还不足以形成一个可继续使用的故事决定。",
        singleNudge: responseMode == .promptedWriting
          ? "再写一个具体细节：人物正在做什么、谁在场、哪句话或哪个动作让事情变了？"
          : (challenge.sentenceStarter.isEmpty ? challenge.reframe : challenge.sentenceStarter),
        acceptedSummary: ""
      )
    }
    guard clean.count <= maximum else {
      return GuidedFlowEvaluation(
        isReady: false,
        feedback: responseMode == .promptedWriting
          ? "全文已经很充足，但当前输入超过了本轮可稳定保存和分析的范围。"
          : "这一步只解决一个问题。请删去解释，只保留最关键的决定。",
        singleNudge: responseMode == .promptedWriting
          ? "保留最有画面、最能让人物行动的部分，把全文收在 \(maximum) 字以内。"
          : "把回答压到 \(maximum) 字以内。",
        acceptedSummary: ""
      )
    }
    if ["不知道", "随便", "都可以", "没有"].contains(clean) {
      return GuidedFlowEvaluation(
        isReady: false,
        feedback: "这还不是创作决定。先选一个你稍微更好奇的方向即可。",
        singleNudge: challenge.options.first ?? challenge.reframe,
        acceptedSummary: ""
      )
    }

    let acceptedSummary: String
    if responseMode == .promptedWriting {
      acceptedSummary = GuidedFlowContributionAnalyzer.canonicalDecision(
        from: clean,
        challenge: challenge
      )
    } else {
      acceptedSummary = String(clean.prefix(120))
    }
    return GuidedFlowEvaluation(
      isReady: true,
      feedback: responseMode == .promptedWriting
        ? "这篇文字已经足够提炼人物、情节和当前决定。"
        : "基本边界已经满足。",
      singleNudge: "",
      acceptedSummary: acceptedSummary
    )
  }

  static func recordFailedAttempt(
    answer: String,
    challenge: GuidedFlowChallenge,
    feedback: String,
    passedLocalChecks: Bool,
    coachReviewed: Bool?,
    responseMode: GuidedFlowResponseMode? = nil,
    session: GuidedFlowSession
  ) {
    session.recordAttempt(
      GuidedFlowAttempt(
        challengeID: challenge.id,
        answer: answer.guidedTrimmed,
        passedLocalChecks: passedLocalChecks,
        passedCoachReview: coachReviewed,
        scaffoldLevel: session.scaffoldLevel,
        responseMode: responseMode ?? session.responseMode,
        feedback: feedback
      )
    )
    session.awaitingRevision = true
    session.lastFeedback = feedback
    session.lastNudge = challenge.supportText(
      for: max(session.scaffoldLevel, .reframe)
    )
    session.consecutiveFirstPasses = 0
    if session.scaffoldLevel >= .mechanisms {
      session.targetStretch = max(0, session.targetStretch - 1)
    }
    session.touch()
  }

  static func accept(
    answer: String,
    acceptedSummary: String,
    challenge: GuidedFlowChallenge,
    coachReviewed: Bool?,
    responseMode: GuidedFlowResponseMode = .focused,
    contributionEcho: GuidedFlowContributionEcho? = nil,
    session: GuidedFlowSession,
    project: StoryProject,
    modelContext: ModelContext
  ) throws {
    let clean = answer.guidedTrimmed
    let earlierAttempts = session.attempts.filter { $0.challengeID == challenge.id }.count
    let wasFirstPass = earlierAttempts == 0 && session.scaffoldLevel == .questionOnly
    let fallbackCanonical = GuidedFlowContributionAnalyzer.canonicalDecision(
      from: clean,
      challenge: challenge
    )
    let echoCanonical = contributionEcho?.canonicalDecision.guidedTrimmed ?? ""
    let canonicalSummary =
      responseMode == .promptedWriting
      ? (!echoCanonical.isEmpty
        ? echoCanonical
        : (acceptedSummary.guidedTrimmed.isEmpty
          ? fallbackCanonical : acceptedSummary.guidedTrimmed))
      : (acceptedSummary.guidedTrimmed.isEmpty
        ? String(clean.prefix(140)) : acceptedSummary.guidedTrimmed)
    let appliedAnswer: String
    if responseMode == .promptedWriting,
      challenge.phase == .beat,
      challenge.id.hasSuffix(".text")
    {
      appliedAnswer = clean
    } else if responseMode == .promptedWriting {
      appliedAnswer = canonicalSummary
    } else {
      appliedAnswer = clean
    }

    session.recordAttempt(
      GuidedFlowAttempt(
        challengeID: challenge.id,
        answer: clean,
        passedLocalChecks: true,
        passedCoachReview: coachReviewed,
        scaffoldLevel: session.scaffoldLevel,
        responseMode: responseMode,
        feedback: "已确认"
      )
    )
    session.recordAcceptedStep(
      GuidedFlowAcceptedStep(
        challenge: challenge,
        itemIndex: session.itemIndex,
        subitemIndex: session.subitemIndex,
        stepIndex: session.stepIndex,
        answer: clean,
        acceptedSummary: String(canonicalSummary.prefix(220)),
        scaffoldLevel: session.scaffoldLevel,
        responseMode: responseMode,
        wasFirstPass: wasFirstPass
      )
    )
    session.setAnswer(appliedAnswer, for: challenge.id)

    if responseMode == .promptedWriting {
      let echo =
        contributionEcho
        ?? GuidedFlowContributionAnalyzer.localReview(
          answer: clean,
          challenge: challenge
        ).echo
      if let echo {
        recordPromptedWritingContribution(
          rawText: clean,
          canonicalDecision: canonicalSummary,
          echo: echo,
          challenge: challenge,
          session: session,
          project: project,
          modelContext: modelContext
        )
      }
    }

    try apply(
      appliedAnswer,
      challenge: challenge,
      session: session,
      project: project,
      modelContext: modelContext
    )

    if wasFirstPass {
      session.consecutiveFirstPasses += 1
      if session.consecutiveFirstPasses >= 2 {
        session.targetStretch = min(4, session.targetStretch + 1)
        session.consecutiveFirstPasses = 0
      }
    } else {
      session.consecutiveFirstPasses = 0
      if session.scaffoldLevel >= .sentenceStarter {
        session.targetStretch = max(0, session.targetStretch - 1)
      }
    }

    session.resetTurnState()
    normalize(session, project: project, modelContext: modelContext)
    project.touch()
    try ProjectPersistenceStore.savePendingChanges(in: modelContext)
  }

  static func requestNextSupport(
    for session: GuidedFlowSession,
    challenge: GuidedFlowChallenge
  ) {
    let nextRaw = min(
      GuidedFlowScaffoldLevel.minimalAssist.rawValue,
      session.scaffoldLevel.rawValue + 1
    )
    let next = GuidedFlowScaffoldLevel(rawValue: nextRaw) ?? .minimalAssist
    session.scaffoldLevel = next
    session.lastNudge = challenge.supportText(for: next)
    session.awaitingRevision = false
    session.touch()
  }

  static func progress(
    session: GuidedFlowSession,
    project: StoryProject
  ) -> Double {
    switch session.phase {
    case .foundation:
      Double(min(session.stepIndex, foundationStepCount)) / Double(foundationStepCount)
    case .structure:
      let total = max(project.structureTemplate.stages.count, 1)
      let base = Double(project.resolvedDecisionCount)
      let partial = Double(min(session.stepIndex, 2)) / 3.0
      return min(1, (base + partial) / Double(total))
    case .scene:
      let scenes = orderedScenes(in: project)
      guard !scenes.isEmpty else { return 0 }
      let confirmed = scenes.filter { $0.selectedSceneOptionID != nil }.count
      return Double(confirmed) / Double(scenes.count)
    case .beat:
      let scenes = orderedScenes(in: project)
      guard !scenes.isEmpty else { return 0 }
      let finished = scenes.filter { $0.status == beatCompleteStatus }.count
      return Double(finished) / Double(scenes.count)
    case .screenplay:
      let total = max(orderedScenes(in: project).count, 1)
      return min(1, Double(session.itemIndex) / Double(total))
    case .completed:
      return 1
    }
  }

  static func overallProgress(
    session: GuidedFlowSession,
    project: StoryProject
  ) -> Double {
    let phaseWeights: [GuidedFlowPhase: (start: Double, width: Double)] = [
      .foundation: (0.00, 0.12),
      .structure: (0.12, 0.28),
      .scene: (0.40, 0.20),
      .beat: (0.60, 0.28),
      .screenplay: (0.88, 0.12),
      .completed: (1.00, 0.00),
    ]
    let weight = phaseWeights[session.phase] ?? (0, 1)
    return min(1, weight.start + progress(session: session, project: project) * weight.width)
  }

  static func rebuildScreenplay(
    project: StoryProject,
    includeIncompleteScenes: Bool = false
  ) {
    let scenes = orderedScenes(in: project)
    let texts = scenes.compactMap { contract -> String? in
      if !includeIncompleteScenes,
        contract.status != beatCompleteStatus
      {
        return nil
      }
      return try? SceneBeatMappingEngine.screenplayScene(for: contract)
    }
    guard !texts.isEmpty else { return }
    project.screenplayText = texts.joined(separator: "\n\n")
    project.touch()
  }

  // MARK: - Location and normalization

  private static let foundationStepCount = 6

  private struct Location {
    var phase: GuidedFlowPhase
    var itemIndex: Int
    var subitemIndex: Int
    var stepIndex: Int
  }

  private static func inferredLocation(for project: StoryProject) -> Location {
    if let missing = firstMissingFoundationStep(in: project) {
      return Location(
        phase: .foundation,
        itemIndex: 0,
        subitemIndex: 0,
        stepIndex: missing
      )
    }

    if !project.isStructureLocked || project.nextStructureStageIndex != nil {
      return Location(
        phase: .structure,
        itemIndex: project.nextStructureStageIndex ?? 0,
        subitemIndex: 0,
        stepIndex: 0
      )
    }

    let scenes = orderedScenes(in: project)
    if scenes.isEmpty || scenes.contains(where: { $0.selectedSceneOptionID == nil }) {
      return Location(
        phase: .scene,
        itemIndex: max(0, scenes.firstIndex(where: { $0.selectedSceneOptionID == nil }) ?? 0),
        subitemIndex: 0,
        stepIndex: 0
      )
    }

    if let beatIndex = scenes.firstIndex(where: { $0.status != beatCompleteStatus }) {
      return Location(
        phase: .beat,
        itemIndex: beatIndex,
        subitemIndex: scenes[beatIndex].microBeats.count,
        stepIndex: 0
      )
    }

    if project.screenplayText.guidedTrimmed.isEmpty {
      return Location(
        phase: .screenplay,
        itemIndex: 0,
        subitemIndex: 0,
        stepIndex: 0
      )
    }

    return Location(
      phase: .completed,
      itemIndex: 0,
      subitemIndex: 0,
      stepIndex: 0
    )
  }

  private static func normalize(
    _ session: GuidedFlowSession,
    project: StoryProject,
    modelContext: ModelContext
  ) {
    switch session.phase {
    case .foundation:
      if session.stepIndex >= foundationStepCount {
        ensureDefaultStructure(for: project)
        session.phase = .structure
        session.itemIndex = project.nextStructureStageIndex ?? 0
        session.subitemIndex = 0
        session.stepIndex = 0
      }

    case .structure:
      ensureDefaultStructure(for: project)
      if let next = project.nextStructureStageIndex {
        if session.itemIndex != next {
          session.itemIndex = next
          session.stepIndex = 0
          session.subitemIndex = 0
        }
      } else {
        _ = SceneMappingEngine.synchronizeConfirmedStages(
          in: project,
          modelContext: modelContext
        )
        modelContext.processPendingChanges()
        session.phase = .scene
        session.itemIndex = 0
        session.subitemIndex = 0
        session.stepIndex = 0
      }

    case .scene:
      let scenes = orderedScenes(in: project)
      if scenes.isEmpty,
        project.isStructureLocked,
        project.nextStructureStageIndex == nil
      {
        _ = SceneMappingEngine.synchronizeConfirmedStages(
          in: project,
          modelContext: modelContext
        )
        modelContext.processPendingChanges()
      }
      let refreshed = orderedScenes(in: project)
      if let next = refreshed.firstIndex(where: { $0.selectedSceneOptionID == nil }) {
        session.itemIndex = next
        session.stepIndex = min(session.stepIndex, 6)
      } else if !refreshed.isEmpty {
        session.phase = .beat
        session.itemIndex =
          refreshed.firstIndex(where: {
            $0.status != beatCompleteStatus
          }) ?? 0
        session.subitemIndex = refreshed[session.itemIndex].microBeats.count
        session.stepIndex = 0
      }

    case .beat:
      let scenes = orderedScenes(in: project)
      if let next = scenes.firstIndex(where: { $0.status != beatCompleteStatus }) {
        if session.itemIndex != next {
          session.itemIndex = next
          session.subitemIndex = scenes[next].microBeats.count
          session.stepIndex = 0
        }
      } else if !scenes.isEmpty {
        rebuildScreenplay(project: project)
        session.phase = .screenplay
        session.itemIndex = 0
        session.subitemIndex = 0
        session.stepIndex = 0
      }

    case .screenplay:
      let scenes = orderedScenes(in: project)
      while session.itemIndex < scenes.count {
        let key = "screenplay.verify.\(scenes[session.itemIndex].id.uuidString)"
        guard session.answer(for: key) == "已确认" else { break }
        session.itemIndex += 1
      }
      if session.itemIndex >= scenes.count {
        rebuildScreenplay(project: project)
        session.phase = .completed
        session.itemIndex = 0
        session.subitemIndex = 0
        session.stepIndex = 0
      }

    case .completed:
      break
    }
    session.touch()
  }

  private static func firstMissingFoundationStep(in project: StoryProject) -> Int? {
    if project.creativeDirectionText.guidedTrimmed.isEmpty
      && project.sourceText.guidedTrimmed.isEmpty
      && project.logline.guidedTrimmed.isEmpty
    {
      return 0
    }
    guard let protagonist = protagonist(in: project) else { return 1 }
    if protagonist.externalGoal.guidedTrimmed.isEmpty { return 2 }
    if project.dramaticPromise.guidedTrimmed.isEmpty
      && project.coreConflictText.guidedTrimmed.isEmpty
    {
      return 3
    }
    if protagonist.falseBelief.guidedTrimmed.isEmpty
      && protagonist.flaw.guidedTrimmed.isEmpty
    {
      return 4
    }
    if project.logline.guidedTrimmed.isEmpty { return 5 }
    return nil
  }

  // MARK: - Helpers

  static func ensureDefaultStructure(for project: StoryProject) {
    if !project.hasSelectedStructureTemplate {
      let template = StoryStructureCatalog.defaultTemplate
      project.structureTemplateID = template.id
      project.structureTemplateName = template.name
      project.structureRulesText = template.rulesPrompt
    }
    if !project.isStructureLocked {
      project.lockStructure()
    }
  }

  static func protagonist(in project: StoryProject) -> StoryCharacter? {
    project.characters.first { $0.role == .protagonist }
      ?? project.characters.first
  }

  static func orderedScenes(in project: StoryProject) -> [SceneContract] {
    project.sceneContracts.sorted {
      if $0.sceneIndex == $1.sceneIndex {
        return $0.createdAt < $1.createdAt
      }
      return $0.sceneIndex < $1.sceneIndex
    }
  }

  static func compactTitle(_ text: String, fallback: String) -> String {
    let clean = text.guidedTrimmed
    guard !clean.isEmpty else { return fallback }
    return String(clean.prefix(18))
  }

  static func normalizedHeading(_ answer: String) -> String {
    let clean = answer.guidedTrimmed
    let uppercase = clean.uppercased()
    if uppercase.hasPrefix("INT.")
      || uppercase.hasPrefix("EXT.")
      || clean.hasPrefix("内.")
      || clean.hasPrefix("外.")
    {
      return clean
    }
    return "内. \(clean) - 日"
  }

  static func mechanismHints(for stage: StructureStage) -> [String] {
    let text = stage.name + stage.purpose + stage.choiceFocus
    if text.contains("关系") || text.contains("盟友") || text.contains("背叛") {
      return ["一次信任交换", "一项无法同时兑现的承诺", "一个关系中的权力倒转"]
    }
    if text.contains("揭示") || text.contains("真相") || text.contains("中点") {
      return ["发现目标本身理解错了", "确认对手早已知情", "观众先看见人物仍未知道的危险"]
    }
    if text.contains("高潮") || text.contains("选择") || text.contains("不可逆") {
      return ["得到目标但失去关系", "保护别人却暴露自己", "放弃旧利益证明改变"]
    }
    if text.contains("对手") || text.contains("压力") || text.contains("危机") {
      return ["对手学习并反制旧策略", "制度关闭退路", "此前的成功释放更昂贵后果"]
    }
    return ["人物主动做出决定", "旧方法暂时有效却制造后果", "一个新事实迫使更换策略"]
  }

  static func dimension(for stage: StructureStage) -> DramaticStateDimension {
    inferredDimension(from: stage.name + stage.purpose + stage.choiceFocus)
  }

  static func inferredDimension(from text: String) -> DramaticStateDimension {
    if text.contains("关系")
      || text.contains("信任")
      || text.contains("权力")
      || text.contains("背叛")
    {
      return .relationship
    }
    if text.contains("知道")
      || text.contains("发现")
      || text.contains("真相")
      || text.contains("相信")
      || text.contains("误解")
    {
      return .knowledge
    }
    if text.contains("观众")
      || text.contains("悬念")
      || text.contains("信息差")
    {
      return .audience
    }
    if text.contains("承诺")
      || text.contains("规则")
      || text.contains("道德")
      || text.contains("责任")
    {
      return .norm
    }
    if text.contains("世界")
      || text.contains("环境")
      || text.contains("制度")
      || text.contains("地点")
    {
      return .world
    }
    return .goal
  }
}

extension String {
  var guidedTrimmed: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

enum GuidedFlowError: LocalizedError {
  case sceneMissing

  var errorDescription: String? {
    switch self {
    case .sceneMissing:
      "当前场景已经变化，请重新进入这一步。"
    }
  }
}
