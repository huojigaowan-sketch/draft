import Foundation
import FoundationModels

@Generable
nonisolated private struct SceneBeatChoiceAIDraft {
    @Guide(description: "六到十二字的小节拍方案名")
    var title: String
    @Guide(description: "这一小节拍中真正发生的戏剧动作；描述事件，不描述摄影")
    var dramaticAction: String
    @Guide(description: "人物为实现目的而采取的可见行动或说出的关键话语")
    var characterAction: String
    @Guide(description: "人物行动在此刻遭遇的直接反作用力")
    var opposition: String
    @Guide(description: "行动与反作用碰撞后出现的新变化、揭示或选择")
    var turn: String
    @Guide(description: "小节拍结束时产生的确定结果，以及它如何推动下一小节拍")
    var outcome: String
    @Guide(description: "可以直接写进 Fountain 剧本的动作或对白段落；不写分析、编号、场景标题或摄影术语")
    var screenplayText: String
    @Guide(description: "这次不可再分更新的维度，只能是：世界事实、认知与信念、目标与策略、关系与权力、承诺与规范、观众认知")
    var stateDimension: String
    @Guide(description: "被改变的具体状态对象")
    var stateSubject: String
    @Guide(description: "更新之前的状态")
    var beforeState: String
    @Guide(description: "更新之后的状态，必须与之前不同")
    var afterState: String
    @Guide(description: "本次更新给观众造成的认知变化；没有则写无")
    var audienceUpdate: String
}

@Generable
nonisolated private struct SceneMicroBeatAIDraft {
    @Guide(description: "这个小节拍在场景因果链中必须完成的唯一任务")
    var purpose: String
    @Guide(
        description: "恰好四个完成同一任务、但戏剧行动与人物选择不同的方案",
        .count(4)
    )
    var options: [SceneBeatChoiceAIDraft]
}

@Generable
nonisolated private struct SceneBeatPlanAIDraft {
    @Guide(description: "按因果顺序排列的一至十二个必要情境更新；数量完全由场景契约所需的最少状态变化决定")
    var microBeats: [SceneMicroBeatAIDraft]
}

@MainActor
enum SceneBeatChoiceEngine {
    static func generatePlan(
        for contract: SceneContract,
        project: StoryProject,
        configuration: AIConfiguration
    ) async throws -> [SceneMicroBeat] {
        guard contract.selectedSceneOptionID != nil,
              SceneCompilationEngine.isComplete(contract) else {
            throw SceneBeatChoiceError.sceneNotConfirmed
        }

        let scenes = project.sceneContracts.sorted { $0.sceneIndex < $1.sceneIndex }
        let scenePosition = scenes.firstIndex { $0.id == contract.id }
        let previous = scenePosition.flatMap { $0 > 0 ? scenes[$0 - 1] : nil }
        let next = scenePosition.flatMap { $0 + 1 < scenes.count ? scenes[$0 + 1] : nil }
        let executionConfiguration = configuration.withThinkingEnabled(false)
        let session = StoryLanguageRuntime.session(
            configuration: executionConfiguration,
            instructions: """
            你是场景内部情境更新执行器。作者已经确认场景状态契约；你要用必要且最少的一至十二个
            情境更新构成这场戏，并为每次更新提供恰好四个方案。每一项是功能上不可再分的
            “行动/言语行为/感知/沉默/事件—反作用—状态变化”，不是句子、镜头或摄影设计。
            同一次行动可同时改变多个状态维度，但两个独立功能不得合并。所有更新串联后必须
            完整执行场景的目标、阻碍、转折、结果与下一场压力。不得改变已确认事实、增加
            支线或重复相同功能。每个方案都必须附带可直接进入剧本的动作或对白文字。
            """
        )
        let response = try await session.respond(
            to: """
            【项目与剧本圣经】
            \(project.projectSummary)
            \(project.storyBibleDigest)

            【已确认场景】
            场 \(contract.sceneIndex) · \(contract.heading)
            视点：\(contract.pointOfView)
            即时目标：\(contract.characterGoal)
            阻碍：\(contract.obstacle)
            转折：\(contract.turn)
            结果：\(contract.outcome)
            下一场压力：\(contract.nextPressure)
            进入状态：\(contract.stateContract.entrySnapshot)
            必须实现的状态差异：
            \(contract.stateContract.requiredChanges.map { "\($0.dimension.rawValue)·\($0.subject)：\($0.beforeValue) → \($0.afterValue)" }.joined(separator: "\n"))
            观众离场认知：\(contract.stateContract.audienceOutcome)
            禁止提前改变：\(contract.stateContract.forbiddenChanges.joined(separator: "；"))

            【相邻场景】
            上一场结果：\(previous?.outcome.trimmed.nonemptyFallback ?? "这是全片第一场")
            下一场目标：\(next?.characterGoal.trimmed.nonemptyFallback ?? "这是全片最后一场")

            【作者创意】
            \(project.protectedCreativeContext(for: contract.structureStageIndex))

            用必要且最少的一至十二次情境更新执行这场戏。每次更新只承担一个不可再分功能，并提供
            恰好四个真正不同的行动方案。不要写场景标题、景别、构图、运镜或剪辑；剧本
            文字必须能按顺序直接串联，并自然衔接前后小节拍。
            """,
            generating: SceneBeatPlanAIDraft.self,
            options: GenerationOptions(
                temperature: 0.64,
                maximumResponseTokens: 8_000
            )
        )
        let microBeats = response.content.microBeats.enumerated().map { offset, draft in
            SceneMicroBeat(
                ordinal: offset + 1,
                purpose: draft.purpose.trimmed,
                options: draft.options.map {
                    SceneBeatChoiceOption(
                        title: $0.title.trimmed,
                        dramaticAction: $0.dramaticAction.trimmed,
                        characterAction: $0.characterAction.trimmed,
                        opposition: $0.opposition.trimmed,
                        turn: $0.turn.trimmed,
                        outcome: $0.outcome.trimmed,
                        screenplayText: $0.screenplayText.trimmed,
                        stateChanges: [
                            DramaticStateMutation(
                                dimension: semanticDimension($0.stateDimension),
                                subject: $0.stateSubject.trimmed,
                                beforeValue: $0.beforeState.trimmed,
                                afterValue: $0.afterState.trimmed,
                                observerNames: ["观众"]
                            )
                        ],
                        audienceUpdate: $0.audienceUpdate.trimmed
                    )
                }
            )
        }
        guard (1...12).contains(microBeats.count),
              microBeats.allSatisfy({ microBeat in
                  microBeat.options.count == 4
                      && Set(microBeat.options.map(\.title)).count == 4
                      && !microBeat.purpose.isEmpty
                      && microBeat.options.allSatisfy(\.isComplete)
              }) else {
            throw SceneBeatChoiceError.invalidPlan
        }
        return microBeats
    }

    private static func semanticDimension(_ value: String) -> DramaticStateDimension {
        let clean = value.trimmed
        return DramaticStateDimension.allCases.first {
            clean.contains($0.rawValue) || $0.rawValue.contains(clean)
        } ?? .world
    }
}

private extension SceneBeatChoiceOption {
    var isComplete: Bool {
        [
            title,
            dramaticAction,
            characterAction,
            opposition,
            turn,
            outcome,
            screenplayText
        ].allSatisfy { !$0.trimmed.isEmpty }
            && stateChanges?.contains(where: \.isEffective) == true
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nonemptyFallback: String? {
        isEmpty ? nil : self
    }
}

enum SceneBeatChoiceError: LocalizedError {
    case sceneNotConfirmed
    case invalidPlan

    var errorDescription: String? {
        switch self {
        case .sceneNotConfirmed:
            "请先在第 3 层确认这个场景。"
        case .invalidPlan:
            "DeepSeek 没有返回一至十二次完整情境更新，或某次更新没有恰好四个方案。"
        }
    }
}
