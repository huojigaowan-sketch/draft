import Foundation
import FoundationModels

@Generable
nonisolated struct JourneyChoiceDraft {
    var title: String
    var pitch: String
    var concreteDetail: String
    var consequence: String
    var futurePressure: String
    var sampleMoment: String
    var evidenceBasis: [String]
    var sourceCount: Int
    var realityTexture: String
    var paceEffect: String
    var emotionShift: String
    var eventScale: String
    @Guide(description: "本大节拍核心变化维度，只能是：世界事实、认知与信念、目标与策略、关系与权力、承诺与规范、观众认知")
    var stateDimension: String
    @Guide(description: "被改变的具体状态对象")
    var stateSubject: String
    @Guide(description: "本大节拍开始前成立的状态")
    var beforeState: String
    @Guide(description: "本大节拍结束后必须成立的新状态")
    var afterState: String
    @Guide(description: "观众在本大节拍结束时新增、修正或失去的理解")
    var audienceUpdate: String
    @Guide(description: "为了保护后续固定结构，本大节拍不能提前改变的事项")
    var forbiddenChanges: [String]
}

@Generable
nonisolated struct JourneyDecisionDraft {
    var question: String
    var executionNote: String

    @Guide(
        description: "恰好四个具体、互不重复、会真正改变后续剧情的选项",
        .count(4)
    )
    var options: [JourneyChoiceDraft]
}

@Generable
nonisolated struct JourneyBlueprintDraft {
    var title: String
    var logline: String
    var theme: String
    var protagonistArc: String
    var antagonistDesign: String
    var actOne: String
    var actTwo: String
    var actThree: String

    var nextWritingTask: String
}

@MainActor
enum TypedStoryJourneyExecutor {
    static func decision(
        context: StoryJourneyContext,
        configuration: AIConfiguration
    ) async throws -> DeepSeekJourneyDecisionCompletion {
        let session = StoryLanguageRuntime.session(
            configuration: configuration,
            instructions: """
            你是故事编译器的结构选项执行器。作者拥有创意主权；你只能依据作者给定的
            创意、锁定结构与现实资料，完成候选路线的具体化、差异化和逻辑检查。
            必须给出恰好四个具体且互不重复的选项。每个选项都要有可拍摄细节、代价、
            下一层压力和可视化瞬间。至少一个从关系出发，各选项不能只替换职业或地点。
            每个选项必须明确至少一次 W/K/G/R/D/E 的 before → after 状态变化、观众认知
            变化和不得提前发生的变化。节奏只由有效状态变化影响量除以时间决定，不能用
            句数、动作数量、剪辑感或情绪形容词冒充。
            不诊断作者、不教导作者、不宣称替作者创新、不推翻已确认事实。
            """
        )
        let response = try await session.respond(
            to: """
            【锁定结构】
            \(context.templateName)
            \(context.templateRules)

            【当前结构点】
            \(context.stageName)
            功能：\(context.stagePurpose)
            本轮焦点：\(context.choiceFocus)

            【作者项目与已确认选择】
            \(context.projectContext)

            【现实资料】
            \(context.realityContext.isEmpty ? "无" : context.realityContext)

            【相关理论，只用于执行检查】
            \(context.theoryContext.isEmpty ? "无" : context.theoryContext)

            【经典功能参考，不复制情节】
            \(context.storyDNAContext.isEmpty ? "无" : context.storyDNAContext)

            返回恰好四个选项。executionNote 只说明这些选项如何服从结构，
            不评价作者，不提出第五个方向。
            """,
            generating: JourneyDecisionDraft.self,
            options: GenerationOptions(
                temperature: 0.78,
                maximumResponseTokens: 4_800
            )
        )

        guard response.content.options.count == 4 else {
            throw DeepSeekError.decoding("AI 没有返回恰好四个强类型选项。")
        }
        return DeepSeekJourneyDecisionCompletion(
            result: JourneyDecisionResult(
                question: response.content.question,
                coachNote: response.content.executionNote,
                options: response.content.options.map(\.storyChoice)
            ),
            usage: .zero
        )
    }

    static func refine(
        context: JourneyOptionRefinementContext,
        configuration: AIConfiguration
    ) async throws -> DeepSeekJourneyOptionCompletion {
        let session = StoryLanguageRuntime.session(
            configuration: configuration,
            instructions: """
            你是精确的局部重做执行器。本轮只能重做作者指定的一项，另外三项、
            锁定结构与既有事实必须保持不动。直接执行作者命令，不增加自己的创意方向。
            """
        )
        let response = try await session.respond(
            to: """
            【锁定结构】\(context.templateName)
            \(context.templateRules)

            【当前结构点】\(context.stageName)
            功能：\(context.stagePurpose)
            焦点：\(context.choiceFocus)

            【项目】\(context.projectContext)
            【只能重做的选项】\(context.currentOption)
            【保持不动的选项】\(context.siblingOptions)
            【作者唯一命令】\(context.authorInstruction)
            【资料】\(context.researchContext)
            【本地偏好】\(context.preferenceContext)
            """,
            generating: JourneyChoiceDraft.self,
            options: GenerationOptions(
                temperature: 0.62,
                maximumResponseTokens: 2_400
            )
        )
        return DeepSeekJourneyOptionCompletion(
            option: response.content.storyChoice,
            usage: .zero
        )
    }

    static func blueprint(
        context: StoryJourneyContext,
        configuration: AIConfiguration
    ) async throws -> DeepSeekBlueprintCompletion {
        let session = StoryLanguageRuntime.session(
            configuration: configuration,
            instructions: """
            你是故事编译器的全本路线执行器。把作者已确认的全部结构选择编译成连续因果路线。
            不增加会取代作者选择的新核心设定。这里只整理第二层的全本路线，不生成场景；
            场景只能在第三层按节拍逐一展开。严格覆盖作者锁定的结构模板。
            """
        )
        let response = try await session.respond(
            to: """
            【锁定结构】
            \(context.templateName)
            \(context.templateRules)

            【作者已确认的完整故事路径】
            \(context.projectContext)

            【现实资料】
            \(context.realityContext.isEmpty ? "无" : context.realityContext)

            【理论与案例只用于连续性检查】
            \(context.theoryContext)
            \(context.storyDNAContext)
            """,
            generating: JourneyBlueprintDraft.self,
            options: GenerationOptions(
                temperature: 0.34,
                maximumResponseTokens: 5_500
            )
        )
        let draft = response.content
        return DeepSeekBlueprintCompletion(
            blueprint: JourneyBlueprint(
                title: draft.title,
                logline: draft.logline,
                theme: draft.theme,
                protagonistArc: draft.protagonistArc,
                antagonistDesign: draft.antagonistDesign,
                actOne: draft.actOne,
                actTwo: draft.actTwo,
                actThree: draft.actThree,
                scenes: [],
                nextWritingTask: draft.nextWritingTask
            ),
            usage: .zero
        )
    }
}

@MainActor
private extension JourneyChoiceDraft {
    var storyChoice: StoryChoiceOption {
        StoryChoiceOption(
            title: title,
            pitch: pitch,
            concreteDetail: concreteDetail,
            consequence: consequence,
            futurePressure: futurePressure,
            sampleMoment: sampleMoment,
            evidenceBasis: evidenceBasis,
            sourceCount: sourceCount,
            realityTexture: realityTexture,
            paceEffect: paceEffect,
            emotionShift: emotionShift,
            eventScale: eventScale,
            plannedStateChanges: [
                DramaticStateMutation(
                    dimension: semanticDimension(stateDimension),
                    subject: stateSubject.trimmingCharacters(in: .whitespacesAndNewlines),
                    beforeValue: beforeState.trimmingCharacters(in: .whitespacesAndNewlines),
                    afterValue: afterState.trimmingCharacters(in: .whitespacesAndNewlines),
                    observerNames: ["观众"]
                )
            ],
            audienceUpdate: audienceUpdate,
            forbiddenChanges: forbiddenChanges
        )
    }

    private func semanticDimension(_ value: String) -> DramaticStateDimension {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return DramaticStateDimension.allCases.first {
            clean.contains($0.rawValue) || $0.rawValue.contains(clean)
        } ?? .world
    }
}
