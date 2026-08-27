import Foundation
import SwiftData

@Model
final class StoryProject {
    @Attribute(.unique) var id: UUID
    var title: String
    var genreRawValue: String
    var logline: String
    var notes: String
    var creativeDirectionText: String = ""
    var creativeIdeasData: Data = Data()
    var creativeIdeasContextUpdatedAt: Date?
    var sourceTitle: String = ""
    var sourceText: String = ""
    var sourceFacts: String = ""
    var dramaticPromise: String = ""
    var storyPathText: String = ""
    var blueprintText: String = ""
    var structureTemplateID: String = ""
    var structureTemplateName: String = ""
    var structureRulesText: String = ""
    var isStructureLocked: Bool = false
    var structureLockedAt: Date?
    var lockedStructureSnapshot: String = ""
    var preferenceProfileData: Data = Data()
    var characterRelationshipsData: Data = Data()
    var characterGraphOptionsData: Data = Data()
    var characterGraphOptionsFingerprint: String = ""
    var characterGraphOptionsGeneratedAt: Date?
    var characterGraphLastInstruction: String = ""
    @Transient var characterGraphRequestToken: UUID?
    /// One-shot navigation intents used by the layered writing desk. They are
    /// deliberately transient: opening a level must never become story data.
    @Transient var requestedCharacterID: UUID?
    @Transient var requestedStructureStageIndex: Int?
    @Transient var requestedSceneContractID: UUID?
    var characterGraphHistoryData: Data = Data()
    var characterGraphLayoutData: Data = Data()
    var pacingPlansData: Data = Data()
    var worldText: String = ""
    var themeText: String = ""
    var structureText: String = ""
    var scenesText: String = ""
    var screenplayText: String = ""
    /// Canonical Narrative Semantic Intermediate Representation. Screenplay
    /// text is its editable realization: untouched projections follow NSIR,
    /// while direct screenplay edits detach safely from automatic replacement.
    var nsirWorkspaceData: Data = Data()
    var nsirRevision: Int = 0
    var nsirUpdatedAt: Date?
    var characterBibleText: String = ""
    var worldBibleText: String = ""
    var themeBibleText: String = ""
    var coreConflictText: String = ""
    var storyBibleDigest: String = ""
    var storyBibleRevision: Int = 0
    var storyBibleUpdatedAt: Date?
    var storyBibleSyncNote: String = ""
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \StoryCharacter.project)
    var characters: [StoryCharacter] = []

    @Relationship(deleteRule: .cascade, inverse: \StoryDecision.project)
    var decisions: [StoryDecision] = []

    @Relationship(deleteRule: .cascade, inverse: \ProjectArtifact.project)
    var artifacts: [ProjectArtifact] = []

    @Relationship(deleteRule: .cascade, inverse: \AnalysisReport.project)
    var reports: [AnalysisReport] = []

    @Relationship(deleteRule: .cascade, inverse: \CreativeTask.project)
    var tasks: [CreativeTask] = []

    @Relationship(deleteRule: .cascade, inverse: \AuthorIdeaRecord.project)
    var authorIdeas: [AuthorIdeaRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \StoryFactRecord.project)
    var canonicalFacts: [StoryFactRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \StoryChangeSet.project)
    var changeSets: [StoryChangeSet] = []

    @Relationship(deleteRule: .cascade, inverse: \StoryCompilerIssue.project)
    var compilerIssues: [StoryCompilerIssue] = []

    @Relationship(deleteRule: .cascade, inverse: \SceneContract.project)
    var sceneContracts: [SceneContract] = []

    @Relationship(deleteRule: .cascade, inverse: \StoryRevisionSnapshot.project)
    var revisionSnapshots: [StoryRevisionSnapshot] = []

    @Relationship(deleteRule: .cascade, inverse: \DramaticUpdateRecord.project)
    var dramaticUpdates: [DramaticUpdateRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \NarrativeProjectionRecord.project)
    var narrativeProjections: [NarrativeProjectionRecord] = []

    init(
        id: UUID = UUID(),
        title: String,
        genre: StoryGenre = .unselected,
        logline: String = "",
        notes: String = "",
        sourceTitle: String = "",
        sourceText: String = "",
        sourceFacts: String = "",
        dramaticPromise: String = "",
        storyPathText: String = "",
        blueprintText: String = "",
        structureTemplateID: String = "",
        structureTemplateName: String = "",
        structureRulesText: String = "",
        isStructureLocked: Bool = false,
        structureLockedAt: Date? = nil,
        lockedStructureSnapshot: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.genreRawValue = genre.rawValue
        self.logline = logline
        self.notes = notes
        self.sourceTitle = sourceTitle
        self.sourceText = sourceText
        self.sourceFacts = sourceFacts
        self.dramaticPromise = dramaticPromise
        self.storyPathText = storyPathText
        self.blueprintText = blueprintText
        self.structureTemplateID = structureTemplateID
        self.structureTemplateName = structureTemplateName
        self.structureRulesText = structureRulesText
        self.isStructureLocked = isStructureLocked
        self.structureLockedAt = structureLockedAt
        self.lockedStructureSnapshot = lockedStructureSnapshot
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension StoryProject {
    var genre: StoryGenre {
        get { StoryGenre(rawValue: genreRawValue) ?? .unselected }
        set { genreRawValue = newValue.rawValue }
    }

    @MainActor
    var nsirWorkspace: CompilerWorkspaceDocument {
        get {
            PersistentPayloadCodec.decode(
                CompilerWorkspaceDocument.self,
                from: nsirWorkspaceData,
                default: .empty(projectID: id),
                label: "StoryProject.nsirWorkspace"
            )
        }
        set {
            var value = newValue
            value.schemaVersion = NSIRSchema.currentVersion
            value.projectID = id
            value.updatedAt = .now
            nsirWorkspaceData = PersistentPayloadCodec.encode(
                value,
                preserving: nsirWorkspaceData,
                label: "StoryProject.nsirWorkspace"
            )
            nsirRevision = value.revision
            nsirUpdatedAt = value.updatedAt
            touch()
        }
    }

    @MainActor
    func requireNSIRWorkspace() throws -> CompilerWorkspaceDocument {
        guard !nsirWorkspaceData.isEmpty else {
            return .empty(projectID: id)
        }
        return try PersistentPayloadCodec.decodeRequired(
            CompilerWorkspaceDocument.self,
            from: nsirWorkspaceData,
            label: "StoryProject.nsirWorkspace"
        )
    }

    var openTaskCount: Int {
        tasks.filter { $0.status != .completed && $0.status != .skipped }.count
    }

    var completionFraction: Double {
        var score = 0.0
        if !title.trimmed.isEmpty { score += 0.05 }
        if !sourceText.trimmed.isEmpty || !logline.trimmed.isEmpty { score += 0.10 }
        if genre != .unselected { score += 0.05 }
        if !logline.trimmed.isEmpty { score += 0.10 }
        if !characters.isEmpty { score += 0.10 }
        if characters.contains(where: { !$0.externalGoal.trimmed.isEmpty }) { score += 0.05 }
        if characters.contains(where: { !$0.internalNeed.trimmed.isEmpty }) { score += 0.05 }
        if !worldText.trimmed.isEmpty { score += 0.08 }
        if !themeText.trimmed.isEmpty { score += 0.07 }
        if !structureText.trimmed.isEmpty { score += 0.12 }
        if !scenesText.trimmed.isEmpty { score += 0.10 }
        if !screenplayText.trimmed.isEmpty { score += 0.13 }
        if !storyPathText.trimmed.isEmpty { score += 0.08 }
        if !blueprintText.trimmed.isEmpty { score += 0.12 }
        return min(score, 1)
    }

    var projectSummary: String {
        let candidates = [logline, dramaticPromise, sourceFacts, notes]
        return candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            ?? "等待第一条故事选择。"
    }

    var projectSymbol: String {
        switch genre {
        case .crime: "handcuffs.fill"
        case .thriller: "bolt.trianglebadge.exclamationmark.fill"
        case .mystery: "eye.fill"
        case .romance: "heart.fill"
        case .comedy: "theatermasks.fill"
        case .scienceFiction: "sparkles"
        case .fantasy: "wand.and.stars"
        case .action: "figure.run"
        case .shortDrama: "rectangle.stack.fill"
        case .drama: "film.stack.fill"
        case .unselected: "leaf.fill"
        }
    }

    @MainActor
    var workflowLabel: String {
        if isStructureLocked,
           resolvedDecisionCount < structureTemplate.stages.count {
            let total = max(structureTemplate.stages.count, 1)
            return "结构推进 \(min(resolvedDecisionCount, total))/\(total)"
        }
        if !screenplayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "剧本写作"
        }
        if !scenesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "场景生成"
        }
        if isStructureLocked { return "结构已完成" }
        if !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "选择结构"
        }
        return "素材整理"
    }

    @MainActor
    var resolvedDecisionCount: Int {
        guard isStructureLocked else {
            return decisions.filter { $0.selectedOptionID != nil }.count
        }
        let validIndices = structureTemplate.stages.indices
        return Set(
            decisions
                .filter { $0.selectedOptionID != nil && validIndices.contains($0.stageIndex) }
                .map(\.stageIndex)
        ).count
    }

    @MainActor
    var nextStructureStageIndex: Int? {
        guard isStructureLocked else { return nil }
        let resolved = Set(
            decisions
                .filter { $0.selectedOptionID != nil }
                .map(\.stageIndex)
        )
        return structureTemplate.stages.indices.first { !resolved.contains($0) }
    }

    @MainActor
    var pendingReviewCount: Int {
        artifacts.filter { $0.status != .integrated }.count
    }

    var hasSelectedStructureTemplate: Bool {
        !structureTemplateID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    var structureTemplate: StoryStructureTemplate {
        StoryStructureCatalog.template(id: structureTemplateID)
    }

    @MainActor
    var structureRulesForPrompt: String {
        if isStructureLocked,
           !lockedStructureSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return lockedStructureSnapshot
        }
        if !structureRulesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return structureRulesText
        }
        let template = structureTemplate
        let stageRules = template.stages.enumerated().map { index, stage in
            "\(index + 1). \(stage.name)：\(stage.purpose)；选择焦点：\(stage.choiceFocus)"
        }.joined(separator: "\n")
        return """
        结构模板：\(template.name)
        体验目标：\(template.experience)
        套用风险：\(template.caution)
        必须依次完成的结构阶段：
        \(stageRules)
        """
    }

    @MainActor
    var preferenceProfile: ProjectPreferenceProfile {
        get {
            PersistentPayloadCodec.decode(
                ProjectPreferenceProfile.self,
                from: preferenceProfileData,
                default: .empty,
                label: "StoryProject.preferenceProfile"
            )
        }
        set {
            preferenceProfileData = PersistentPayloadCodec.encode(
                newValue,
                preserving: preferenceProfileData,
                label: "StoryProject.preferenceProfile"
            )
        }
    }

    @MainActor
    var characterRelationships: [CharacterRelationship] {
        get {
            PersistentPayloadCodec.decode(
                [CharacterRelationship].self,
                from: characterRelationshipsData,
                default: [],
                label: "StoryProject.characterRelationships"
            )
        }
        set {
            characterRelationshipsData = PersistentPayloadCodec.encode(
                newValue,
                preserving: characterRelationshipsData,
                label: "StoryProject.characterRelationships"
            )
            touch()
        }
    }

    @MainActor
    var characterGraphOptions: CharacterGraphOptionsResult? {
        get {
            PersistentPayloadCodec.decodeOptional(
                CharacterGraphOptionsResult.self,
                from: characterGraphOptionsData,
                label: "StoryProject.characterGraphOptions"
            )
        }
        set {
            if let newValue {
                characterGraphOptionsData = PersistentPayloadCodec.encode(
                    newValue,
                    preserving: characterGraphOptionsData,
                    label: "StoryProject.characterGraphOptions"
                )
            } else {
                characterGraphOptionsData = Data()
            }
            touch()
        }
    }

    @MainActor
    var characterGraphHistory: [CharacterGraphRevision] {
        get {
            PersistentPayloadCodec.decode(
                [CharacterGraphRevision].self,
                from: characterGraphHistoryData,
                default: [],
                label: "StoryProject.characterGraphHistory"
            )
        }
        set {
            characterGraphHistoryData = PersistentPayloadCodec.encode(
                newValue,
                preserving: characterGraphHistoryData,
                label: "StoryProject.characterGraphHistory"
            )
            touch()
        }
    }

    @MainActor
    var characterGraphLayout: [UUID: CharacterGraphLayoutPoint] {
        get {
            PersistentPayloadCodec.decode(
                [UUID: CharacterGraphLayoutPoint].self,
                from: characterGraphLayoutData,
                default: [:],
                label: "StoryProject.characterGraphLayout"
            )
        }
        set {
            characterGraphLayoutData = PersistentPayloadCodec.encode(
                newValue,
                preserving: characterGraphLayoutData,
                label: "StoryProject.characterGraphLayout"
            )
        }
    }

    @MainActor
    var pacingPlans: [StagePacingPlan] {
        get {
            PersistentPayloadCodec.decode(
                [StagePacingPlan].self,
                from: pacingPlansData,
                default: [],
                label: "StoryProject.pacingPlans"
            )
        }
        set {
            pacingPlansData = PersistentPayloadCodec.encode(
                newValue,
                preserving: pacingPlansData,
                label: "StoryProject.pacingPlans"
            )
            touch()
        }
    }

    @MainActor
    func pacingPlan(for stageIndex: Int, total: Int) -> StagePacingPlan {
        pacingPlans.first { $0.stageIndex == stageIndex }
            ?? StagePacingPlan.suggested(stageIndex: stageIndex, total: total)
    }

    @MainActor
    func setPacingPlan(_ plan: StagePacingPlan) {
        var plan = plan
        plan.updatedAt = .now
        var plans = pacingPlans
        if let index = plans.firstIndex(where: { $0.stageIndex == plan.stageIndex }) {
            plans[index] = plan
        } else {
            plans.append(plan)
        }
        pacingPlans = plans.sorted { $0.stageIndex < $1.stageIndex }
    }

    @MainActor
    func lockStructure() {
        guard hasSelectedStructureTemplate, !isStructureLocked else { return }
        let snapshot = structureRulesForPrompt
        lockedStructureSnapshot = snapshot
        structureRulesText = snapshot
        structureLockedAt = .now
        isStructureLocked = true
        touch()
    }

    func touch() {
        updatedAt = .now
    }
}

private extension String {
    nonisolated var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
