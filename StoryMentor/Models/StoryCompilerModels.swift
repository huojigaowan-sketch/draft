import Foundation
import SwiftData

enum AuthorIdeaStatus: String, Codable, CaseIterable {
    case inbox = "灵感盒"
    case analyzing = "分析中"
    case proposed = "待确认"
    case active = "已纳入"
    case paused = "已暂停"
    case rejected = "未采用"
}

@Model
final class AuthorIdeaRecord {
    @Attribute(.unique) var id: UUID
    var originalText: String
    var protectedCore: String
    var scopeRawValue: String
    var statusRawValue: String
    var targetStageIndex: Int?
    var impactSummary: String
    var affectedAreasText: String
    var preservedElementsText: String
    var risksText: String
    var proposedActionsText: String
    var captainInterpretation: String = ""
    var captainOptionsData: Data = Data()
    var selectedCaptainOptionID: UUID?
    var executionIdeaID: UUID?
    @Transient var impactAnalysisRequestToken: UUID?
    var createdAt: Date
    var updatedAt: Date
    var appliedAt: Date?
    var project: StoryProject?

    init(
        id: UUID = UUID(),
        originalText: String,
        protectedCore: String = "",
        scope: CreativeIdeaScope,
        status: AuthorIdeaStatus,
        targetStageIndex: Int? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.originalText = originalText
        self.protectedCore = protectedCore
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ? originalText : protectedCore
        scopeRawValue = scope.rawValue
        statusRawValue = status.rawValue
        self.targetStageIndex = targetStageIndex
        impactSummary = ""
        affectedAreasText = ""
        preservedElementsText = ""
        risksText = ""
        proposedActionsText = ""
        captainInterpretation = ""
        captainOptionsData = Data()
        selectedCaptainOptionID = nil
        executionIdeaID = nil
        self.createdAt = createdAt
        updatedAt = createdAt
    }

    var scope: CreativeIdeaScope {
        get { CreativeIdeaScope(rawValue: scopeRawValue) ?? .inbox }
        set { scopeRawValue = newValue.rawValue }
    }

    var status: AuthorIdeaStatus {
        get { AuthorIdeaStatus(rawValue: statusRawValue) ?? .inbox }
        set { statusRawValue = newValue.rawValue }
    }

    var affectedAreas: [String] {
        get { affectedAreasText.nonemptyLines }
        set { affectedAreasText = newValue.joined(separator: "\n") }
    }

    var preservedElements: [String] {
        get { preservedElementsText.nonemptyLines }
        set { preservedElementsText = newValue.joined(separator: "\n") }
    }

    var risks: [String] {
        get { risksText.nonemptyLines }
        set { risksText = newValue.joined(separator: "\n") }
    }

    var proposedActions: [String] {
        get { proposedActionsText.nonemptyLines }
        set { proposedActionsText = newValue.joined(separator: "\n") }
    }

    var captainOptions: [CaptainCommandOption] {
        get {
            PersistentPayloadCodec.decode(
                [CaptainCommandOption].self,
                from: captainOptionsData,
                default: [],
                label: "AuthorIdeaRecord.captainOptions"
            )
        }
        set {
            captainOptionsData = PersistentPayloadCodec.encode(
                newValue,
                preserving: captainOptionsData,
                label: "AuthorIdeaRecord.captainOptions"
            )
            updatedAt = .now
        }
    }

    var selectedCaptainOption: CaptainCommandOption? {
        guard let selectedCaptainOptionID else { return nil }
        return captainOptions.first { $0.id == selectedCaptainOptionID }
    }
}

nonisolated enum CaptainStoryArea: String, CaseIterable, Codable, Identifiable {
    case premise = "故事前提"
    case characters = "人物"
    case relationships = "人物关系"
    case world = "世界"
    case theme = "主题"
    case conflict = "核心冲突"
    case structure = "固定结构"
    case scenes = "场景"
    case screenplay = "剧本"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .premise: "sparkles"
        case .characters: "person.2.fill"
        case .relationships: "point.3.connected.trianglepath.dotted"
        case .world: "globe.asia.australia.fill"
        case .theme: "scope"
        case .conflict: "bolt.horizontal.fill"
        case .structure: "square.grid.3x3.fill"
        case .scenes: "rectangle.stack.fill"
        case .screenplay: "text.book.closed.fill"
        }
    }

    @MainActor
    var moduleKind: ProjectModuleKind {
        switch self {
        case .premise: .inspiration
        case .characters: .character
        case .relationships: .relationship
        case .world: .world
        case .theme: .theme
        case .conflict: .storyPath
        case .structure: .structure
        case .scenes: .scene
        case .screenplay: .screenplay
        }
    }
}

nonisolated struct CaptainAreaChange: Codable, Hashable, Identifiable {
    var area: CaptainStoryArea
    var affected: Bool
    var target: String
    var update: String
    var consequence: String

    var id: String { area.rawValue }
}

nonisolated struct CaptainCommandOption: Codable, Hashable, Identifiable {
    var id: UUID
    var title: String
    var strategy: String
    var protectedCore: String
    var changes: [CaptainAreaChange]
    var preservedFacts: [String]
    var continuityRisks: [String]

    init(
        id: UUID = UUID(),
        title: String,
        strategy: String,
        protectedCore: String,
        changes: [CaptainAreaChange],
        preservedFacts: [String],
        continuityRisks: [String]
    ) {
        self.id = id
        self.title = title
        self.strategy = strategy
        self.protectedCore = protectedCore
        self.changes = changes
        self.preservedFacts = preservedFacts
        self.continuityRisks = continuityRisks
    }

    var affectedChanges: [CaptainAreaChange] {
        changes.filter {
            $0.affected
                && !$0.update.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

nonisolated struct CaptainCommandResult {
    var interpretation: String
    var options: [CaptainCommandOption]
}

nonisolated struct SceneChoiceOption: Codable, Hashable, Identifiable {
    var id: UUID
    var title: String
    var approach: String
    var heading: String
    var pointOfView: String
    var characterGoal: String
    var obstacle: String
    var turn: String
    var outcome: String
    var nextPressure: String
    /// Optional for backward compatibility with projects created before the
    /// dramatic-state compiler was introduced.
    var requiredStateChanges: [DramaticStateMutation]?
    var audienceUpdate: String?
    var forbiddenChanges: [String]?

    init(
        id: UUID = UUID(),
        title: String,
        approach: String,
        heading: String,
        pointOfView: String,
        characterGoal: String,
        obstacle: String,
        turn: String,
        outcome: String,
        nextPressure: String,
        requiredStateChanges: [DramaticStateMutation]? = nil,
        audienceUpdate: String? = nil,
        forbiddenChanges: [String]? = nil
    ) {
        self.id = id
        self.title = title
        self.approach = approach
        self.heading = heading
        self.pointOfView = pointOfView
        self.characterGoal = characterGoal
        self.obstacle = obstacle
        self.turn = turn
        self.outcome = outcome
        self.nextPressure = nextPressure
        self.requiredStateChanges = requiredStateChanges
        self.audienceUpdate = audienceUpdate
        self.forbiddenChanges = forbiddenChanges
    }
}

nonisolated struct SceneBeatChoiceOption: Codable, Hashable, Identifiable {
    var id: UUID
    var title: String
    var dramaticAction: String
    var characterAction: String
    var opposition: String
    var turn: String
    var outcome: String
    var screenplayText: String
    var stateChanges: [DramaticStateMutation]?
    var audienceUpdate: String?

    init(
        id: UUID = UUID(),
        title: String,
        dramaticAction: String,
        characterAction: String,
        opposition: String,
        turn: String,
        outcome: String,
        screenplayText: String,
        stateChanges: [DramaticStateMutation]? = nil,
        audienceUpdate: String? = nil
    ) {
        self.id = id
        self.title = title
        self.dramaticAction = dramaticAction
        self.characterAction = characterAction
        self.opposition = opposition
        self.turn = turn
        self.outcome = outcome
        self.screenplayText = screenplayText
        self.stateChanges = stateChanges
        self.audienceUpdate = audienceUpdate
    }
}

nonisolated struct SceneMicroBeat: Codable, Hashable, Identifiable, Comparable {
    var id: UUID
    var ordinal: Int
    var purpose: String
    var options: [SceneBeatChoiceOption]
    var selectedOptionID: UUID?

    init(
        id: UUID = UUID(),
        ordinal: Int,
        purpose: String,
        options: [SceneBeatChoiceOption],
        selectedOptionID: UUID? = nil
    ) {
        self.id = id
        self.ordinal = ordinal
        self.purpose = purpose
        self.options = options
        self.selectedOptionID = selectedOptionID
    }

    var selectedOption: SceneBeatChoiceOption? {
        guard let selectedOptionID else { return nil }
        return options.first { $0.id == selectedOptionID }
    }

    static func < (lhs: SceneMicroBeat, rhs: SceneMicroBeat) -> Bool {
        if lhs.ordinal == rhs.ordinal {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.ordinal < rhs.ordinal
    }
}

enum StoryFactKind: String, Codable, CaseIterable {
    case premise = "前提"
    case character = "人物"
    case relationship = "关系"
    case worldRule = "世界规则"
    case theme = "主题命题"
    case event = "事件"
}

@Model
final class StoryFactRecord {
    @Attribute(.unique) var id: UUID
    var kindRawValue: String
    var subject: String
    var predicate: String
    var value: String
    var source: String
    var isLockedByAuthor: Bool
    var createdAt: Date
    var updatedAt: Date
    var project: StoryProject?

    init(
        id: UUID = UUID(),
        kind: StoryFactKind,
        subject: String,
        predicate: String,
        value: String,
        source: String,
        isLockedByAuthor: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        kindRawValue = kind.rawValue
        self.subject = subject
        self.predicate = predicate
        self.value = value
        self.source = source
        self.isLockedByAuthor = isLockedByAuthor
        self.createdAt = createdAt
        updatedAt = createdAt
    }

    var kind: StoryFactKind {
        get { StoryFactKind(rawValue: kindRawValue) ?? .event }
        set { kindRawValue = newValue.rawValue }
    }
}

enum StoryChangeSetStatus: String, Codable, CaseIterable {
    case proposed = "待确认"
    case applied = "已应用"
    case dismissed = "未采用"
}

@Model
final class StoryChangeSet {
    @Attribute(.unique) var id: UUID
    var title: String
    var summary: String
    var affectedAreasText: String
    var preservedElementsText: String
    var authorIdeaID: UUID?
    var statusRawValue: String
    var createdAt: Date
    var appliedAt: Date?
    var project: StoryProject?

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        affectedAreas: [String],
        preservedElements: [String],
        authorIdeaID: UUID? = nil,
        status: StoryChangeSetStatus = .proposed,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        affectedAreasText = affectedAreas.joined(separator: "\n")
        preservedElementsText = preservedElements.joined(separator: "\n")
        self.authorIdeaID = authorIdeaID
        statusRawValue = status.rawValue
        self.createdAt = createdAt
    }

    var status: StoryChangeSetStatus {
        get { StoryChangeSetStatus(rawValue: statusRawValue) ?? .proposed }
        set { statusRawValue = newValue.rawValue }
    }

    var affectedAreas: [String] { affectedAreasText.nonemptyLines }
    var preservedElements: [String] { preservedElementsText.nonemptyLines }
}

enum StoryCompilerIssueSeverity: String, Codable, CaseIterable {
    case blocker = "阻断"
    case warning = "警告"
    case note = "提示"
}

@Model
final class StoryCompilerIssue {
    @Attribute(.unique) var id: UUID
    var code: String
    var severityRawValue: String
    var title: String
    var detail: String
    var location: String
    var isResolved: Bool
    var createdAt: Date
    var updatedAt: Date
    var project: StoryProject?

    init(
        id: UUID = UUID(),
        code: String,
        severity: StoryCompilerIssueSeverity,
        title: String,
        detail: String,
        location: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.code = code
        severityRawValue = severity.rawValue
        self.title = title
        self.detail = detail
        self.location = location
        isResolved = false
        self.createdAt = createdAt
        updatedAt = createdAt
    }

    var severity: StoryCompilerIssueSeverity {
        get { StoryCompilerIssueSeverity(rawValue: severityRawValue) ?? .note }
        set { severityRawValue = newValue.rawValue }
    }
}

@Model
final class SceneContract {
    @Attribute(.unique) var id: UUID
    var sceneIndex: Int
    var structureStageIndex: Int?
    var stageSceneOrdinal: Int = 1
    var scopeTitle: String = ""
    var scopePurpose: String = ""
    var scopeEntryState: String = ""
    var scopeExitState: String = ""
    var sceneOptionsData: Data = Data()
    var selectedSceneOptionID: UUID?
    var microBeatUnitsData: Data = Data()
    var stateContractData: Data = Data()
    /// Provenance for deterministic projections such as NSIR transitions.
    /// Author edits are preserved by comparing the current fields with the
    /// last source snapshot before applying a newer source revision.
    var sourceKindRawValue: String = ""
    var sourceRevision: Int = 0
    var sourceFingerprint: String = ""
    var sourceSnapshotData: Data = Data()
    var sourceIsDetached: Bool = false
    var sourceIsMissing: Bool = false
    var heading: String
    var pointOfView: String
    var characterGoal: String
    var obstacle: String
    var turn: String
    var outcome: String
    var nextPressure: String
    var status: String
    var createdAt: Date
    var updatedAt: Date
    var project: StoryProject?

    init(
        id: UUID = UUID(),
        sceneIndex: Int,
        structureStageIndex: Int? = nil,
        stageSceneOrdinal: Int = 1,
        scopeTitle: String = "",
        scopePurpose: String = "",
        scopeEntryState: String = "",
        scopeExitState: String = "",
        heading: String = "",
        pointOfView: String = "",
        characterGoal: String = "",
        obstacle: String = "",
        turn: String = "",
        outcome: String = "",
        nextPressure: String = "",
        status: String = "待设计",
        createdAt: Date = .now
    ) {
        self.id = id
        self.sceneIndex = sceneIndex
        self.structureStageIndex = structureStageIndex
        self.stageSceneOrdinal = stageSceneOrdinal
        self.scopeTitle = scopeTitle
        self.scopePurpose = scopePurpose
        self.scopeEntryState = scopeEntryState
        self.scopeExitState = scopeExitState
        sceneOptionsData = Data()
        selectedSceneOptionID = nil
        microBeatUnitsData = Data()
        stateContractData = Data()
        self.heading = heading
        self.pointOfView = pointOfView
        self.characterGoal = characterGoal
        self.obstacle = obstacle
        self.turn = turn
        self.outcome = outcome
        self.nextPressure = nextPressure
        self.status = status
        self.createdAt = createdAt
        updatedAt = createdAt
    }

    var sceneOptions: [SceneChoiceOption] {
        get {
            PersistentPayloadCodec.decode(
                [SceneChoiceOption].self,
                from: sceneOptionsData,
                default: [],
                label: "SceneContract.sceneOptions"
            )
        }
        set {
            sceneOptionsData = PersistentPayloadCodec.encode(
                newValue,
                preserving: sceneOptionsData,
                label: "SceneContract.sceneOptions"
            )
            updatedAt = .now
        }
    }

    var selectedSceneOption: SceneChoiceOption? {
        guard let selectedSceneOptionID else { return nil }
        return sceneOptions.first { $0.id == selectedSceneOptionID }
    }

    var microBeats: [SceneMicroBeat] {
        get {
            PersistentPayloadCodec.decode(
                [SceneMicroBeat].self,
                from: microBeatUnitsData,
                default: [],
                label: "SceneContract.microBeats"
            )
        }
        set {
            microBeatUnitsData = PersistentPayloadCodec.encode(
                newValue,
                preserving: microBeatUnitsData,
                label: "SceneContract.microBeats"
            )
            updatedAt = .now
        }
    }

    var areMicroBeatsConfirmed: Bool {
        !microBeats.isEmpty && microBeats.allSatisfy { $0.selectedOption != nil }
    }

    var stateContract: SceneStateContract {
        get {
            if let decoded = PersistentPayloadCodec.decodeOptional(
                SceneStateContract.self,
                from: stateContractData,
                label: "SceneContract.stateContract"
            ), !decoded.isEmpty {
                return decoded
            }
            return SceneStateContract(
                entrySnapshot: scopeEntryState,
                requiredChanges: selectedSceneOption?.requiredStateChanges ?? [],
                forbiddenChanges: selectedSceneOption?.forbiddenChanges ?? [],
                audienceOutcome: selectedSceneOption?.audienceUpdate ?? "",
                exitSnapshot: scopeExitState,
                verificationRule: outcome
            )
        }
        set {
            stateContractData = PersistentPayloadCodec.encode(
                newValue,
                preserving: stateContractData,
                label: "SceneContract.stateContract"
            )
            updatedAt = .now
        }
    }
}

@Model
final class StoryRevisionSnapshot {
    @Attribute(.unique) var id: UUID
    var title: String
    var reason: String
    var projectDigest: String
    var screenplayText: String
    var createdAt: Date
    var project: StoryProject?

    init(
        id: UUID = UUID(),
        title: String,
        reason: String,
        projectDigest: String,
        screenplayText: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.reason = reason
        self.projectDigest = projectDigest
        self.screenplayText = screenplayText
        self.createdAt = createdAt
    }
}

private extension String {
    nonisolated var nonemptyLines: [String] {
        split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
