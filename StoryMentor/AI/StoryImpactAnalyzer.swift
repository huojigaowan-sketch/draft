import Foundation
import FoundationModels

@Generable
nonisolated struct IdeaImpactAnalysis {
    @Guide(description: "用两到三句话说明这个想法会怎样改变当前故事，不替作者扩写新创意")
    var summary: String

    @Guide(description: "从作者原文中提取必须原样保护的创新核心")
    var protectedCore: String

    @Guide(description: "会受到影响的项目区域，例如人物、关系、大节拍、场景、主题或世界规则")
    var affectedAreas: [String]

    @Guide(description: "必须保持不动的既有选择，尤其是锁定结构和作者明确确认的事实")
    var preservedElements: [String]

    @Guide(description: "可能产生的连续性、因果、人物动机、节奏或主题风险")
    var risks: [String]

    @Guide(description: "AI 可以承担的机械性后续动作，不提出替代作者创意的新方向")
    var proposedActions: [String]
}

@MainActor
enum StoryImpactAnalyzer {
    static func analyze(
        idea: String,
        scope: CreativeIdeaScope,
        stageIndex: Int?,
        project: StoryProject,
        configuration: AIConfiguration
    ) async throws -> IdeaImpactAnalysis {
        let template = project.structureTemplate
        let stageDescription: String
        if let stageIndex, template.stages.indices.contains(stageIndex) {
            let stage = template.stages[stageIndex]
            stageDescription = "第 \(stageIndex + 1) 个大节拍：\(stage.name)；功能：\(stage.purpose)"
        } else {
            stageDescription = "全项目"
        }

        let characters = project.characters.prefix(20).map { character in
            "\(character.name)：外在目标 \(character.externalGoal)；内在需求 \(character.internalNeed)"
        }
        .joined(separator: "\n")
        let decisions = project.decisions
            .filter { $0.selectedOptionID != nil }
            .sorted { $0.stageIndex < $1.stageIndex }
            .prefix(24)
            .map {
                "大节拍 \($0.stageIndex + 1)：\($0.selectedOption?.title ?? "已确认")"
            }
            .joined(separator: "\n")

        let session = StoryLanguageRuntime.session(
            configuration: configuration,
            instructions: """
            你是“故事编译器”的影响分析器，不是创意导师。
            作者提供创新，AI 只负责识别影响、守住已确认事实、发现逻辑风险并列出机械性工作。
            绝不评价想法好坏，绝不另提创意，绝不修改项目，绝不把作者原话稀释成类型片套话。
            锁定结构只能被标记为受影响或需要作者重新确认，不能被默认推翻。
            """
        )

        let response = try await session.respond(
            to: """
            【作者新想法】
            \(idea)

            【作者指定范围】
            \(scope.rawValue)；\(stageDescription)

            【项目核心】
            片名：\(project.title)
            类型：\(project.genre.rawValue)
            一句话：\(project.logline)
            主题：\(project.themeText)
            核心冲突：\(project.coreConflictText)

            【锁定结构】
            \(project.isStructureLocked ? project.structureRulesForPrompt : "尚未锁定结构")

            【现有人物】
            \(characters.isEmpty ? "尚无人物" : characters)

            【作者已经确认的结构选择】
            \(decisions.isEmpty ? "尚无确认选择" : decisions)

            只做影响分析。所有 proposedActions 必须是检查、同步、重排、补齐、改写、验证等执行工作，
            不能包含“设计一个更有创意的……”之类替作者创作的任务。
            """,
            generating: IdeaImpactAnalysis.self,
            options: GenerationOptions(
                temperature: 0.18,
                maximumResponseTokens: 1_500
            )
        )
        return response.content
    }
}
