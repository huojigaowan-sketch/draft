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
    self.wasFirstPass = wasFirstPass
    self.createdAt = createdAt
  }

  var phase: GuidedFlowPhase {
    GuidedFlowPhase(rawValue: phaseRawValue) ?? .foundation
  }

  var skill: GuidedFlowSkill {
    GuidedFlowSkill(rawValue: skillRawValue) ?? .ideaDiscovery
  }
}

nonisolated struct GuidedFlowAttempt: Codable, Hashable, Identifiable, Sendable {
  var id: UUID
  var challengeID: String
  var answer: String
  var passedLocalChecks: Bool
  var passedCoachReview: Bool?
  var scaffoldLevel: Int
  var feedback: String
  var createdAt: Date

  init(
    id: UUID = UUID(),
    challengeID: String,
    answer: String,
    passedLocalChecks: Bool,
    passedCoachReview: Bool?,
    scaffoldLevel: GuidedFlowScaffoldLevel,
    feedback: String,
    createdAt: Date = .now
  ) {
    self.id = id
    self.challengeID = challengeID
    self.answer = answer
    self.passedLocalChecks = passedLocalChecks
    self.passedCoachReview = passedCoachReview
    self.scaffoldLevel = scaffoldLevel.rawValue
    self.feedback = feedback
    self.createdAt = createdAt
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
