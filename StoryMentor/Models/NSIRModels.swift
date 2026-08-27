import Foundation

// MARK: - Stable identifiers

typealias CharacterID = UUID
typealias RevisionID = Int
typealias RuleID = UUID
typealias PropositionID = UUID
typealias TransitionID = UUID

/// NSIR is the canonical, text-independent representation of a story.
///
/// Types in this file deliberately have no SwiftUI or SwiftData dependency so
/// the compiler, validators and package serializer can run without the UI or AI.
nonisolated enum NSIRSchema {
    static let currentVersion = 1
}

// MARK: - Epistemic rule system

nonisolated enum RuleClass: String, Codable, CaseIterable, Identifiable, Sendable {
    case l0 = "L0 · 作者锁定命题"
    case l1 = "L1 · 逻辑与连续性"
    case l2 = "L2 · 形式模型条件"
    case l3 = "L3 · 项目类型契约"
    case l4 = "L4 · 经验性启发"
    case l5 = "L5 · 审美假设"

    var id: String { rawValue }

    var isEnforceable: Bool {
        switch self {
        case .l0, .l1, .l3: true
        case .l2, .l4, .l5: false
        }
    }

    var shortLabel: String { String(rawValue.prefix(2)) }
}

nonisolated struct RuleReference: Codable, Hashable, Identifiable, Sendable {
    var id: RuleID
    var title: String
    var ruleClass: RuleClass

    init(id: RuleID = UUID(), title: String, ruleClass: RuleClass) {
        self.id = id
        self.title = title
        self.ruleClass = ruleClass
    }
}

nonisolated struct RuleCard: Codable, Identifiable, Sendable {
    var id: RuleID
    var title: String
    var ruleClass: RuleClass
    var statement: String
    var modelScope: String
    var enabled: Bool
    var weight: Double
    var source: String
    var createdAt: Date

    init(
        id: RuleID = UUID(),
        title: String,
        ruleClass: RuleClass,
        statement: String,
        modelScope: String = "全项目",
        enabled: Bool = true,
        weight: Double = 1,
        source: String = "StoryMentor",
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.ruleClass = ruleClass
        self.statement = statement
        self.modelScope = modelScope
        self.enabled = enabled
        self.weight = min(max(weight, 0), 1)
        self.source = source
        self.createdAt = createdAt
    }
}

// MARK: - Author propositions

nonisolated enum CreativePropositionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case emotion = "情感命题"
    case trauma = "人物创伤"
    case foreshadowing = "性格伏笔"
    case microConflict = "微型冲突"
    case relationship = "关系变化"
    case secretReveal = "秘密与揭示"
    case choiceCost = "选择与代价"
    case imageAction = "画面或动作"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .emotion: "heart.text.square.fill"
        case .trauma: "bandage.fill"
        case .foreshadowing: "eye.trianglebadge.exclamationmark.fill"
        case .microConflict: "bolt.horizontal.fill"
        case .relationship: "person.2.fill"
        case .secretReveal: "lock.open.trianglebadge.exclamationmark"
        case .choiceCost: "arrow.triangle.branch"
        case .imageAction: "photo.on.rectangle.angled"
        }
    }

    var prompt: String {
        switch self {
        case .emotion: "例如：让她嫉妒，但她绝不能承认自己喜欢他。"
        case .trauma: "例如：她小时候被母亲遗弃，这件事今天仍在驱动她。"
        case .foreshadowing: "例如：提前暗示他其实有极强的控制欲，但不能泄底。"
        case .microConflict: "例如：只设计一次很小的摩擦，不升级成争吵。"
        case .relationship: "例如：让两人更亲密，同时让信任下降。"
        case .secretReveal: "例如：观众先知道真相，人物仍相信谎言。"
        case .choiceCost: "例如：逼她在尊严和救下弟弟之间选择。"
        case .imageAction: "例如：他把第二只杯子收进柜子，没有解释。"
        }
    }
}

nonisolated enum PropositionStatus: String, Codable, CaseIterable, Sendable {
    case proposed = "待确认"
    case locked = "作者锁定"
    case superseded = "已被替代"
    case rejected = "未采用"
}

nonisolated struct Proposition: Codable, Identifiable, Sendable {
    var id: PropositionID
    var kind: CreativePropositionKind
    var originalText: String
    var formalStatement: String
    var targetCharacterIDs: [CharacterID]
    var forbiddenOutcomes: [String]
    var lockedFacts: [String]
    var undecidedVariables: [String]
    var status: PropositionStatus
    var createdAt: Date
    var revision: RevisionID

    init(
        id: PropositionID = UUID(),
        kind: CreativePropositionKind,
        originalText: String,
        formalStatement: String = "",
        targetCharacterIDs: [CharacterID] = [],
        forbiddenOutcomes: [String] = [],
        lockedFacts: [String] = [],
        undecidedVariables: [String] = [],
        status: PropositionStatus = .proposed,
        createdAt: Date = .now,
        revision: RevisionID = 0
    ) {
        self.id = id
        self.kind = kind
        self.originalText = originalText
        self.formalStatement = formalStatement.isEmpty ? originalText : formalStatement
        self.targetCharacterIDs = targetCharacterIDs
        self.forbiddenOutcomes = forbiddenOutcomes
        self.lockedFacts = lockedFacts
        self.undecidedVariables = undecidedVariables
        self.status = status
        self.createdAt = createdAt
        self.revision = revision
    }
}

// MARK: - Canonical story state

nonisolated enum NarrativeStateDimension: String, Codable, CaseIterable, Identifiable, Sendable {
    case world = "W · 世界事实"
    case belief = "B · 知识与信念"
    case goal = "G · 目标与策略"
    case relationship = "R · 关系向量"
    case norm = "N · 承诺与规范"
    case affect = "A · 情绪评价条件"
    case identity = "I · 自我认同与防御"
    case resource = "Q · 资源、风险与机会"
    case audience = "U · 观众认知"
    case motif = "M · 伏笔、悬念与意象"

    var id: String { rawValue }
    var code: String { String(rawValue.prefix(1)) }

    var symbol: String {
        switch self {
        case .world: "globe.asia.australia.fill"
        case .belief: "brain.head.profile.fill"
        case .goal: "scope"
        case .relationship: "person.2.fill"
        case .norm: "checkmark.seal.fill"
        case .affect: "waveform.path.ecg"
        case .identity: "person.crop.circle.badge.questionmark"
        case .resource: "gauge.with.dots.needle.33percent"
        case .audience: "eye.fill"
        case .motif: "point.3.filled.connected.trianglepath.dotted"
        }
    }
}

nonisolated enum TruthStatus: String, Codable, CaseIterable, Sendable {
    case fact = "事实"
    case belief = "相信"
    case mistakenBelief = "错误信念"
    case suspicion = "怀疑"
    case expectation = "预期"
    case unknown = "未知"
}

nonisolated struct Belief: Codable, Identifiable, Sendable {
    var id: UUID
    var holderID: CharacterID
    var subject: String
    var value: String
    var truthStatus: TruthStatus
    var learnedAtTransitionID: TransitionID?
    var confidence: Double

    init(
        id: UUID = UUID(),
        holderID: CharacterID,
        subject: String,
        value: String,
        truthStatus: TruthStatus = .belief,
        learnedAtTransitionID: TransitionID? = nil,
        confidence: Double = 1
    ) {
        self.id = id
        self.holderID = holderID
        self.subject = subject
        self.value = value
        self.truthStatus = truthStatus
        self.learnedAtTransitionID = learnedAtTransitionID
        self.confidence = min(max(confidence, 0), 1)
    }
}

nonisolated struct Goal: Codable, Identifiable, Sendable {
    var id: UUID
    var ownerID: CharacterID
    var desiredState: String
    var plan: String
    var currentStrategy: String
    var priority: Double
    var active: Bool

    init(
        id: UUID = UUID(),
        ownerID: CharacterID,
        desiredState: String,
        plan: String = "",
        currentStrategy: String = "",
        priority: Double = 0.5,
        active: Bool = true
    ) {
        self.id = id
        self.ownerID = ownerID
        self.desiredState = desiredState
        self.plan = plan
        self.currentStrategy = currentStrategy
        self.priority = min(max(priority, 0), 1)
        self.active = active
    }
}

nonisolated struct RelationshipState: Codable, Identifiable, Sendable {
    var id: UUID
    var fromID: CharacterID
    var toID: CharacterID
    var trust: Double
    var intimacy: Double
    var power: Double
    var dependency: Double
    var obligation: Double
    var resentment: Double
    var attraction: Double
    var publicStatus: Double

    init(
        id: UUID = UUID(),
        fromID: CharacterID,
        toID: CharacterID,
        trust: Double = 0,
        intimacy: Double = 0,
        power: Double = 0,
        dependency: Double = 0,
        obligation: Double = 0,
        resentment: Double = 0,
        attraction: Double = 0,
        publicStatus: Double = 0
    ) {
        self.id = id
        self.fromID = fromID
        self.toID = toID
        self.trust = Self.unit(trust)
        self.intimacy = Self.unit(intimacy)
        self.power = Self.unit(power)
        self.dependency = Self.unit(dependency)
        self.obligation = Self.unit(obligation)
        self.resentment = Self.unit(resentment)
        self.attraction = Self.unit(attraction)
        self.publicStatus = Self.unit(publicStatus)
    }

    private static func unit(_ value: Double) -> Double { min(max(value, -1), 1) }
}

nonisolated struct NormState: Codable, Identifiable, Sendable {
    var id: UUID
    var subject: String
    var holderID: CharacterID?
    var kind: String
    var statement: String
    var active: Bool
}

nonisolated struct AffectiveAppraisal: Codable, Identifiable, Sendable {
    var id: UUID
    var characterID: CharacterID
    var label: String
    var valuedObject: String
    var threat: String
    var entitlement: String
    var selfReportedMotive: String
    var actualMotive: String
}

nonisolated struct IdentityState: Codable, Identifiable, Sendable {
    var id: UUID
    var characterID: CharacterID
    var selfNarrative: String
    var defense: String
    var threatenedBy: String
}

nonisolated struct ResourceState: Codable, Identifiable, Sendable {
    var id: UUID
    var ownerID: CharacterID?
    var resource: String
    var availability: Double
    var risk: Double
    var deadline: String
}

nonisolated struct AudienceState: Codable, Sendable {
    var knows: [String] = []
    var suspects: [String] = []
    var expects: [String] = []
    var misunderstands: [String] = []
}

nonisolated enum ObligationStatus: String, Codable, CaseIterable, Sendable {
    case open = "未解决"
    case satisfied = "已回收"
    case violated = "已违背"
    case waived = "作者豁免"
}

nonisolated struct Obligation: Codable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var detail: String
    var createdByTransitionID: TransitionID?
    var dueBeforeTransitionID: TransitionID?
    var status: ObligationStatus
    var ruleClass: RuleClass

    init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        createdByTransitionID: TransitionID? = nil,
        dueBeforeTransitionID: TransitionID? = nil,
        status: ObligationStatus = .open,
        ruleClass: RuleClass = .l1
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.createdByTransitionID = createdByTransitionID
        self.dueBeforeTransitionID = dueBeforeTransitionID
        self.status = status
        self.ruleClass = ruleClass
    }
}

nonisolated struct StoryState: Codable, Sendable {
    /// Lossless key/value projection used by the deterministic reducer. Typed
    /// collections below provide richer queries without collapsing dimensions.
    var indexedValues: [String: String] = [:]
    var worldFacts: [String: String] = [:]
    var beliefs: [Belief] = []
    var goals: [Goal] = []
    var relationships: [RelationshipState] = []
    var norms: [NormState] = []
    var appraisals: [AffectiveAppraisal] = []
    var identities: [IdentityState] = []
    var resources: [ResourceState] = []
    var audience = AudienceState()
    var motifStates: [String: String] = [:]
}

// MARK: - Dramatic transitions

nonisolated enum ConditionOperator: String, Codable, CaseIterable, Sendable {
    case equals = "等于"
    case notEquals = "不等于"
    case contains = "包含"
    case exists = "存在"
    case notExists = "不存在"
}

nonisolated struct Condition: Codable, Identifiable, Sendable {
    var id: UUID
    var dimension: NarrativeStateDimension
    var subject: String
    var holderID: CharacterID?
    var operation: ConditionOperator
    var expectedValue: String
}

nonisolated struct Trigger: Codable, Sendable {
    var summary: String
    var sourceTransitionID: TransitionID?
    var externalEvent: Bool
}

nonisolated struct NarrativeTarget: Codable, Sendable {
    var characterID: CharacterID?
    var object: String
}

nonisolated struct Tactic: Codable, Sendable {
    var verb: String
    var method: String
    var concealment: String
}

nonisolated struct StateMutation: Codable, Identifiable, Sendable {
    var id: UUID
    var dimension: NarrativeStateDimension
    var subject: String
    var holderID: CharacterID?
    var beforeValue: String
    var afterValue: String
    var truthStatus: TruthStatus
    var observerIDs: [CharacterID]
    var audienceObserves: Bool

    init(
        id: UUID = UUID(),
        dimension: NarrativeStateDimension,
        subject: String,
        holderID: CharacterID? = nil,
        beforeValue: String,
        afterValue: String,
        truthStatus: TruthStatus = .fact,
        observerIDs: [CharacterID] = [],
        audienceObserves: Bool = true
    ) {
        self.id = id
        self.dimension = dimension
        self.subject = subject
        self.holderID = holderID
        self.beforeValue = beforeValue
        self.afterValue = afterValue
        self.truthStatus = truthStatus
        self.observerIDs = observerIDs
        self.audienceObserves = audienceObserves
    }

    var isEffective: Bool {
        let before = beforeValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let after = afterValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return !after.isEmpty && before.localizedCaseInsensitiveCompare(after) != .orderedSame
    }
}

nonisolated struct Consequence: Codable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var detail: String
    var severity: Double

    init(id: UUID = UUID(), title: String, detail: String, severity: Double = 0.5) {
        self.id = id
        self.title = title
        self.detail = detail
        self.severity = min(max(severity, 0), 1)
    }
}

nonisolated enum DramaticFunction: String, Codable, CaseIterable, Sendable {
    case setup = "建立"
    case escalation = "升级"
    case reveal = "揭示"
    case reversal = "反转"
    case choice = "选择"
    case payoff = "回收"
    case concealment = "掩饰"
    case recognition = "认知"
}

nonisolated struct VisibilityMap: Codable, Sendable {
    var observerIDs: [CharacterID]
    var audienceObserves: Bool
    var concealedFromIDs: [CharacterID]

    static let audienceOnly = VisibilityMap(
        observerIDs: [],
        audienceObserves: true,
        concealedFromIDs: []
    )
}

nonisolated struct Provenance: Codable, Sendable {
    var source: String
    var model: String
    var sourcePropositionIDs: [PropositionID]
    var generatedAt: Date
}

nonisolated struct AnalysisConfidence: Codable, Sendable {
    var value: Double
    var basis: String
    var disputed: Bool

    init(value: Double, basis: String, disputed: Bool = false) {
        self.value = min(max(value, 0), 1)
        self.basis = basis
        self.disputed = disputed
    }
}

nonisolated struct DramaticTransition: Codable, Identifiable, Sendable {
    var id: TransitionID
    var title: String
    var preconditions: [Condition]
    var trigger: Trigger?
    var actor: CharacterID?
    var actorName: String
    var target: NarrativeTarget?
    var intention: String
    var tactic: Tactic
    var resistance: [String]
    var effects: [StateMutation]
    var visibility: VisibilityMap
    var cost: [Consequence]
    var dramaticFunctions: Set<DramaticFunction>
    var partialOrderPredecessorIDs: [TransitionID]
    var provenance: Provenance
    var confidence: AnalysisConfidence

    init(
        id: TransitionID = UUID(),
        title: String,
        preconditions: [Condition] = [],
        trigger: Trigger? = nil,
        actor: CharacterID? = nil,
        actorName: String = "",
        target: NarrativeTarget? = nil,
        intention: String,
        tactic: Tactic,
        resistance: [String] = [],
        effects: [StateMutation],
        visibility: VisibilityMap = .audienceOnly,
        cost: [Consequence] = [],
        dramaticFunctions: Set<DramaticFunction> = [],
        partialOrderPredecessorIDs: [TransitionID] = [],
        provenance: Provenance,
        confidence: AnalysisConfidence
    ) {
        self.id = id
        self.title = title
        self.preconditions = preconditions
        self.trigger = trigger
        self.actor = actor
        self.actorName = actorName
        self.target = target
        self.intention = intention
        self.tactic = tactic
        self.resistance = resistance
        self.effects = effects
        self.visibility = visibility
        self.cost = cost
        self.dramaticFunctions = dramaticFunctions
        self.partialOrderPredecessorIDs = partialOrderPredecessorIDs
        self.provenance = provenance
        self.confidence = confidence
    }

    var isEffective: Bool { effects.contains(where: \.isEffective) }
}

// MARK: - Explainable recommendations and patches

nonisolated struct PremiseReference: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var propositionID: PropositionID?
    var statement: String
}

nonisolated struct Assumption: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var statement: String
    var authorConfirmed: Bool
}

nonisolated struct EvidenceReference: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var label: String
    var sourceID: String
    var excerpt: String
}

nonisolated enum NarrativeIssueKind: String, Codable, CaseIterable, Sendable {
    case authorConstraint = "作者命题冲突"
    case continuity = "时间与世界连续性"
    case knowledgeLeak = "知识泄漏"
    case causalGap = "因果缺口"
    case unresolvedSetup = "未回收设置"
    case semanticDrift = "语义漂移"
    case assumption = "AI 假设"
    case incompleteModel = "形式模型不完整"
}

nonisolated enum IssueSeverity: String, Codable, CaseIterable, Sendable {
    case error = "错误"
    case warning = "警告"
    case decision = "待作者决定"
    case note = "提示"
}

nonisolated struct NarrativeIssue: Codable, Identifiable, Sendable {
    var id: UUID
    var kind: NarrativeIssueKind
    var severity: IssueSeverity
    var title: String
    var detail: String
    var ruleClass: RuleClass
    var evidence: [EvidenceReference]
    var transitionID: TransitionID?
}

nonisolated struct StateDiff: Codable, Sendable {
    var mutations: [StateMutation]
    var introducedObligations: [Obligation]
    var resolvedObligationIDs: [UUID]
    var screenplayPreview: String

    static let empty = StateDiff(
        mutations: [],
        introducedObligations: [],
        resolvedObligationIDs: [],
        screenplayPreview: ""
    )
}

nonisolated struct Alternative: Codable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var difference: String
}

nonisolated struct Tradeoff: Codable, Identifiable, Sendable {
    var id: UUID
    var gains: String
    var costs: String
}

nonisolated struct UncertaintyReport: Codable, Sendable {
    var confidence: Double
    var unresolvedVariables: [String]
    var modelDependentClaims: [String]
}

nonisolated enum StoryOperation: Codable, Identifiable, Sendable {
    case addProposition(Proposition)
    case addTransition(DramaticTransition)
    case addObligation(Obligation)
    case resolveObligation(UUID)
    case updateState([StateMutation])
    case stageScreenplayText(String)

    var id: UUID {
        switch self {
        case .addProposition(let value): value.id
        case .addTransition(let value): value.id
        case .addObligation(let value): value.id
        case .resolveObligation(let id): id
        case .updateState(let values): values.first?.id ?? UUID()
        case .stageScreenplayText: UUID()
        }
    }
}

nonisolated struct StoryPatch: Codable, Identifiable, Sendable {
    var id: UUID
    var baseRevision: RevisionID
    var title: String
    var operations: [StoryOperation]
    var createdAt: Date
    var generatedBy: ModelExecutionRecord
}

nonisolated struct ModelExecutionRecord: Codable, Sendable {
    var provider: String
    var model: String
    var profile: String
    var contextSummary: String
    var createdAt: Date
}

nonisolated struct ValidationReport: Codable, Sendable {
    var valid: Bool
    var checkedRevision: RevisionID
    var issues: [NarrativeIssue]
    var stateDiff: StateDiff
    var checkedRuleIDs: [RuleID]
    var generatedAt: Date

    static func empty(revision: RevisionID) -> ValidationReport {
        ValidationReport(
            valid: true,
            checkedRevision: revision,
            issues: [],
            stateDiff: .empty,
            checkedRuleIDs: [],
            generatedAt: .now
        )
    }
}

nonisolated struct RecommendationTrace: Codable, Identifiable, Sendable {
    var id: UUID
    var conclusion: String
    var ruleClass: RuleClass
    var appliedRules: [RuleReference]
    var acceptedPremises: [PremiseReference]
    var assumptions: [Assumption]
    var evidence: [EvidenceReference]
    var counterEvidence: [EvidenceReference]
    var detectedProblem: NarrativeIssue?
    var proposedPatchID: UUID
    var resultingStateDiff: StateDiff
    var alternatives: [Alternative]
    var tradeoffs: [Tradeoff]
    var uncertainty: UncertaintyReport
    var requiresAuthorDecision: Bool
}

/// Multi-objective vector. It intentionally has no aggregate score.
nonisolated struct NarrativeObjectiveVector: Codable, Sendable {
    var coherence: Double
    var causality: Double
    var epistemicLegality: Double
    var emotionalCoverage: Double
    var economy: Double
    var genreFit: Double
    var novelty: Double
    var userPreference: Double

    var dimensions: [(String, Double)] {
        [
            ("因果", causality),
            ("知识合法", epistemicLegality),
            ("情感覆盖", emotionalCoverage),
            ("经济性", economy),
            ("类型契约", genreFit),
            ("意外性", novelty)
        ]
    }

    func dominates(_ other: Self) -> Bool {
        let lhs = [coherence, causality, epistemicLegality, emotionalCoverage,
                   economy, genreFit, novelty, userPreference]
        let rhs = [other.coherence, other.causality, other.epistemicLegality,
                   other.emotionalCoverage, other.economy, other.genreFit,
                   other.novelty, other.userPreference]
        return zip(lhs, rhs).allSatisfy { $0 >= $1 }
            && zip(lhs, rhs).contains { $0 > $1 }
    }
}

nonisolated struct CompilerCandidate: Codable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var thesis: String
    var transitions: [DramaticTransition]
    var patch: StoryPatch
    var trace: RecommendationTrace
    var objectives: NarrativeObjectiveVector
    var actionSkeleton: String
}

nonisolated struct InformationGainQuestion: Codable, Identifiable, Sendable {
    var id: UUID
    var prompt: String
    var rationale: String
    var variable: String
    var options: [String]
    var expectedInformationGain: Double
}

nonisolated struct PreferenceComparison: Codable, Identifiable, Sendable {
    var id: UUID
    var preferredCandidateID: UUID
    var rejectedCandidateID: UUID
    var projectSpecific: Bool
    var createdAt: Date
}

nonisolated struct SemanticSourceMap: Codable, Identifiable, Sendable {
    var id: UUID
    var utf16Location: Int
    var utf16Length: Int
    var transitionIDs: [TransitionID]
    var realizationRole: String
    var alignmentConfidence: Double
    var sourceFingerprint: String
}

/// Minimal, auditable payload assembled for one model task. It is a temporary
/// work area, never story memory, and excludes unrelated screenplay text.
nonisolated struct ContextSlice: Codable, Identifiable, Sendable {
    var id: UUID
    var task: String
    var propositionIDs: [PropositionID]
    var relatedCharacterIDs: [CharacterID]
    var relatedTransitionIDs: [TransitionID]
    var openObligationIDs: [UUID]
    var ruleIDs: [RuleID]
    var projectExcerpt: String
    var untrustedSourceExcerpts: [String]
    var createdAt: Date

    var auditSummary: String {
        "命题 \(propositionIDs.count) · 人物 \(relatedCharacterIDs.count) · 转移 \(relatedTransitionIDs.count) · 规则 \(ruleIDs.count)"
    }
}

// MARK: - Canonical workspace document

nonisolated struct CompilerWorkspaceDocument: Codable, Sendable {
    var schemaVersion: Int
    var revision: RevisionID
    var projectID: UUID
    var propositions: [Proposition]
    var state: StoryState
    var transitions: [DramaticTransition]
    var rules: [RuleCard]
    var obligations: [Obligation]
    var stagedPatches: [StoryPatch]
    var recommendationTraces: [RecommendationTrace]
    var validationHistory: [ValidationReport]
    var preferenceComparisons: [PreferenceComparison]
    var sourceMaps: [SemanticSourceMap]
    var updatedAt: Date

    static func empty(projectID: UUID) -> Self {
        CompilerWorkspaceDocument(
            schemaVersion: NSIRSchema.currentVersion,
            revision: 0,
            projectID: projectID,
            propositions: [],
            state: StoryState(),
            transitions: [],
            rules: RuleCard.builtInRules,
            obligations: [],
            stagedPatches: [],
            recommendationTraces: [],
            validationHistory: [],
            preferenceComparisons: [],
            sourceMaps: [],
            updatedAt: .now
        )
    }
}

nonisolated extension RuleCard {
    static let builtInRules: [RuleCard] = [
        RuleCard(
            title: "作者公理不可改写",
            ruleClass: .l0,
            statement: "任何 Patch 都不得删除、反转或静默弱化作者锁定命题。"
        ),
        RuleCard(
            title: "知识来源合法",
            ruleClass: .l1,
            statement: "人物只能使用其亲历、获知或可合理推断的信息。"
        ),
        RuleCard(
            title: "有效状态转移",
            ruleClass: .l1,
            statement: "每个 DramaticTransition 至少产生一项有效 before → after 差异。"
        ),
        RuleCard(
            title: "先建立后回收",
            ruleClass: .l1,
            statement: "回收、背叛与反转必须分别存在可追溯的线索、承诺或旧解释。"
        ),
        RuleCard(
            title: "情感评价结构",
            ruleClass: .l2,
            statement: "情绪标签应展开为珍视对象、威胁、归责、资格与行动倾向。"
        ),
        RuleCard(
            title: "候选结构差异",
            ruleClass: .l4,
            statement: "候选应改变策略或状态轨迹，而不只是替换名词和措辞。"
        ),
        RuleCard(
            title: "审美只供裁决",
            ruleClass: .l5,
            statement: "克制、激烈、诗意等判断只能作为选项，不得冒充逻辑结论。"
        )
    ]
}
