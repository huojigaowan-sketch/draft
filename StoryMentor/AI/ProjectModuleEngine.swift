import Foundation

struct ProjectModuleOptionOutcome {
    let result: ProjectModuleOptionsResult
    let usage: TokenUsage
    let preparationNote: String
}

struct ProjectModuleRefinementOutcome {
    let result: ProjectModuleRefinementResult
    let usage: TokenUsage
    let preparationNote: String
}

@MainActor
struct ProjectModuleEngine {
    let settings: AISettingsStore

    func generateOptions(
        for module: ProjectArtifact,
        in project: StoryProject
    ) async throws -> ProjectModuleOptionOutcome {
        let rawContext = projectContext(project, excluding: module.id)
        let prepared = await AppleTextService.prepareForAnalysis(
            rawContext,
            enabled: settings.useApplePreprocessing
        )
        let preparedReview = await AppleTextService.prepareForAnalysis(
            module.aiInstruction,
            enabled: settings.useApplePreprocessing
        )
        let theory = await theoryContext(
            query: "\(module.kind.rawValue) \(module.title) \(module.humanInput) \(module.lockedIdeas)",
            section: module.kind.workspaceSection
        )
        let storyDNA = StoryDNAService.shared.matches(
            query: "\(module.humanInput)\n\(module.workingText)",
            genre: project.genre.rawValue,
            limit: 3
        )
        .map(\.promptBlock)
        .joined(separator: "\n\n")

        let completion = try await DeepSeekClient(
            configuration: settings.configuration()
        ).generateProjectModuleOptions(
            ProjectModuleAIContext(
                projectTitle: project.title,
                genre: project.genre.rawValue,
                projectCreativeDirection: project.creativeContext(),
                structureRules: project.structureRulesForPrompt,
                moduleKind: module.kind.rawValue,
                moduleFocus: module.kind.promptFocus,
                moduleTitle: module.title,
                humanInput: module.humanInput,
                lockedIdeas: module.lockedIdeas,
                authorGuidance: module.authorGuidanceText,
                currentDraft: module.workingText,
                authorCommand: preparedReview.text,
                projectContext: prepared.text,
                theoryContext: theory,
                storyDNAContext: storyDNA,
                researchContext: String(
                    (module.researchResult?.promptContext ?? "").prefix(7_000)
                )
            )
        )
        return ProjectModuleOptionOutcome(
            result: completion.result,
            usage: completion.usage,
            preparationNote: prepared.note
        )
    }

    func refine(
        _ module: ProjectArtifact,
        in project: StoryProject
    ) async throws -> ProjectModuleRefinementOutcome {
        try await refineDraft(
            kind: module.kind,
            title: module.title,
            humanInput: module.humanInput,
            lockedIdeas: module.lockedIdeas,
            currentText: module.workingText,
            instruction: module.aiInstruction,
            authorGuidance: module.authorGuidanceText,
            researchContext: String(
                (module.researchResult?.promptContext ?? "").prefix(7_000)
            ),
            in: project
        )
    }

    func refineDraft(
        kind: ProjectModuleKind,
        title: String,
        humanInput: String,
        lockedIdeas: String,
        currentText: String,
        instruction: String,
        authorGuidance: String = "",
        researchContext: String = "",
        in project: StoryProject
    ) async throws -> ProjectModuleRefinementOutcome {
        let rawContext = projectContext(project, excluding: nil)
        let prepared = await AppleTextService.prepareForAnalysis(
            rawContext,
            enabled: settings.useApplePreprocessing
        )
        let theory = await theoryContext(
            query: "\(kind.rawValue) 重写 微调 \(instruction) \(currentText)",
            section: kind.workspaceSection
        )
        let completion = try await DeepSeekClient(
            configuration: settings.configuration()
        ).refineProjectModule(
            ProjectModuleRefinementContext(
                projectTitle: project.title,
                genre: project.genre.rawValue,
                projectCreativeDirection: project.creativeContext(),
                moduleKind: kind.rawValue,
                moduleFocus: kind.promptFocus,
                moduleTitle: title,
                humanInput: humanInput,
                lockedIdeas: lockedIdeas,
                authorGuidance: authorGuidance,
                currentDraft: currentText,
                authorCommand: instruction,
                projectContext: prepared.text,
                theoryContext: theory,
                researchContext: researchContext
            )
        )
        return ProjectModuleRefinementOutcome(
            result: completion.result,
            usage: completion.usage,
            preparationNote: prepared.note
        )
    }

    private func theoryContext(
        query: String,
        section: WorkspaceSection
    ) async -> String {
        guard settings.useKnowledgeBase else { return "" }
        let evidence = (try? await TheoryIndexStore.shared.search(
            query: query,
            route: TheoryRouting.route(for: section),
            maximumMatches: 4,
            maximumCharacters: 2_400
        )) ?? []
        return evidence.map(\.promptBlock).joined(separator: "\n\n")
    }

    private func projectContext(
        _ project: StoryProject,
        excluding moduleID: UUID?
    ) -> String {
        let acceptedModules = project.artifacts
            .filter { $0.id != moduleID && $0.status == .integrated }
            .sorted { $0.sortIndex < $1.sortIndex }
            .map { "【\($0.kind.rawValue) · \($0.title)】\n\($0.acceptedText)" }
            .joined(separator: "\n\n")

        let characters = project.characters.map {
            "\($0.role.rawValue) \($0.name)：\($0.seedText)；目标：\($0.externalGoal)；需求：\($0.internalNeed)"
        }
        .joined(separator: "\n")

        let context = """
        项目：\(project.title)
        类型：\(project.genre.rawValue)
        项目创作方向与后来注入：\(project.creativeContext())
        一句话故事：\(project.logline)
        戏剧承诺：\(project.dramaticPromise)
        结构模板：\(project.structureTemplateName)
        作者总笔记：\(project.notes)

        【动态剧本圣经】
        \(project.storyBibleDigest.isEmpty ? "尚未建立。" : project.storyBibleDigest)

        【人物档案】
        \(characters.isEmpty ? "尚未建立。" : characters)

        【项目内已确认内容】
        \(acceptedModules.isEmpty ? "尚无已确认创作卡。" : acceptedModules)

        【已经确认的故事路径】
        \(project.storyPathText)

        \(project.dramaticSemanticFoundationPrompt)
        """
        return String(context.prefix(14_000))
    }
}
