import Foundation
import CryptoKit
import NaturalLanguage

struct JourneyDecisionOutcome {
    let stage: StructureStage
    let stageIndex: Int
    let result: JourneyDecisionResult
    let usage: TokenUsage
    let preparationNote: String
}

struct JourneyOptionRefinementOutcome {
    let option: StoryChoiceOption
    let usage: TokenUsage
    let preparationNote: String
}

struct JourneyBlueprintOutcome {
    let blueprint: JourneyBlueprint
    let usage: TokenUsage
    let preparationNote: String
}

@MainActor
struct StoryJourneyEngine {
    let settings: AISettingsStore

    func optionsContextFingerprint(
        for project: StoryProject,
        decision: StoryDecision
    ) -> String {
        let template = project.structureTemplate
        guard template.stages.indices.contains(decision.stageIndex) else {
            return ""
        }
        let stage = template.stages[decision.stageIndex]
        let pacing = project.pacingPlan(
            for: decision.stageIndex,
            total: template.stages.count
        )
        let payload = """
        story-journey-options-v1
        模型：\(settings.model)
        思考模式：\(settings.thinkingEnabled)
        Apple 预处理：\(settings.useApplePreprocessing)
        知识库：\(settings.useKnowledgeBase)
        模板：\(template.name)
        模板规则：\(project.structureRulesForPrompt)
        阶段：\(stage.name)
        阶段目的：\(stage.purpose)
        选择焦点：\(stage.choiceFocus)
        \(projectContext(
            project,
            stageIndex: decision.stageIndex,
            includePreferences: false
        ))
        \(project.protectedCreativeContext(for: decision.stageIndex))
        作者阶段注入：\(decision.authorBrief)
        \(pacing.promptBlock)
        \(combinedRealityContext(
            project,
            stageResearch: decision.researchResult?.promptContext ?? ""
        ))
        """
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func nextDecision(
        for project: StoryProject,
        stageResearch: String = "",
        authorBrief: String = ""
    ) async throws -> JourneyDecisionOutcome {
        let template = project.structureTemplate
        guard let stageIndex = project.nextStructureStageIndex else {
            throw StoryJourneyError.allDecisionsCompleted
        }
        let stage = template.stages[stageIndex]
        let pacing = project.pacingPlan(
            for: stageIndex,
            total: template.stages.count
        )
        let source = projectContext(project, stageIndex: stageIndex) + """

        【作者对本阶段的初始注入】
        \(authorBrief.isEmpty ? "作者暂未补充。" : authorBrief)

        \(pacing.promptBlock)
        """
        let prepared = await AppleTextService.prepareForAnalysis(
            source,
            enabled: settings.useApplePreprocessing
        )
        let protectedProjectContext = """
        \(prepared.text)

        \(project.protectedCreativeContext(for: stageIndex))

        【作者对本阶段的初始注入 · 未经摘要 · 必须优先执行】
        \(authorBrief.isEmpty ? "作者暂未补充。" : authorBrief)

        【本阶段节奏与情绪约束 · 未经摘要 · 必须优先执行】
        \(pacing.promptBlock)
        """
        let supporting = await supportingContext(
            query: "\(template.name) \(stage.name) \(stage.purpose)\n\(source)",
            project: project
        )
        let completion = try await TypedStoryJourneyExecutor.decision(
            context: StoryJourneyContext(
                templateName: template.name,
                templateRules: project.structureRulesForPrompt,
                stageName: stage.name,
                stagePurpose: stage.purpose,
                choiceFocus: stage.choiceFocus,
                projectContext: protectedProjectContext,
                theoryContext: supporting.theory,
                storyDNAContext: supporting.storyDNA,
                realityContext: combinedRealityContext(project, stageResearch: stageResearch)
            ),
            configuration: settings.configuration()
        )
        return JourneyDecisionOutcome(
            stage: stage,
            stageIndex: stageIndex,
            result: completion.result,
            usage: completion.usage,
            preparationNote: prepared.note
        )
    }

    func regenerateOption(
        _ option: StoryChoiceOption,
        instruction: String,
        in decision: StoryDecision,
        project: StoryProject
    ) async throws -> JourneyOptionRefinementOutcome {
        let template = project.structureTemplate
        guard template.stages.indices.contains(decision.stageIndex) else {
            throw StoryJourneyError.invalidStage
        }
        let stage = template.stages[decision.stageIndex]
        let pacing = project.pacingPlan(
            for: decision.stageIndex,
            total: template.stages.count
        )
        let source = projectContext(project, stageIndex: decision.stageIndex) + """

        【作者对本阶段的直接注入】
        \(decision.authorBrief.isEmpty ? "作者暂未补充。" : decision.authorBrief)

        \(pacing.promptBlock)
        """
        let prepared = await AppleTextService.prepareForAnalysis(
            source,
            enabled: settings.useApplePreprocessing
        )
        let protectedProjectContext = """
        \(prepared.text)

        \(project.protectedCreativeContext(for: decision.stageIndex))

        【作者对本阶段的直接注入 · 未经摘要 · 必须优先执行】
        \(decision.authorBrief.isEmpty ? "作者暂未补充。" : decision.authorBrief)

        【本阶段节奏与情绪约束 · 未经摘要 · 必须优先执行】
        \(pacing.promptBlock)
        """
        let siblings = decision.options
            .filter { $0.id != option.id }
            .enumerated()
            .map { "\($0.offset + 1). \($0.element.title)：\($0.element.pitch)" }
            .joined(separator: "\n")
        let completion = try await TypedStoryJourneyExecutor.refine(
            context: JourneyOptionRefinementContext(
                templateName: template.name,
                templateRules: project.structureRulesForPrompt,
                stageName: stage.name,
                stagePurpose: stage.purpose,
                choiceFocus: stage.choiceFocus,
                projectContext: protectedProjectContext,
                currentOption: optionPrompt(option),
                siblingOptions: siblings,
                authorInstruction: instruction,
                researchContext: decision.researchResult?.promptContext ?? "",
                preferenceContext: ProjectPreferenceEngine.promptBlock(for: project)
            ),
            configuration: settings.configuration()
        )
        return JourneyOptionRefinementOutcome(
            option: completion.option,
            usage: completion.usage,
            preparationNote: prepared.note
        )
    }

    func blueprint(for project: StoryProject) async throws -> JourneyBlueprintOutcome {
        let template = project.structureTemplate
        guard project.resolvedDecisionCount >= template.stages.count else {
            throw StoryJourneyError.notEnoughDecisions
        }
        let source = projectContext(project, stageIndex: nil)
        let prepared = await AppleTextService.prepareForAnalysis(
            source,
            enabled: settings.useApplePreprocessing
        )
        let protectedProjectContext = """
        \(prepared.text)

        \(project.protectedCreativeContext(for: nil))
        """
        let supporting = await supportingContext(
            query: "完整故事 结构 场景 因果 高潮 \(source)",
            project: project
        )
        let allResearch = project.decisions
            .compactMap(\.researchResult?.promptContext)
            .joined(separator: "\n\n")
        let completion = try await TypedStoryJourneyExecutor.blueprint(
            context: StoryJourneyContext(
                templateName: template.name,
                templateRules: project.structureRulesForPrompt,
                stageName: "完整路线",
                stagePurpose: "把全部阶段组织成连续、可写、可拍的因果路线。",
                choiceFocus: "尊重作者选择，并让每个模板阶段在场景中兑现。",
                projectContext: protectedProjectContext,
                theoryContext: supporting.theory,
                storyDNAContext: supporting.storyDNA,
                realityContext: combinedRealityContext(project, stageResearch: allResearch)
            ),
            configuration: settings.configuration()
        )
        return JourneyBlueprintOutcome(
            blueprint: completion.blueprint,
            usage: completion.usage,
            preparationNote: prepared.note
        )
    }

    private func supportingContext(
        query: String,
        project: StoryProject
    ) async -> (theory: String, storyDNA: String) {
        let route = TheoryRouting.route(for: .journey)
        let evidence: [TheoryEvidence]
        if settings.useKnowledgeBase {
            evidence = (try? await TheoryIndexStore.shared.search(
                query: query,
                route: route,
                maximumMatches: 5,
                maximumCharacters: 2_800
            )) ?? []
        } else {
            evidence = []
        }
        let cases = StoryDNAService.shared.matches(
            query: query,
            genre: project.genre.rawValue,
            limit: 3
        )
        return (
            evidence.map(\.promptBlock).joined(separator: "\n\n"),
            cases.map(\.promptBlock).joined(separator: "\n\n")
        )
    }

    private func projectContext(
        _ project: StoryProject,
        stageIndex: Int?,
        includePreferences: Bool = true
    ) -> String {
        let characters = project.characters
            .sorted {
                if $0.name == $1.name {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.name < $1.name
            }
            .map { character in
            """
            \(character.role.rawValue) \(character.name)
            描述：\(character.seedText)
            目标：\(character.externalGoal)
            需求：\(character.internalNeed)
            恐惧：\(character.fear)
            错误信念：\(character.falseBelief)
            """
        }.joined(separator: "\n\n")

        let choices = project.decisions
            .filter { $0.selectedOptionID != nil }
            .sorted {
                if $0.stageIndex == $1.stageIndex {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.stageIndex < $1.stageIndex
            }
            .map { decision in
                let option = decision.selectedOption
                return """
                【第\(decision.stageIndex + 1)阶段 · \(decision.stageName)】
                作者确认：\(decision.selectedAnswerText)
                代价：\(option?.consequence ?? "")
                后续压力：\(option?.futurePressure ?? "")
                """
            }
            .joined(separator: "\n\n")

        let relationships = project.characterRelationships
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { relationship in
            let from = project.characters.first {
                $0.id == relationship.fromCharacterID
            }?.name ?? "未知人物"
            let to = project.characters.first {
                $0.id == relationship.toCharacterID
            }?.name ?? "未知人物"
            return "\(from) → \(to)：\(relationship.kind.rawValue)，张力\(relationship.tension)，\(relationship.detail)"
        }.joined(separator: "\n")

        return """
        项目：\(project.title)
        类型：\(project.genre.rawValue)
        【作者创意方向与后来注入】
        \(project.creativeContext(for: stageIndex))
        锁定结构：\(project.structureTemplate.name)
        来源：\(project.sourceTitle)
        事实层：\(project.sourceFacts)
        一句话：\(project.logline)
        戏剧问题：\(project.dramaticPromise)
        项目笔记：\(project.notes)

        【当前故事罗盘】
        世界：\(project.worldText.isEmpty ? project.worldBibleText : project.worldText)
        主题：\(project.themeText.isEmpty ? project.themeBibleText : project.themeText)
        核心冲突：\(project.coreConflictText.isEmpty ? project.dramaticPromise : project.coreConflictText)

        【动态剧本圣经 · 本机增量生成】
        \(project.storyBibleDigest.isEmpty ? "尚未建立。" : project.storyBibleDigest)

        【人物材料】
        \(characters.isEmpty ? "尚未建立人物档案。" : characters)

        【已确认人物关系图】
        \(relationships.isEmpty ? "尚未建立关系边。" : relationships)

        【作者已确认且不可推翻的结构选择】
        \(choices.isEmpty ? "尚未作出选择。" : choices)

        \(includePreferences
            ? ProjectPreferenceEngine.promptBlock(for: project)
            : "【本机项目偏好】不作为当前四选项的过期条件。")
        """
    }

    private func combinedRealityContext(
        _ project: StoryProject,
        stageResearch: String
    ) -> String {
        let material = project.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectReality = material.contains("【现实资料包】")
            ? String(material.prefix(7_000))
            : ""
        return [projectReality, String(stageResearch.prefix(7_000))]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n【当前阶段专项调查】\n")
    }

    private func optionPrompt(_ option: StoryChoiceOption) -> String {
        """
        标题：\(option.title)
        方向：\(option.pitch)
        具体细节：\(option.concreteDetail)
        代价：\(option.consequence)
        后续压力：\(option.futurePressure)
        场面预告：\(option.sampleMoment)
        现实质感：\(option.realityTexture)
        """
    }
}

struct ProjectPreferenceProfile: Codable, Hashable {
    var tokenWeights: [String: Double]
    var likedSamples: [String]
    var feedbackHistory: [String]
    var signalCount: Int
    var updatedAt: Date?

    static let empty = ProjectPreferenceProfile(
        tokenWeights: [:],
        likedSamples: [],
        feedbackHistory: [],
        signalCount: 0,
        updatedAt: nil
    )
}

enum ProjectPreferenceSignal {
    case liked
    case unliked
    case selected
    case refined
}

@MainActor
enum ProjectPreferenceEngine {
    static func record(
        _ signal: ProjectPreferenceSignal,
        option: StoryChoiceOption,
        feedback: String = "",
        in project: StoryProject
    ) {
        var profile = project.preferenceProfile
        let reward: Double
        switch signal {
        case .liked: reward = 1.0
        case .unliked: reward = -1.0
        case .selected: reward = 2.4
        case .refined: reward = -0.35
        }

        for token in tokens(option.preferenceText) {
            profile.tokenWeights[token, default: 0] = max(
                -6,
                min(10, profile.tokenWeights[token, default: 0] * 0.985 + reward)
            )
        }
        if signal == .liked || signal == .selected {
            profile.likedSamples.append(String(option.preferenceText.prefix(420)))
            profile.likedSamples = Array(profile.likedSamples.suffix(16))
        }
        let cleanFeedback = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanFeedback.isEmpty {
            profile.feedbackHistory.append(cleanFeedback)
            profile.feedbackHistory = Array(profile.feedbackHistory.suffix(20))
            for token in tokens(cleanFeedback) {
                profile.tokenWeights[token, default: 0] += 0.75
            }
        }
        profile.signalCount += 1
        profile.updatedAt = .now
        project.preferenceProfile = profile
        project.touch()
    }

    static func score(_ option: StoryChoiceOption, for project: StoryProject) -> Double {
        let profile = project.preferenceProfile
        let text = option.preferenceText.lowercased()
        return profile.tokenWeights
            .filter { $0.value > 0.4 }
            .sorted {
                if $0.value == $1.value { return $0.key < $1.key }
                return $0.value > $1.value
            }
            .prefix(32)
            .reduce(0.0) { score, item in
                score + (text.contains(item.key.lowercased()) ? item.value : 0)
            }
    }

    static func promptBlock(for project: StoryProject) -> String {
        let profile = project.preferenceProfile
        guard profile.signalCount > 0 else {
            return "【本机项目偏好】尚未形成；不要替作者假设审美。"
        }
        let positive = profile.tokenWeights
            .filter { $0.value > 0.6 }
            .sorted {
                if $0.value == $1.value { return $0.key < $1.key }
                return $0.value > $1.value
            }
            .prefix(14)
            .map(\.key)
            .joined(separator: "、")
        let feedback = profile.feedbackHistory.suffix(6).joined(separator: "；")
        let samples = profile.likedSamples.suffix(4).joined(separator: "\n")
        return """
        【本机项目偏好画像 · \(profile.signalCount)个反馈信号】
        高频倾向：\(positive.isEmpty ? "仍在学习" : positive)
        作者近期指令：\(feedback.isEmpty ? "暂无" : feedback)
        作者喜欢或确认过的表达：
        \(samples.isEmpty ? "暂无" : samples)
        这是软偏好，不得覆盖锁定结构、事实与作者本轮明确命令。
        """
    }

    private static func tokens(_ text: String) -> [String] {
        let source = text.lowercased()
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = source
        var result: [String] = []
        tokenizer.enumerateTokens(in: source.startIndex..<source.endIndex) { range, _ in
            let token = String(source[range]).trimmingCharacters(in: .punctuationCharacters)
            if token.count > 1 { result.append(token) }
            return true
        }
        return result
    }

}

enum StoryJourneyError: LocalizedError {
    case allDecisionsCompleted
    case notEnoughDecisions
    case invalidStage

    var errorDescription: String? {
        switch self {
        case .allDecisionsCompleted:
            "全部结构阶段已经完成，可以生成全本路线。"
        case .notEnoughDecisions:
            "请先完成锁定结构的全部阶段。"
        case .invalidStage:
            "当前阶段与锁定结构不一致。"
        }
    }
}
