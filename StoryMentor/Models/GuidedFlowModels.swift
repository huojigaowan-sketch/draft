import Foundation
import SwiftData

nonisolated enum GuidedFlowPhase: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case foundation = "故事核心"
  case structure = "结构推进"
  case scene = "场景设计"
  case beat = "情境更新"
  case screenplay = "剧本确认"
  case completed = "剧本完成"

  var id: String { rawValue }

  var systemImage: String {
    switch self {
    case .foundation: "leaf.fill"
    case .structure: "point.3.connected.trianglepath.dotted"
    case .scene: "rectangle.stack.fill"
    case .beat: "list.number"
    case .screenplay: "text.book.closed.fill"
    case .completed: "checkmark.seal.fill"
    }
  }
}

nonisolated enum GuidedFlowSkill: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case ideaDiscovery = "发现故事"
  case characterCausality = "人物因果"
  case oppositionAndStakes = "阻力与代价"
  case structuralReasoning = "结构推演"
  case sceneConstruction = "场景构造"
  case dramaticStateControl = "状态变化"
  case dialogueAndAction = "动作与对白"
  case revisionAndContinuity = "修订与连续性"

  var id: String { rawValue }
}

nonisolated enum GuidedFlowAnswerKind: String, Codable, Hashable, Sendable {
  case freeText
  case choice
  case confirmation
}

nonisolated enum GuidedFlowResponseMode: String, CaseIterable, Codable, Hashable, Identifiable,
  Sendable
{
  case focused = "聚焦回答"
  case promptedWriting = "命题写作"

  var id: String { rawValue }

  var systemImage: String {
    switch self {
    case .focused: "scope"
    case .promptedWriting: "doc.text.fill"
    }
  }
}

nonisolated enum GuidedFlowDiscoveryKind: String, CaseIterable, Codable, Hashable, Identifiable,
  Sendable
{
  case character = "活起来的人物"
  case plot = "已经发生的情节"
  case relationship = "关系里的压力"
  case image = "可以拍到的画面"
  case voice = "作者声音"
  case world = "世界与生活细节"
  case theme = "价值与主题"

  var id: String { rawValue }

  var systemImage: String {
    switch self {
    case .character: "person.crop.circle.fill"
    case .plot: "arrow.triangle.branch"
    case .relationship: "person.2.fill"
    case .image: "photo.fill"
    case .voice: "quote.bubble.fill"
    case .world: "globe.asia.australia.fill"
    case .theme: "scope"
    }
  }
}

nonisolated struct GuidedFlowDiscovery: Codable, Hashable, Identifiable, Sendable {
  var id: UUID
  var kindRawValue: String
  var finding: String
  var sourceExcerpt: String

  init(
    id: UUID = UUID(),
    kind: GuidedFlowDiscoveryKind,
    finding: String,
    sourceExcerpt: String
  ) {
    self.id = id
    kindRawValue = kind.rawValue
    self.finding = finding
    self.sourceExcerpt = sourceExcerpt
  }

  var kind: GuidedFlowDiscoveryKind {
    get { GuidedFlowDiscoveryKind(rawValue: kindRawValue) ?? .plot }
    set { kindRawValue = newValue.rawValue }
  }
}

nonisolated struct GuidedFlowContributionEcho: Codable, Hashable, Sendable {
  var headline: String
  var impactSummary: String
  var canonicalDecision: String
  var discoveries: [GuidedFlowDiscovery]
  var preservedLines: [String]
  var nextQuestion: String
}

nonisolated struct GuidedFlowPromptedWritingReview: Hashable, Sendable {
  var isReady: Bool
  var feedback: String
  var singleNudge: String
  var echo: GuidedFlowContributionEcho?
}

nonisolated struct GuidedFlowContribution: Codable, Hashable, Identifiable, Sendable {
  var id: UUID
  var challengeID: String
  var prompt: String
  var rawText: String
  var echo: GuidedFlowContributionEcho
  var projectArtifactID: UUID?
  var createdAt: Date

  init(
    id: UUID = UUID(),
    challengeID: String,
    prompt: String,
    rawText: String,
    echo: GuidedFlowContributionEcho,
    projectArtifactID: UUID? = nil,
    createdAt: Date = .now
  ) {
    self.id = id
    self.challengeID = challengeID
    self.prompt = prompt
    self.rawText = rawText
    self.echo = echo
    self.projectArtifactID = projectArtifactID
    self.createdAt = createdAt
  }
}

nonisolated enum GuidedFlowScaffoldLevel: Int, CaseIterable, Codable, Hashable, Comparable, Sendable
{
  case questionOnly = 0
  case reframe = 1
  case rule = 2
  case mechanisms = 3
  case sentenceStarter = 4
  case minimalAssist = 5

  static func < (lhs: GuidedFlowScaffoldLevel, rhs: GuidedFlowScaffoldLevel) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  var label: String {
    switch self {
    case .questionOnly: "独立尝试"
    case .reframe: "换一种问法"
    case .rule: "查看规则"
    case .mechanisms: "查看机制"
    case .sentenceStarter: "半成品支架"
    case .minimalAssist: "AI 只补当前一步"
    }
  }
}

nonisolated struct GuidedFlowDifficultyProfile: Codable, Hashable, Sendable {
  var openness: Int
  var constraintLoad: Int
  var causalHorizon: Int
  var stateComplexity: Int
  var executionLoad: Int

  init(
    openness: Int,
    constraintLoad: Int,
    causalHorizon: Int,
    stateComplexity: Int,
    executionLoad: Int
  ) {
    self.openness = Self.clamp(openness)
    self.constraintLoad = Self.clamp(constraintLoad)
    self.causalHorizon = Self.clamp(causalHorizon)
    self.stateComplexity = Self.clamp(stateComplexity)
    self.executionLoad = Self.clamp(executionLoad)
  }

  var aggregate: Double {
    Double(openness + constraintLoad + causalHorizon + stateComplexity + executionLoad) / 5.0
  }

  var label: String {
    switch aggregate {
    case ..<0.9: "轻松推进"
    case ..<1.8: "当前匹配"
    case ..<2.8: "稍有拉伸"
    default: "建议拆分"
    }
  }

  private static func clamp(_ value: Int) -> Int {
    min(4, max(0, value))
  }
}

nonisolated struct GuidedFlowChallenge: Identifiable, Hashable, Sendable {
  var id: String
  var phase: GuidedFlowPhase
  var title: String
  var question: String
  var whyItMatters: String
  var placeholder: String
  var referenceText: String
  var skill: GuidedFlowSkill
  var answerKind: GuidedFlowAnswerKind
  var options: [String]
  var minimumCharacters: Int
  var maximumCharacters: Int
  var reframe: String
  var ruleHint: String
  var mechanismHints: [String]
  var sentenceStarter: String
  var minimalAssistInstruction: String
  var successContract: [String]
  var difficulty: GuidedFlowDifficultyProfile

  var supportsPromptedWriting: Bool {
    guard answerKind == .freeText, phase != .screenplay else { return false }
    return !id.hasSuffix(".heading") && !id.hasSuffix(".pov")
  }

  var promptedWritingPrompt: String {
    let lead = "命题：《\(title)》"
    switch phase {
    case .foundation:
      return """
        \(lead)
        围绕“\(question)”写一篇短文。不要急着介绍完整设定；写一个你能看见的具体时刻，让人物的动作、犹豫、关系或生活细节自然出现。
        """
    case .structure:
      return """
        \(lead)
        写主人公走到这一步前后的一段经历。可以写动作、对话、回忆和观察，但只让当前这个决定、代价或变化发生，不必继续写后面的全部剧情。
        """
    case .scene:
      return """
        \(lead)
        把当前问题放进这场戏的一个具体时刻里。你可以像写小说或命题作文一样写人物、动作、对话和环境，不需要使用剧本格式。
        """
    case .beat:
      return """
        \(lead)
        只围绕当前这一次情境变化写一个片段。可以写动作、对白、观察和停顿，但不要跳到后续场景或替人物完成全部故事。
        """
    case .screenplay, .completed:
      return lead
    }
  }

  var promptedWritingPlaceholder: String {
    "从一个具体时刻写起。可以先写人物正在做什么、他在躲避什么，或哪一个细节让局面开始不一样……"
  }

  func minimumCharacters(for mode: GuidedFlowResponseMode) -> Int {
    mode == .promptedWriting ? max(120, minimumCharacters) : minimumCharacters
  }

  func maximumCharacters(for mode: GuidedFlowResponseMode) -> Int {
    mode == .promptedWriting ? 5_000 : maximumCharacters
  }

  func supportText(for level: GuidedFlowScaffoldLevel) -> String {
    switch level {
    case .questionOnly:
      ""
    case .reframe:
      reframe
    case .rule:
      ruleHint
    case .mechanisms:
      mechanismHints.map { "• \($0)" }.joined(separator: "\n")
    case .sentenceStarter:
      sentenceStarter
    case .minimalAssist:
      minimalAssistInstruction
    }
  }
}

nonisolated struct GuidedFlowAcceptedStep: Codable, Hashable, Identifiable, Sendable {
  var id: UUID
  var challengeID: String
  var phaseRawValue: String
  var itemIndex: Int
  var subitemIndex: Int
  var stepIndex: Int
  var question: String
  var answer: String
  var acceptedSummary: String
  var skillRawValue: String
  var scaffoldLevel: Int
  var responseModeRawValue: String?
  var wasFirstPass: Bool
  var createdAt: Date

  init(
    id: UUID = UUID(),
    challenge: GuidedFlowChallenge,
    itemIndex: Int,
    subitemIndex: Int,
    stepIndex: Int,
    answer: String,
    acceptedSummary: String,
    scaffoldLevel: GuidedFlowScaffoldLevel,
    responseMode: GuidedFlowResponseMode = .focused,
    wasFirstPass: Bool,
    createdAt: Date = .now
  ) {
    self.id = id
    challengeID = challenge.id
    phaseRawValue = challenge.phase.rawValue
    self.itemIndex = itemIndex
    self.subitemIndex = subitemIndex
    self.stepIndex = stepIndex
    question = challenge.question
    self.answer = answer
    self.acceptedSummary = acceptedSummary
    skillRawValue = challenge.skill.rawValue
    self.scaffoldLevel = scaffoldLevel.rawValue
    responseModeRawValue = responseMode.rawValue
    self.wasFirstPass = wasFirstPass
    self.createdAt = createdAt
  }

  var phase: GuidedFlowPhase {
    GuidedFlowPhase(rawValue: phaseRawValue) ?? .foundation
  }

  var skill: GuidedFlowSkill {
    GuidedFlowSkill(rawValue: skillRawValue) ?? .ideaDiscovery
  }

  var responseMode: GuidedFlowResponseMode {
    GuidedFlowResponseMode(rawValue: responseModeRawValue ?? "") ?? .focused
  }
}

nonisolated struct GuidedFlowAttempt: Codable, Hashable, Identifiable, Sendable {
  var id: UUID
  var challengeID: String
  var answer: String
  var passedLocalChecks: Bool
  var passedCoachReview: Bool?
  var scaffoldLevel: Int
  var responseModeRawValue: String?
  var feedback: String
  var createdAt: Date

  init(
    id: UUID = UUID(),
    challengeID: String,
    answer: String,
    passedLocalChecks: Bool,
    passedCoachReview: Bool?,
    scaffoldLevel: GuidedFlowScaffoldLevel,
    responseMode: GuidedFlowResponseMode = .focused,
    feedback: String,
    createdAt: Date = .now
  ) {
    self.id = id
    self.challengeID = challengeID
    self.answer = answer
    self.passedLocalChecks = passedLocalChecks
    self.passedCoachReview = passedCoachReview
    self.scaffoldLevel = scaffoldLevel.rawValue
    responseModeRawValue = responseMode.rawValue
    self.feedback = feedback
    self.createdAt = createdAt
  }

  var responseMode: GuidedFlowResponseMode {
    GuidedFlowResponseMode(rawValue: responseModeRawValue ?? "") ?? .focused
  }
}

nonisolated struct GuidedFlowEvaluation: Hashable, Sendable {
  var isReady: Bool
  var feedback: String
  var singleNudge: String
  var acceptedSummary: String
}

@Model
final class GuidedFlowSession {
  @Attribute(.unique) var id: UUID
  var projectID: UUID
  var phaseRawValue: String
  var itemIndex: Int
  var subitemIndex: Int
  var stepIndex: Int
  var scaffoldLevelRawValue: Int
  var targetStretch: Int
  var consecutiveFirstPasses: Int
  var currentDraft: String
  var lastFeedback: String
  var lastNudge: String
  var awaitingRevision: Bool
  var pendingAcceptedSummary: String
  var responseModeRawValue: String = GuidedFlowResponseMode.focused.rawValue
  var pendingContributionData: Data = Data()
  var contributionsData: Data = Data()
  var acceptedStepsData: Data
  var attemptsData: Data
  var answerMapData: Data
  var createdAt: Date
  var updatedAt: Date

  init(
    id: UUID = UUID(),
    projectID: UUID,
    phase: GuidedFlowPhase,
    itemIndex: Int = 0,
    subitemIndex: Int = 0,
    stepIndex: Int = 0,
    scaffoldLevel: GuidedFlowScaffoldLevel = .questionOnly,
    responseMode: GuidedFlowResponseMode = .focused,
    targetStretch: Int = 0,
    createdAt: Date = .now
  ) {
    self.id = id
    self.projectID = projectID
    phaseRawValue = phase.rawValue
    self.itemIndex = itemIndex
    self.subitemIndex = subitemIndex
    self.stepIndex = stepIndex
    scaffoldLevelRawValue = scaffoldLevel.rawValue
    self.targetStretch = min(4, max(0, targetStretch))
    consecutiveFirstPasses = 0
    currentDraft = ""
    lastFeedback = ""
    lastNudge = ""
    awaitingRevision = false
    pendingAcceptedSummary = ""
    responseModeRawValue = responseMode.rawValue
    pendingContributionData = Data()
    contributionsData = Data()
    acceptedStepsData = Data()
    attemptsData = Data()
    answerMapData = Data()
    self.createdAt = createdAt
    updatedAt = createdAt
  }
}

extension GuidedFlowSession {
  var phase: GuidedFlowPhase {
    get { GuidedFlowPhase(rawValue: phaseRawValue) ?? .foundation }
    set {
      phaseRawValue = newValue.rawValue
      touch()
    }
  }

  var scaffoldLevel: GuidedFlowScaffoldLevel {
    get { GuidedFlowScaffoldLevel(rawValue: scaffoldLevelRawValue) ?? .questionOnly }
    set {
      scaffoldLevelRawValue = newValue.rawValue
      touch()
    }
  }

  var responseMode: GuidedFlowResponseMode {
    get { GuidedFlowResponseMode(rawValue: responseModeRawValue) ?? .focused }
    set {
      responseModeRawValue = newValue.rawValue
      touch()
    }
  }

  var pendingContribution: GuidedFlowContribution? {
    get {
      PersistentPayloadCodec.decodeOptional(
        GuidedFlowContribution.self,
        from: pendingContributionData,
        label: "GuidedFlowSession.pendingContribution"
      )
    }
    set {
      if let newValue {
        pendingContributionData = PersistentPayloadCodec.encode(
          newValue,
          preserving: pendingContributionData,
          label: "GuidedFlowSession.pendingContribution"
        )
      } else {
        pendingContributionData = Data()
      }
      touch()
    }
  }

  var contributions: [GuidedFlowContribution] {
    get {
      PersistentPayloadCodec.decode(
        [GuidedFlowContribution].self,
        from: contributionsData,
        default: [],
        label: "GuidedFlowSession.contributions"
      )
    }
    set {
      contributionsData = PersistentPayloadCodec.encode(
        newValue,
        preserving: contributionsData,
        label: "GuidedFlowSession.contributions"
      )
      touch()
    }
  }

  var acceptedSteps: [GuidedFlowAcceptedStep] {
    get {
      PersistentPayloadCodec.decode(
        [GuidedFlowAcceptedStep].self,
        from: acceptedStepsData,
        default: [],
        label: "GuidedFlowSession.acceptedSteps"
      )
    }
    set {
      acceptedStepsData = PersistentPayloadCodec.encode(
        newValue,
        preserving: acceptedStepsData,
        label: "GuidedFlowSession.acceptedSteps"
      )
      touch()
    }
  }

  var attempts: [GuidedFlowAttempt] {
    get {
      PersistentPayloadCodec.decode(
        [GuidedFlowAttempt].self,
        from: attemptsData,
        default: [],
        label: "GuidedFlowSession.attempts"
      )
    }
    set {
      attemptsData = PersistentPayloadCodec.encode(
        newValue,
        preserving: attemptsData,
        label: "GuidedFlowSession.attempts"
      )
      touch()
    }
  }

  var answerMap: [String: String] {
    get {
      PersistentPayloadCodec.decode(
        [String: String].self,
        from: answerMapData,
        default: [:],
        label: "GuidedFlowSession.answerMap"
      )
    }
    set {
      answerMapData = PersistentPayloadCodec.encode(
        newValue,
        preserving: answerMapData,
        label: "GuidedFlowSession.answerMap"
      )
      touch()
    }
  }

  func answer(for key: String) -> String {
    answerMap[key] ?? ""
  }

  func setAnswer(_ answer: String, for key: String) {
    var values = answerMap
    values[key] = answer
    answerMap = values
  }

  func removeAnswers(withPrefix prefix: String) {
    answerMap = answerMap.filter { !$0.key.hasPrefix(prefix) }
  }

  func recordAttempt(_ attempt: GuidedFlowAttempt) {
    var values = attempts
    values.append(attempt)
    attempts = Array(values.suffix(400))
  }

  func recordAcceptedStep(_ step: GuidedFlowAcceptedStep) {
    var values = acceptedSteps
    values.append(step)
    acceptedSteps = Array(values.suffix(500))
  }

  func recordContribution(_ contribution: GuidedFlowContribution) {
    var values = contributions
    values.append(contribution)
    contributions = Array(values.suffix(120))
    pendingContribution = contribution
  }

  func resetTurnState() {
    currentDraft = ""
    lastFeedback = ""
    lastNudge = ""
    awaitingRevision = false
    pendingAcceptedSummary = ""
    scaffoldLevel = .questionOnly
    touch()
  }

  func touch() {
    updatedAt = .now
  }
}
