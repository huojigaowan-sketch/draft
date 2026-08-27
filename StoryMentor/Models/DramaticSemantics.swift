import Foundation
import SwiftData

/// The six dimensions that make up the screenplay's dynamic context.
///
/// A dramatic update is valid when at least one of these dimensions changes.
/// Emotion and pacing are measured as consequences of these changes instead
/// of becoming a seventh source of truth.
nonisolated enum DramaticStateDimension: String, CaseIterable, Codable, Identifiable, Sendable {
    case world = "世界事实"
    case knowledge = "认知与信念"
    case goal = "目标与策略"
    case relationship = "关系与权力"
    case norm = "承诺与规范"
    case audience = "观众认知"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .world: "globe.asia.australia.fill"
        case .knowledge: "brain.head.profile.fill"
        case .goal: "scope"
        case .relationship: "person.2.fill"
        case .norm: "checkmark.seal.fill"
        case .audience: "eye.fill"
        }
    }
}

nonisolated enum DramaticCarrier: String, CaseIterable, Codable, Identifiable, Sendable {
    case dialogue = "对白"
    case action = "动作"
    case silence = "沉默"
    case perception = "感知"
    case revelation = "揭示"
    case sound = "声音"
    case spatial = "空间关系"
    case event = "事件"

    var id: String { rawValue }
}

nonisolated enum DramaticUpdateOrigin: String, Codable, Sendable {
    case planned = "结构计划"
    case extracted = "正文提取"
    case authored = "作者确认"
}

nonisolated enum DramaticUpdateStatus: String, Codable, Sendable {
    case candidate = "候选"
    case analyzed = "已分析"
    case confirmed = "已确认"
    case locked = "作者锁定"
    case stale = "正文已变化"
}

nonisolated enum DramaticTruthStatus: String, CaseIterable, Codable, Sendable {
    case fact = "事实"
    case belief = "人物相信"
    case mistakenBelief = "错误信念"
    case suspicion = "怀疑"
    case expectation = "预期"
}

nonisolated struct DramaticStateMutation: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var dimensionRawValue: String
    var subject: String
    var holder: String
    var beforeValue: String
    var afterValue: String
    var truthStatusRawValue: String
    var observerNames: [String]

    init(
        id: UUID = UUID(),
        dimension: DramaticStateDimension,
        subject: String,
        holder: String = "",
        beforeValue: String,
        afterValue: String,
        truthStatus: DramaticTruthStatus = .fact,
        observerNames: [String] = []
    ) {
        self.id = id
        dimensionRawValue = dimension.rawValue
        self.subject = subject
        self.holder = holder
        self.beforeValue = beforeValue
        self.afterValue = afterValue
        truthStatusRawValue = truthStatus.rawValue
        self.observerNames = observerNames
    }

    var dimension: DramaticStateDimension {
        get { DramaticStateDimension(rawValue: dimensionRawValue) ?? .world }
        set { dimensionRawValue = newValue.rawValue }
    }

    var truthStatus: DramaticTruthStatus {
        get { DramaticTruthStatus(rawValue: truthStatusRawValue) ?? .fact }
        set { truthStatusRawValue = newValue.rawValue }
    }

    var stateKey: String {
        [dimensionRawValue, holder, subject]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "|")
    }

    var isEffective: Bool {
        let before = beforeValue.semanticNormalized
        let after = afterValue.semanticNormalized
        return !after.isEmpty && before != after
    }
}

/// An external anchor into Fountain source. Semantic metadata never enters the
/// screenplay text itself, so import/export stays byte-for-byte clean.
nonisolated struct DramaticSourceAnchor: Codable, Hashable, Sendable {
    var sceneRecordID: UUID?
    var sceneContractID: UUID?
    var localUTF16Location: Int
    var localUTF16Length: Int
    var startParagraph: Int
    var endParagraph: Int
    var quotedText: String
    var leadingContext: String
    var trailingContext: String
    var sourceFingerprint: String

    static let empty = DramaticSourceAnchor(
        sceneRecordID: nil,
        sceneContractID: nil,
        localUTF16Location: 0,
        localUTF16Length: 0,
        startParagraph: 0,
        endParagraph: 0,
        quotedText: "",
        leadingContext: "",
        trailingContext: "",
        sourceFingerprint: ""
    )
}

/// A scene's top-down obligation expressed in the same language used to read
/// the finished screenplay bottom-up. This makes structure a constraint on
/// state change, not a request for a particular sentence or bit of blocking.
nonisolated struct SceneStateContract: Codable, Hashable, Sendable {
    var entrySnapshot: String
    var requiredChanges: [DramaticStateMutation]
    var forbiddenChanges: [String]
    var audienceOutcome: String
    var exitSnapshot: String
    var verificationRule: String

    static let empty = SceneStateContract(
        entrySnapshot: "",
        requiredChanges: [],
        forbiddenChanges: [],
        audienceOutcome: "",
        exitSnapshot: "",
        verificationRule: ""
    )

    var isEmpty: Bool {
        entrySnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && requiredChanges.isEmpty
            && forbiddenChanges.isEmpty
            && audienceOutcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && exitSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@Model
final class DramaticUpdateRecord {
    @Attribute(.unique) var id: UUID
    var sceneRecordID: UUID?
    var sceneContractID: UUID?
    var structureStageIndex: Int?
    var sceneIndex: Int?
    var ordinal: Int
    var carrierRawValue: String
    var actionVerb: String
    var summary: String
    var actor: String
    var target: String
    var intention: String
    var resistance: String
    var outcome: String
    var mutationsData: Data
    var sourceAnchorData: Data
    var causalParentIDsData: Data
    var originRawValue: String
    var statusRawValue: String
    var confidence: Double
    var salience: Double
    var irreversibility: Double
    var sourceRevision: String
    var analysisModel: String
    var createdAt: Date
    var updatedAt: Date
    var project: StoryProject?

    init(
        id: UUID = UUID(),
        sceneRecordID: UUID? = nil,
        sceneContractID: UUID? = nil,
        structureStageIndex: Int? = nil,
        sceneIndex: Int? = nil,
        ordinal: Int,
        carrier: DramaticCarrier,
        actionVerb: String,
        summary: String,
        actor: String = "",
        target: String = "",
        intention: String = "",
        resistance: String = "",
        outcome: String = "",
        mutations: [DramaticStateMutation],
        sourceAnchor: DramaticSourceAnchor = .empty,
        causalParentIDs: [UUID] = [],
        origin: DramaticUpdateOrigin = .extracted,
        status: DramaticUpdateStatus = .analyzed,
        confidence: Double = 0.75,
        salience: Double = 0.5,
        irreversibility: Double = 0.5,
        sourceRevision: String,
        analysisModel: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.sceneRecordID = sceneRecordID
        self.sceneContractID = sceneContractID
        self.structureStageIndex = structureStageIndex
        self.sceneIndex = sceneIndex
        self.ordinal = ordinal
        carrierRawValue = carrier.rawValue
        self.actionVerb = actionVerb
        self.summary = summary
        self.actor = actor
        self.target = target
        self.intention = intention
        self.resistance = resistance
        self.outcome = outcome
        mutationsData = PersistentPayloadCodec.encode(
            mutations,
            preserving: Data(),
            label: "DramaticUpdateRecord.mutations"
        )
        sourceAnchorData = PersistentPayloadCodec.encode(
            sourceAnchor,
            preserving: Data(),
            label: "DramaticUpdateRecord.sourceAnchor"
        )
        causalParentIDsData = PersistentPayloadCodec.encode(
            causalParentIDs,
            preserving: Data(),
            label: "DramaticUpdateRecord.causalParentIDs"
        )
        originRawValue = origin.rawValue
        statusRawValue = status.rawValue
        self.confidence = min(max(confidence, 0), 1)
        self.salience = min(max(salience, 0), 1)
        self.irreversibility = min(max(irreversibility, 0), 1)
        self.sourceRevision = sourceRevision
        self.analysisModel = analysisModel
        self.createdAt = createdAt
        updatedAt = createdAt
    }

    var carrier: DramaticCarrier {
        get { DramaticCarrier(rawValue: carrierRawValue) ?? .event }
        set { carrierRawValue = newValue.rawValue }
    }

    var origin: DramaticUpdateOrigin {
        get { DramaticUpdateOrigin(rawValue: originRawValue) ?? .extracted }
        set { originRawValue = newValue.rawValue }
    }

    var status: DramaticUpdateStatus {
        get { DramaticUpdateStatus(rawValue: statusRawValue) ?? .candidate }
        set { statusRawValue = newValue.rawValue }
    }

    var mutations: [DramaticStateMutation] {
        get {
            PersistentPayloadCodec.decode(
                [DramaticStateMutation].self,
                from: mutationsData,
                default: [],
                label: "DramaticUpdateRecord.mutations"
            )
        }
        set {
            mutationsData = PersistentPayloadCodec.encode(
                newValue,
                preserving: mutationsData,
                label: "DramaticUpdateRecord.mutations"
            )
            updatedAt = .now
        }
    }

    var sourceAnchor: DramaticSourceAnchor {
        get {
            PersistentPayloadCodec.decode(
                DramaticSourceAnchor.self,
                from: sourceAnchorData,
                default: .empty,
                label: "DramaticUpdateRecord.sourceAnchor"
            )
        }
        set {
            sourceAnchorData = PersistentPayloadCodec.encode(
                newValue,
                preserving: sourceAnchorData,
                label: "DramaticUpdateRecord.sourceAnchor"
            )
            sceneRecordID = newValue.sceneRecordID
            sceneContractID = newValue.sceneContractID
            updatedAt = .now
        }
    }

    var causalParentIDs: [UUID] {
        get {
            PersistentPayloadCodec.decode(
                [UUID].self,
                from: causalParentIDsData,
                default: [],
                label: "DramaticUpdateRecord.causalParentIDs"
            )
        }
        set {
            causalParentIDsData = PersistentPayloadCodec.encode(
                newValue,
                preserving: causalParentIDsData,
                label: "DramaticUpdateRecord.causalParentIDs"
            )
            updatedAt = .now
        }
    }

    var isEffective: Bool {
        mutations.contains(where: \.isEffective)
    }

    /// Transparent, deterministic impact used by pacing. The language model
    /// proposes the inputs; it never gets to invent the final pace number.
    var effectiveImpact: Double {
        guard isEffective else { return 0 }
        let breadth = min(Double(Set(mutations.map(\.dimensionRawValue)).count) / 3, 1)
        let informationAsymmetry = mutations.contains { $0.dimension == .audience } ? 0.18 : 0
        return min(
            1,
            (0.38 * salience)
                + (0.26 * irreversibility)
                + (0.16 * confidence)
                + (0.20 * breadth)
                + informationAsymmetry
        )
    }
}

nonisolated enum NarrativeProjectionScope: String, Codable, CaseIterable, Sendable {
    case scene = "场景"
    case stage = "大节拍"
    case project = "全片"
    case character = "人物"
    case relationship = "关系"
    case world = "世界"
    case theme = "主题"
    case conflict = "冲突"
}

nonisolated enum NarrativeProjectionStatus: String, Codable, Sendable {
    case current = "最新"
    case stale = "待重算"
    case proposed = "待作者确认"
    case accepted = "作者已确认"
}

nonisolated struct SemanticPacingMetrics: Codable, Hashable, Sendable {
    var durationSeconds: Double
    var updateCount: Int
    var effectiveUpdateCount: Int
    var updateDensity: Double
    var averageImpact: Double
    var resistanceIntensity: Double
    var irreversibility: Double
    var audienceInformationRate: Double

    static let empty = SemanticPacingMetrics(
        durationSeconds: 0,
        updateCount: 0,
        effectiveUpdateCount: 0,
        updateDensity: 0,
        averageImpact: 0,
        resistanceIntensity: 0,
        irreversibility: 0,
        audienceInformationRate: 0
    )
}

@Model
final class NarrativeProjectionRecord {
    @Attribute(.unique) var id: UUID
    var scopeRawValue: String
    var scopeKey: String
    var title: String
    var summary: String
    var entryState: String
    var exitState: String
    var intentSummary: String
    var realizationGap: String
    var evidenceIDsData: Data
    var metricsData: Data
    var sourceRevision: String
    var statusRawValue: String
    var createdAt: Date
    var updatedAt: Date
    var project: StoryProject?

    init(
        id: UUID = UUID(),
        scope: NarrativeProjectionScope,
        scopeKey: String,
        title: String,
        summary: String,
        entryState: String = "",
        exitState: String = "",
        intentSummary: String = "",
        realizationGap: String = "",
        evidenceIDs: [UUID] = [],
        metrics: SemanticPacingMetrics = .empty,
        sourceRevision: String,
        status: NarrativeProjectionStatus = .current,
        createdAt: Date = .now
    ) {
        self.id = id
        scopeRawValue = scope.rawValue
        self.scopeKey = scopeKey
        self.title = title
        self.summary = summary
        self.entryState = entryState
        self.exitState = exitState
        self.intentSummary = intentSummary
        self.realizationGap = realizationGap
        evidenceIDsData = PersistentPayloadCodec.encode(
            evidenceIDs,
            preserving: Data(),
            label: "NarrativeProjectionRecord.evidenceIDs"
        )
        metricsData = PersistentPayloadCodec.encode(
            metrics,
            preserving: Data(),
            label: "NarrativeProjectionRecord.metrics"
        )
        self.sourceRevision = sourceRevision
        statusRawValue = status.rawValue
        self.createdAt = createdAt
        updatedAt = createdAt
    }

    var scope: NarrativeProjectionScope {
        get { NarrativeProjectionScope(rawValue: scopeRawValue) ?? .scene }
        set { scopeRawValue = newValue.rawValue }
    }

    var status: NarrativeProjectionStatus {
        get { NarrativeProjectionStatus(rawValue: statusRawValue) ?? .current }
        set { statusRawValue = newValue.rawValue }
    }

    var evidenceIDs: [UUID] {
        get {
            PersistentPayloadCodec.decode(
                [UUID].self,
                from: evidenceIDsData,
                default: [],
                label: "NarrativeProjectionRecord.evidenceIDs"
            )
        }
        set {
            evidenceIDsData = PersistentPayloadCodec.encode(
                newValue,
                preserving: evidenceIDsData,
                label: "NarrativeProjectionRecord.evidenceIDs"
            )
        }
    }

    var metrics: SemanticPacingMetrics {
        get {
            PersistentPayloadCodec.decode(
                SemanticPacingMetrics.self,
                from: metricsData,
                default: .empty,
                label: "NarrativeProjectionRecord.metrics"
            )
        }
        set {
            metricsData = PersistentPayloadCodec.encode(
                newValue,
                preserving: metricsData,
                label: "NarrativeProjectionRecord.metrics"
            )
        }
    }
}

extension String {
    fileprivate nonisolated var semanticNormalized: String {
        folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        .components(separatedBy: .whitespacesAndNewlines)
        .joined()
        .trimmingCharacters(in: CharacterSet(charactersIn: "，。！？；：,.!?;:\"'“”‘’"))
    }
}

@MainActor
extension StoryProject {
    /// Shared invariant injected into generative layers. The first block is
    /// theoretical law; the second is read-only evidence from screenplay.
    var dramaticSemanticFoundationPrompt: String {
        let evidence = narrativeProjections
            .filter { $0.status != .stale }
            .sorted { lhs, rhs in
                if lhs.scope.rawValue == rhs.scope.rawValue {
                    return lhs.scopeKey < rhs.scopeKey
                }
                return lhs.scope.rawValue < rhs.scope.rawValue
            }
            .prefix(18)
            .map { "【\($0.scope.rawValue)·\($0.title)】\n\($0.summary)" }
            .joined(separator: "\n")

        return """
        【全项目底层公理 · 不得降级】
        剧本的最小功能单位是一次不可再分的情境更新，而不是字、词、句、段、镜头或固定数量的小节拍。
        有效更新必须使 W世界事实、K人物认知/信念、G目标/策略、R关系/权力、D承诺/规范、
        E观众认知至少一项产生可说明的 before → after 差异。人物认知与观众认知必须分开；
        情绪、动作数量和篇幅只是结果或载体，不能冒充状态变化。节奏只按有效更新影响总量 ÷ 时间计算。
        固定结构向下提供必须实现与不得提前发生的状态契约；正文向上提供唯一实现证据。
        正文归纳只能作为提案，绝不能覆盖作者锁定的一句话、人物、主题、世界、冲突或结构。

        【当前正文反向证据】
        \(evidence.isEmpty ? "尚未分析正文；只能依据计划，不得声称已经实现。" : evidence)
        """
    }
}
