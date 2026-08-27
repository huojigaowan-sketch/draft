import Foundation
import SwiftData

@MainActor
enum CaptainCommandApplier {
    static func apply(
        _ option: CaptainCommandOption,
        from idea: AuthorIdeaRecord,
        to project: StoryProject,
        in modelContext: ModelContext
    ) throws {
        guard idea.selectedCaptainOptionID == nil else {
            throw CaptainCommandApplyError.alreadyApplied
        }
        guard !option.affectedChanges.isEmpty else {
            throw CaptainCommandApplyError.noChanges
        }

        try ProjectPersistenceStore.transaction(in: modelContext) {
            StoryCompiler.insertSnapshot(
                project: project,
                title: "执行船长指令前",
                reason: idea.originalText,
                in: modelContext
            )

        idea.protectedCore = option.protectedCore
        idea.affectedAreas = option.affectedChanges.map(\.area.rawValue)
        idea.preservedElements = option.preservedFacts
        idea.risks = option.continuityRisks
        idea.proposedActions = option.affectedChanges.map {
            "\($0.area.rawValue) · \($0.target)：\($0.update)"
        }
        idea.executionIdeaID = project.addCreativeIdea(
            text: idea.originalText,
            scope: .project,
            stageIndex: nil
        )
        idea.selectedCaptainOptionID = option.id
        idea.status = .active
        idea.appliedAt = .now
        idea.updatedAt = .now

        let changeSet = StoryChangeSet(
            title: "船长确认 · \(option.title)",
            summary: option.strategy,
            affectedAreas: option.affectedChanges.map(\.area.rawValue),
            preservedElements: option.preservedFacts,
            authorIdeaID: idea.id,
            status: .applied
        )
        changeSet.appliedAt = .now
        changeSet.project = project
        modelContext.insert(changeSet)

        var nextSortIndex = (project.artifacts.map(\.sortIndex).max() ?? -1) + 1
        for change in option.affectedChanges {
            let title = "船长指令 · \(change.area.rawValue)"
            let artifact = ProjectArtifact(
                title: title,
                kind: change.area.moduleKind,
                status: .reviewing,
                originLabel: "船长操控框 · 用户确认",
                humanInput: idea.originalText,
                lockedIdeas: ([option.protectedCore] + option.preservedFacts)
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: "\n"),
                workingText: change.update,
                acceptedText: "",
                aiInstruction: "",
                aiSummary: change.consequence,
                sortIndex: nextSortIndex,
                project: project
            )
            nextSortIndex += 1
            modelContext.insert(artifact)
            project.artifacts.append(artifact)
            artifact.confirmAndIntegrate()
            synchronizeBible(change, commandTitle: option.title, project: project)
        }

        project.storyBibleDigest = """
        【人物小传】
        \(project.characterBibleText.bibleFallback)

        【世界规则】
        \(project.worldBibleText.bibleFallback)

        【主题命题】
        \(project.themeBibleText.bibleFallback)

        【核心冲突】
        \(project.coreConflictText.bibleFallback)
        """
        project.storyBibleRevision += 1
        project.storyBibleUpdatedAt = .now
        project.storyBibleSyncNote = "船长确认“\(option.title)”后已同步全部受影响模块"
        project.touch()
            StoryCompiler.updateFindings(project: project, in: modelContext)
        }
    }

    private static func synchronizeBible(
        _ change: CaptainAreaChange,
        commandTitle: String,
        project: StoryProject
    ) {
        let block = """
        【船长确认 · \(commandTitle) · \(change.target)】
        \(change.update)
        """

        switch change.area {
        case .premise:
            break
        case .characters:
            project.characterBibleText = appending(block, to: project.characterBibleText)
            for character in project.characters
            where change.target.localizedCaseInsensitiveContains(character.name) {
                character.seedText = appending(block, to: character.seedText)
                character.touch()
            }
        case .relationships:
            project.characterBibleText = appending(block, to: project.characterBibleText)
        case .world:
            project.worldBibleText = appending(block, to: project.worldBibleText)
        case .theme:
            project.themeBibleText = appending(block, to: project.themeBibleText)
        case .conflict:
            project.coreConflictText = appending(block, to: project.coreConflictText)
        case .structure, .scenes, .screenplay:
            break
        }
    }

    private static func appending(_ block: String, to text: String) -> String {
        let current = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBlock = block.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return cleanBlock }
        return "\(current)\n\n\(cleanBlock)"
    }
}

enum CaptainCommandApplyError: LocalizedError {
    case alreadyApplied
    case noChanges

    var errorDescription: String? {
        switch self {
        case .alreadyApplied:
            "这条船长指令已经确认执行。"
        case .noChanges:
            "这个方案没有可执行的模块变更。"
        }
    }
}

private extension String {
    var bibleFallback: String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "尚待后续选择确认"
            : self
    }
}
