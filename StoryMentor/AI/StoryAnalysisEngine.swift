import Foundation

struct AnalysisOutcome {
    let result: AIAnalysisResult
    let usage: TokenUsage
    let localPreparationNote: String
    let evidence: [TheoryEvidence]
}

@MainActor
struct StoryAnalysisEngine {
    let settings: AISettingsStore

    func analyze(
        project: StoryProject,
        section: WorkspaceSection,
        character: StoryCharacter?
    ) async throws -> AnalysisOutcome {
        let source = StoryInputBuilder.sourceText(
            project: project,
            section: section,
            character: character
        )
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StoryAnalysisError.emptyMaterial
        }

        let prepared = await AppleTextService.prepareForAnalysis(
            source,
            enabled: settings.useApplePreprocessing
        )
        let protectedProjectContext = """
        \(prepared.text)

        \(project.protectedCreativeContext(
            for: section == .journey ? project.nextStructureStageIndex : nil
        ))
        """
        let route = TheoryRouting.route(for: section)
        let evidence: [TheoryEvidence]
        if settings.useKnowledgeBase {
            evidence = (try? await TheoryIndexStore.shared.search(
                query: source,
                route: route,
                maximumMatches: 6,
                maximumCharacters: 3_600
            )) ?? []
        } else {
            evidence = []
        }
        let storyCases = StoryDNAService.shared.matches(
            query: source,
            genre: project.genre.rawValue,
            limit: 4
        )

        let remoteContext = RemoteAnalysisContext(
            sectionName: section.rawValue,
            genre: project.genre.rawValue,
            authorMaterial: protectedProjectContext,
            theoryFocus: route.focus,
            storyDNAContext: storyCases.map(\.promptBlock).joined(separator: "\n\n"),
            knowledgeContext: evidence.map(\.promptBlock).joined(separator: "\n\n")
        )
        let client = DeepSeekClient(configuration: try settings.configuration())
        let completion = try await client.analyze(remoteContext)
        return AnalysisOutcome(
            result: completion.result,
            usage: completion.usage,
            localPreparationNote: "\(prepared.note) · 理论证据 \(evidence.count) 条，约 \(evidence.reduce(0) { $0 + $1.estimatedTokens }) tokens",
            evidence: evidence
        )
    }
}

@MainActor
enum StoryInputBuilder {
    static func sourceText(
        project: StoryProject,
        section: WorkspaceSection,
        character: StoryCharacter?
    ) -> String {
        switch section {
        case .home, .seeds, .classics, .fragments:
            return ""
        case .journey:
            return withCreativeContext(
                """
            项目：\(project.title)
            一句话：\(project.logline)
            戏剧问题：\(project.dramaticPromise)
            作者选择：
            \(project.storyPathText)
            """,
                project: project,
                stageIndex: project.nextStructureStageIndex
            )
        case .templates:
            return withCreativeContext(project.structureRulesForPrompt, project: project)
        case .compiler, .overview, .ideas:
            let characterBriefs = project.characters.map {
                "\($0.role.rawValue) \($0.name)：\($0.seedText)\n目标：\($0.externalGoal)\n需求：\($0.internalNeed)"
            }
            return withCreativeContext(
                """
            项目：\(project.title)
            类型：\(project.genre.rawValue)
            一句话：\(project.logline)
            项目笔记：\(project.notes)
            人物：
            \(characterBriefs.joined(separator: "\n\n"))
            """,
                project: project
            )
        case .characters, .relationships:
            guard let character else { return "" }
            return withCreativeContext(
                """
            人物：\(character.name)
            功能：\(character.role.rawValue)
            年龄：\(character.age)
            职业：\(character.occupation)
            自由描述：\(character.seedText)
            背景：\(character.background)
            外部目标：\(character.externalGoal)
            内在需求：\(character.internalNeed)
            恐惧：\(character.fear)
            创伤：\(character.trauma)
            秘密：\(character.secret)
            错误信念：\(character.falseBelief)
            缺陷：\(character.flaw)
            能力：\(character.strength)
            弧线：\(character.arc)
            """,
                project: project
            )
        case .world:
            return withCreativeContext(project.worldText, project: project)
        case .theme:
            return withCreativeContext(project.themeText, project: project)
        case .structure:
            return withCreativeContext(project.structureText, project: project)
        case .scenes:
            return withCreativeContext(project.scenesText, project: project)
        case .screenplay, .versions, .delivery:
            return withCreativeContext(project.screenplayText, project: project)
        case .knowledge:
            return ""
        }
    }

    private static func withCreativeContext(
        _ source: String,
        project: StoryProject,
        stageIndex: Int? = nil
    ) -> String {
        """
        \(source)

        【作者创意方向与后来注入】
        \(project.creativeContext(for: stageIndex))
        """
    }
}

enum StoryAnalysisError: LocalizedError {
    case emptyMaterial

    var errorDescription: String? {
        "当前模块还没有足够文字。先写下一点素材，再发起诊断。"
    }
}
