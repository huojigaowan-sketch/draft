import Foundation

nonisolated enum GuidedScriptScale: String, CaseIterable, Codable, Identifiable, Sendable {
  case shortDrama = "短剧 / 短片"
  case shortFilm = "中短篇"
  case feature = "电影长片"

  var id: String { rawValue }

  var subtitle: String {
    switch self {
    case .shortDrama:
      "约 8—15 场，适合 5—15 分钟"
    case .shortFilm:
      "约 18—24 场，适合 20—45 分钟"
    case .feature:
      "约 36—44 场，适合 80—110 分钟"
    }
  }

  var targetSceneCount: Int {
    switch self {
    case .shortDrama: 12
    case .shortFilm: 22
    case .feature: 40
    }
  }

  var defaultSceneLength: ScreenplaySceneLength {
    switch self {
    case .shortDrama: .compact
    case .shortFilm: .standard
    case .feature: .standard
    }
  }
}

nonisolated enum GuidedScreenplayObligationKind: String, Codable, Hashable, Sendable {
  case structureSelection
  case structureStage
  case sceneDraft
  case screenplayReview
  case authorApproval
}

nonisolated enum GuidedScreenplayObligationStatus: String, Codable, Hashable, Sendable {
  case pending
  case active
  case satisfied
  case blocked
}

nonisolated struct GuidedScreenplayObligation: Identifiable, Hashable, Sendable {
  var id: String
  var kind: GuidedScreenplayObligationKind
  var status: GuidedScreenplayObligationStatus
  var title: String
  var detail: String
  var stageIndex: Int?
  var sceneContractID: UUID?
  var reviewKindRawValue: String?
  var blocker: String?

  var reviewKind: ScreenplayReviewKind? {
    guard let reviewKindRawValue else { return nil }
    return ScreenplayReviewKind(rawValue: reviewKindRawValue)
  }
}

nonisolated struct GuidedScreenplayCompletionSnapshot: Hashable, Sendable {
  var obligations: [GuidedScreenplayObligation]
  var nextObligation: GuidedScreenplayObligation?
  var hardCompleted: Int
  var hardTotal: Int
  var sceneCompleted: Int
  var sceneTotal: Int
  var blockerCount: Int
  var screenplayFingerprint: String
  var isAuthorApproved: Bool

  var fraction: Double {
    guard hardTotal > 0 else { return 0 }
    return min(1, Double(hardCompleted) / Double(hardTotal))
  }

  var isComplete: Bool {
    hardTotal > 0
      && hardCompleted == hardTotal
      && blockerCount == 0
      && isAuthorApproved
  }
}

nonisolated struct GuidedScreenplayPrompt: Hashable, Sendable {
  var obligationID: String
  var eyebrow: String
  var title: String
  var question: String
  var writingDirection: String
  var completionHint: String
  var targetSceneContractID: UUID?
  var actionTitle: String
}

nonisolated enum GuidedScreenplayEchoKind: String, Codable, Hashable, Sendable {
  case character = "人物"
  case plot = "情节"
  case relationship = "关系"
  case image = "可拍画面"
  case voice = "声音"
  case world = "生活与世界"
  case structure = "结构推进"
}

nonisolated struct GuidedScreenplayEchoFinding: Codable, Hashable, Identifiable, Sendable {
  var id: UUID
  var kindRawValue: String
  var title: String
  var effect: String
  var evidence: String

  init(
    id: UUID = UUID(),
    kind: GuidedScreenplayEchoKind,
    title: String,
    effect: String,
    evidence: String
  ) {
    self.id = id
    kindRawValue = kind.rawValue
    self.title = title
    self.effect = effect
    self.evidence = evidence
  }

  var kind: GuidedScreenplayEchoKind {
    GuidedScreenplayEchoKind(rawValue: kindRawValue) ?? .plot
  }
}

nonisolated struct GuidedCompiledMutation: Codable, Hashable, Sendable {
  var dimensionRawValue: String
  var subject: String
  var holder: String
  var beforeValue: String
  var afterValue: String

  var dimension: DramaticStateDimension {
    DramaticStateDimension(rawValue: dimensionRawValue) ?? .world
  }
}

nonisolated struct GuidedCompiledBeat: Codable, Hashable, Identifiable, Sendable {
  var id: UUID
  var purpose: String
  var dramaticAction: String
  var characterAction: String
  var opposition: String
  var turn: String
  var outcome: String
  var screenplayText: String
  var mutations: [GuidedCompiledMutation]
  var audienceUpdate: String

  init(
    id: UUID = UUID(),
    purpose: String,
    dramaticAction: String,
    characterAction: String,
    opposition: String,
    turn: String,
    outcome: String,
    screenplayText: String,
    mutations: [GuidedCompiledMutation],
    audienceUpdate: String
  ) {
    self.id = id
    self.purpose = purpose
    self.dramaticAction = dramaticAction
    self.characterAction = characterAction
    self.opposition = opposition
    self.turn = turn
    self.outcome = outcome
    self.screenplayText = screenplayText
    self.mutations = mutations
    self.audienceUpdate = audienceUpdate
  }
}

nonisolated struct GuidedCompiledCharacter: Codable, Hashable, Identifiable, Sendable {
  var id: UUID
  var name: String
  var roleRawValue: String
  var visibleBehavior: String
  var immediateGoal: String
  var fearOrDefense: String

  init(
    id: UUID = UUID(),
    name: String,
    roleRawValue: String,
    visibleBehavior: String,
    immediateGoal: String,
    fearOrDefense: String
  ) {
    self.id = id
    self.name = name
    self.roleRawValue = roleRawValue
    self.visibleBehavior = visibleBehavior
    self.immediateGoal = immediateGoal
    self.fearOrDefense = fearOrDefense
  }
}

nonisolated struct GuidedSceneCompilationResult: Hashable, Sendable {
  var fountainText: String
  var heading: String
  var pointOfView: String
  var characterGoal: String
  var obstacle: String
  var turn: String
  var outcome: String
  var nextPressure: String
  var stageDecision: String
  var stageCost: String
  var stageEvidence: String
  var beats: [GuidedCompiledBeat]
  var characters: [GuidedCompiledCharacter]
  var echoHeadline: String
  var echoFindings: [GuidedScreenplayEchoFinding]
  var preservedQuotes: [String]
  var knowledgeSources: [String]
}

nonisolated struct GuidedScreenplayCompileEcho: Codable, Hashable, Identifiable, Sendable {
  var id: UUID
  var sceneContractID: UUID
  var headline: String
  var findings: [GuidedScreenplayEchoFinding]
  var preservedQuotes: [String]
  var createdAt: Date

  init(
    id: UUID = UUID(),
    sceneContractID: UUID,
    headline: String,
    findings: [GuidedScreenplayEchoFinding],
    preservedQuotes: [String],
    createdAt: Date = .now
  ) {
    self.id = id
    self.sceneContractID = sceneContractID
    self.headline = headline
    self.findings = findings
    self.preservedQuotes = preservedQuotes
    self.createdAt = createdAt
  }
}

extension Notification.Name {
  static let guidedFlowCommitScreenplay = Notification.Name(
    "StoryMentor.GuidedFlow.CommitScreenplay"
  )
}

@MainActor
extension GuidedFlowSession {
  private static let scriptScaleKey = "guided.screenplay.scale"
  private static let approvalFingerprintKey = "guided.screenplay.approvalFingerprint"
  private static let echoPrefix = "guided.screenplay.echo."

  var guidedScriptScale: GuidedScriptScale {
    get {
      GuidedScriptScale(rawValue: answer(for: Self.scriptScaleKey)) ?? .shortFilm
    }
    set {
      setAnswer(newValue.rawValue, for: Self.scriptScaleKey)
    }
  }

  var guidedApprovalFingerprint: String {
    answer(for: Self.approvalFingerprintKey)
  }

  func approveCompletedScreenplay(fingerprint: String) {
    setAnswer(fingerprint, for: Self.approvalFingerprintKey)
    touch()
  }

  func invalidateCompletedScreenplayApproval() {
    guard !guidedApprovalFingerprint.isEmpty else { return }
    setAnswer("", for: Self.approvalFingerprintKey)
    touch()
  }

  func storeCompileEcho(_ echo: GuidedScreenplayCompileEcho) {
    guard let data = try? JSONEncoder().encode(echo) else { return }
    setAnswer(
      data.base64EncodedString(),
      for: Self.echoPrefix + echo.sceneContractID.uuidString
    )
  }

  func compileEcho(for sceneContractID: UUID) -> GuidedScreenplayCompileEcho? {
    let value = answer(for: Self.echoPrefix + sceneContractID.uuidString)
    guard let data = Data(base64Encoded: value) else { return nil }
    return try? JSONDecoder().decode(GuidedScreenplayCompileEcho.self, from: data)
  }
}
