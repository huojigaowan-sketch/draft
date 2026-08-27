import Foundation
import SwiftData

/// The single write boundary for project-level SwiftData operations.
///
/// Views may still edit observable model properties through bindings, but
/// multi-model commands and graph maintenance must pass through this store so
/// they save once and roll back the complete context on failure.
@MainActor
enum ProjectPersistenceStore {
    static func transaction(
        in context: ModelContext,
        _ changes: () throws -> Void
    ) throws {
        do {
            try context.transaction(block: changes)
        } catch {
            context.rollback()
            throw error
        }
    }

    static func savePendingChanges(in context: ModelContext) throws {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Saves a seed only after it has been attached to an existing project.
    /// The persisted column keeps its legacy name, but its meaning is now the
    /// required project foreign key for every story-specific record.
    static func save(
        seed: StorySeed,
        under projectID: UUID,
        in context: ModelContext
    ) throws {
        let descriptor = FetchDescriptor<StoryProject>(
            predicate: #Predicate { $0.id == projectID }
        )
        guard let project = try context.fetch(descriptor).first else {
            throw ProjectPersistenceError.missingProject(projectID)
        }
        if seed.projectID != projectID {
            seed.projectID = projectID
        }
        seed.updatedAt = .now
        project.touch()
        try savePendingChanges(in: context)
    }

    /// Compatibility boundary for older creation surfaces that predate an
    /// explicit active-project parameter. It never permits a new orphan seed:
    /// an unowned seed receives a project in the same save operation.
    @discardableResult
    static func saveEnsuringProject(
        seed: StorySeed,
        in context: ModelContext
    ) throws -> UUID {
        if let projectID = seed.projectID {
            try save(seed: seed, under: projectID, in: context)
            return projectID
        }

        let cleanTitle = seed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = StoryProject(
            title: cleanTitle.isEmpty ? "未命名故事项目" : cleanTitle,
            notes: "由旧版种子入口自动建立；种子、实验与剧本统一归入此项目。",
            sourceTitle: seed.title,
            sourceText: seed.sourceText,
            createdAt: seed.createdAt,
            updatedAt: seed.updatedAt
        )
        context.insert(project)
        seed.projectID = project.id
        seed.updatedAt = .now
        project.touch()
        try savePendingChanges(in: context)
        return project.id
    }

    /// Returns the one canonical screenplay workspace for a project and folds
    /// legacy duplicates into it before deleting them.
    static func screenplayState(
        for project: StoryProject,
        in context: ModelContext
    ) throws -> ScreenplayWorkspaceState {
        let projectID = project.id
        let descriptor = FetchDescriptor<ScreenplayWorkspaceState>(
            predicate: #Predicate { $0.projectID == projectID },
            sortBy: [
                SortDescriptor(\ScreenplayWorkspaceState.updatedAt, order: .reverse),
                SortDescriptor(\ScreenplayWorkspaceState.createdAt, order: .forward)
            ]
        )
        let matches = try context.fetch(descriptor)
        guard let canonical = matches.first else {
            let state = ScreenplayWorkspaceState(projectID: projectID)
            context.insert(state)
            return state
        }

        for duplicate in matches.dropFirst() {
            try canonical.validatePayloads()
            try duplicate.validatePayloads()
            canonical.absorbLegacyDuplicate(duplicate)
            context.delete(duplicate)
        }
        return canonical
    }

    /// Repairs the project ownership graph without discarding recovery clues.
    ///
    /// Older builds allowed seeds without a project and deleted screenplay
    /// workspaces whose raw project ID no longer resolved. The project is now
    /// the aggregate root, so migration creates a recovery project instead,
    /// preserving the original UUID whenever one already exists.
    @discardableResult
    static func repairGraph(
        projects: [StoryProject],
        seeds: [StorySeed],
        in context: ModelContext
    ) throws -> Bool {
        let allWorkspaceStates = try context.fetch(
            FetchDescriptor<ScreenplayWorkspaceState>()
        )

        // Fail closed before changing identifiers. A corrupt nested payload
        // must roll back the complete startup transaction, never decode as an
        // empty seed and then overwrite the original bytes.
        for seed in seeds {
            try validatePayloads(of: seed)
        }
        for state in allWorkspaceStates {
            try state.validatePayloads()
        }
        for project in projects where !project.nsirWorkspaceData.isEmpty {
            _ = try project.requireNSIRWorkspace()
        }

        var projectsByID: [UUID: StoryProject] = [:]
        for project in projects {
            projectsByID[project.id] = project
        }
        var changed = false

        func recoverProject(
            id: UUID,
            title: String,
            sourceTitle: String = "",
            sourceText: String = "",
            createdAt: Date = .now,
            updatedAt: Date = .now,
            note: String
        ) -> StoryProject {
            if let existing = projectsByID[id] { return existing }
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let project = StoryProject(
                id: id,
                title: cleanTitle.isEmpty ? "恢复的故事项目" : cleanTitle,
                notes: note,
                sourceTitle: sourceTitle,
                sourceText: sourceText,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
            context.insert(project)
            projectsByID[id] = project
            changed = true
            return project
        }

        for seed in seeds {
            let owningID = seed.projectID ?? UUID()
            if projectsByID[owningID] == nil {
                _ = recoverProject(
                    id: owningID,
                    title: seed.title,
                    sourceTitle: seed.title,
                    sourceText: seed.sourceText,
                    createdAt: seed.createdAt,
                    updatedAt: seed.updatedAt,
                    note: seed.projectID == nil
                        ? "由旧版本未归档种子自动建立；种子、实验与剧本现在统一归入此项目。"
                        : "按旧种子保留的项目 UUID 恢复；原始项目记录缺失。"
                )
            }
            if seed.projectID != owningID {
                seed.projectID = owningID
                seed.updatedAt = .now
                changed = true
            }
        }

        for state in allWorkspaceStates where projectsByID[state.projectID] == nil {
            let shortID = String(state.projectID.uuidString.prefix(8)).uppercased()
            _ = recoverProject(
                id: state.projectID,
                title: "恢复的剧本项目 · \(shortID)",
                createdAt: state.createdAt,
                updatedAt: state.updatedAt,
                note: "由旧版本孤立剧本工作区自动恢复；剧本文字与版本记录均保留原项目 UUID。"
            )
        }

        for project in projectsByID.values {
            if !project.nsirWorkspaceData.isEmpty {
                var document = try project.requireNSIRWorkspace()
                guard document.schemaVersion <= NSIRSchema.currentVersion else {
                    throw ProjectPersistenceError.unsupportedNSIRSchema(
                        found: document.schemaVersion,
                        supported: NSIRSchema.currentVersion
                    )
                }
                if document.projectID != project.id
                    || document.schemaVersion != NSIRSchema.currentVersion {
                    document.projectID = project.id
                    document.schemaVersion = NSIRSchema.currentVersion
                    project.nsirWorkspace = document
                    changed = true
                } else {
                    if project.nsirRevision != document.revision {
                        project.nsirRevision = document.revision
                        changed = true
                    }
                    if project.nsirUpdatedAt != document.updatedAt {
                        project.nsirUpdatedAt = document.updatedAt
                        changed = true
                    }
                }
            }
        }

        let statesByProject = Dictionary(grouping: allWorkspaceStates, by: \.projectID)
        for matches in statesByProject.values where matches.count > 1 {
            let ordered = matches.sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.createdAt < $1.createdAt
            }
            guard let canonical = ordered.first else { continue }
            for duplicate in ordered.dropFirst() {
                canonical.absorbLegacyDuplicate(duplicate)
                context.delete(duplicate)
            }
            changed = true
        }

        let fragments = try context.fetch(FetchDescriptor<StoryFragment>())
        for fragment in fragments {
            if let projectID = fragment.projectID,
               projectsByID[projectID] == nil {
                _ = recoverProject(
                    id: projectID,
                    title: fragment.projectTitle.isEmpty
                        ? "恢复的灵感项目"
                        : fragment.projectTitle,
                    createdAt: fragment.createdAt,
                    updatedAt: fragment.updatedAt,
                    note: "按灵感碎片保留的项目 UUID 恢复。"
                )
            }
            if let grownProjectID = fragment.grownProjectID,
               projectsByID[grownProjectID] == nil {
                _ = recoverProject(
                    id: grownProjectID,
                    title: fragment.title,
                    createdAt: fragment.createdAt,
                    updatedAt: fragment.updatedAt,
                    note: "按已成长灵感保留的项目 UUID 恢复。"
                )
            }
        }

        return changed
    }

    static func delete(
        project: StoryProject,
        in context: ModelContext
    ) throws {
        let projectID = project.id
        try transaction(in: context) {
            // Fetch from the persistence context at action time rather than
            // trusting a potentially stale @Query snapshot from the view.
            let allSeeds = try context.fetch(FetchDescriptor<StorySeed>())
            let ownedSeeds = allSeeds.filter { $0.projectID == projectID }
            let ownedSeedIDs = Set(ownedSeeds.map(\.id))

            let dossiers = try context.fetch(FetchDescriptor<ResearchDossier>())
            for dossier in dossiers where dossier.linkedSeedID.map(ownedSeedIDs.contains) == true {
                dossier.linkedSeedID = nil
                dossier.updatedAt = .now
            }

            let fragments = try context.fetch(FetchDescriptor<StoryFragment>())
            for fragment in fragments {
                if fragment.projectID == projectID {
                    fragment.projectID = nil
                }
                if fragment.grownProjectID == projectID {
                    fragment.grownProjectID = nil
                }
            }

            let descriptor = FetchDescriptor<ScreenplayWorkspaceState>(
                predicate: #Predicate { $0.projectID == projectID }
            )
            try context.fetch(descriptor).forEach(context.delete)
            ownedSeeds.forEach(context.delete)
            context.delete(project)
        }
    }

    private static func validatePayloads(of seed: StorySeed) throws {
        if !seed.dramaticElementsData.isEmpty {
            _ = try PersistentPayloadCodec.decodeRequired(
                [DramaticElement].self,
                from: seed.dramaticElementsData,
                label: "StorySeed.dramaticElements"
            )
        }
        if !seed.directionsData.isEmpty {
            _ = try PersistentPayloadCodec.decodeRequired(
                [AdaptationDirection].self,
                from: seed.directionsData,
                label: "StorySeed.directions"
            )
        }
        if !seed.scienceLabData.isEmpty {
            _ = try PersistentPayloadCodec.decodeRequired(
                StoryCultivationSnapshot.self,
                from: seed.scienceLabData,
                label: "StorySeed.cultivationSnapshot"
            )
        }
        if !seed.pendingExperimentData.isEmpty {
            _ = try PersistentPayloadCodec.decodeRequired(
                StoryExperimentCandidate.self,
                from: seed.pendingExperimentData,
                label: "StorySeed.pendingExperimentCandidate"
            )
        }
    }
}

enum ProjectPersistenceError: LocalizedError {
    case unsupportedNSIRSchema(found: Int, supported: Int)
    case missingProject(UUID)

    var errorDescription: String? {
        switch self {
        case .unsupportedNSIRSchema(let found, let supported):
            "NSIR 数据版本为 \(found)，当前应用仅支持到 \(supported)。已停止写入以保护原始数据。"
        case .missingProject(let projectID):
            "项目 \(projectID.uuidString) 不存在，已停止保存以避免产生孤立数据。"
        }
    }
}

@MainActor
private extension ScreenplayWorkspaceState {
    func validatePayloads() throws {
        if !metadataData.isEmpty {
            _ = try PersistentPayloadCodec.decodeRequired(
                [ScreenplaySceneMetadata].self,
                from: metadataData,
                label: "ScreenplayWorkspaceState.metadata"
            )
        }
        if !sceneRecordsData.isEmpty {
            _ = try PersistentPayloadCodec.decodeRequired(
                [ScreenplaySceneRecord].self,
                from: sceneRecordsData,
                label: "ScreenplayWorkspaceState.sceneRecords"
            )
        }
        if !revisionsData.isEmpty {
            _ = try PersistentPayloadCodec.decodeRequired(
                [ScreenplayRevision].self,
                from: revisionsData,
                label: "ScreenplayWorkspaceState.revisions"
            )
        }
        if !reviewRoundsData.isEmpty {
            _ = try PersistentPayloadCodec.decodeRequired(
                [ScreenplayReviewRound].self,
                from: reviewRoundsData,
                label: "ScreenplayWorkspaceState.reviewRounds"
            )
        }
        if !elementStylesData.isEmpty {
            _ = try PersistentPayloadCodec.decodeRequired(
                [ScreenplayElementStyleDefinition].self,
                from: elementStylesData,
                label: "ScreenplayWorkspaceState.elementStyles"
            )
        }
    }

    func absorbLegacyDuplicate(_ duplicate: ScreenplayWorkspaceState) {
        metadata = merged(metadata, duplicate.metadata, id: \.id)
        sceneRecords = merged(sceneRecords, duplicate.sceneRecords, id: \.id)
            .sorted { $0.order < $1.order }
        revisions = merged(revisions, duplicate.revisions, id: \.id)
            .sorted { $0.createdAt > $1.createdAt }
        reviewRounds = merged(reviewRounds, duplicate.reviewRounds, id: \.id)
            .sorted { $0.createdAt > $1.createdAt }

        if updatedAt < duplicate.updatedAt {
            activeSceneIndex = duplicate.activeSceneIndex
            activeSceneID = duplicate.activeSceneID
            generationStatus = duplicate.generationStatus
            generationCompletedScenes = duplicate.generationCompletedScenes
            generationTotalScenes = duplicate.generationTotalScenes
            generationCurrentScene = duplicate.generationCurrentScene
            generationMessage = duplicate.generationMessage
            generationStartedAt = duplicate.generationStartedAt
            generationFinishedAt = duplicate.generationFinishedAt
            if !duplicate.elementStylesData.isEmpty {
                elementStylesData = duplicate.elementStylesData
            }
        }
        createdAt = min(createdAt, duplicate.createdAt)
        updatedAt = max(updatedAt, duplicate.updatedAt)
    }

    func merged<Element, ID: Hashable>(
        _ primary: [Element],
        _ secondary: [Element],
        id: KeyPath<Element, ID>
    ) -> [Element] {
        var seen = Set<ID>()
        return (primary + secondary).filter {
            seen.insert($0[keyPath: id]).inserted
        }
    }
}
