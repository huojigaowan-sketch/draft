import Foundation
import FoundationModels

nonisolated struct SceneScopeDraft: Hashable {
    var title: String
    var purpose: String
    var entryState: String
    var exitState: String
}

enum SceneChoiceSourceKind: Equatable {
    case confirmedStage
    case nsirTransition
}

struct SceneChoiceSourceContext: Equatable {
    let kind: SceneChoiceSourceKind
    let hierarchyLabel: String
    let sourceBadge: String
    let promptBlock: String
    let fallbackNextPressure: String
    let creativeStageIndex: Int?
}

@Generable
nonisolated private struct SceneScopeAIDraft {
    @Guide(description: "八到十六字的场景槽位名称，不写内外景格式")
    var title: String
    @Guide(description: "这场必须完成的唯一叙事任务")
    var purpose: String
    @Guide(description: "进入本场前已经成立的人物、信息与压力状态")
    var entryState: String
    @Guide(description: "离开本场时必须发生的唯一关键状态变化")
    var exitState: String
}

@Generable
nonisolated private struct SceneScopeSetDraft {
    @Guide(description: "按因果顺序排列的一至四个场景槽位；每个槽位只承担一次关键状态变化")
    var scenes: [SceneScopeAIDraft]
}

@Generable
nonisolated private struct SceneChoiceAIDraft {
    @Guide(description: "八到十六字的方案名")
    var title: String
    @Guide(description: "说明这个方案采用的具体执行机制，以及它与另外三个方案的根本区别")
    var approach: String
    @Guide(description: "标准可拍摄场景标题，包含内外景、具体地点和时间")
    var heading: String
    @Guide(description: "观众主要通过谁经历这一场")
    var pointOfView: String
    @Guide(description: "视点人物在本场立刻要取得的具体结果")
    var characterGoal: String
    @Guide(description: "具体的人、规则、物理条件或信息差如何阻止目标")
    var obstacle: String
    @Guide(description: "可见或可听的事件如何改变策略、信息或权力")
    var turn: String
    @Guide(description: "离场时人物具体得到、失去、决定或知道了什么")
    var outcome: String
    @Guide(description: "这个结果如何迫使后一个场景发生")
    var nextPressure: String
    @Guide(description: "本场不可再分核心变化的维度，只能是：世界事实、认知与信念、目标与策略、关系与权力、承诺与规范、观众认知")
    var stateDimension: String
    @Guide(description: "被改变的具体状态对象")
    var stateSubject: String
    @Guide(description: "变化发生前已成立的状态")
    var beforeState: String
    @Guide(description: "变化完成后必须成立的状态，不能与变化前相同")
    var afterState: String
    @Guide(description: "本场结束时观众比入场时新增、修正或失去的理解")
    var audienceUpdate: String
    @Guide(description: "为了保护固定结构和后续因果，本场绝不能提前改变的事实、认知、目标、关系或承诺")
    var forbiddenChanges: [String]
}

@Generable
nonisolated private struct SceneChoiceSetDraft {
    @Guide(
        description: "恰好四个完整、具体、执行机制真正不同，但都完成同一场景槽位任务的方案",
        .count(4)
    )
    var options: [SceneChoiceAIDraft]
}

@MainActor
enum SceneChoiceEngine {
    static func sourceContext(
        for contract: SceneContract,
        project: StoryProject
    ) throws -> SceneChoiceSourceContext {
        let document = project.nsirWorkspace
        let transitionIndex = document.transitions.firstIndex { $0.id == contract.id }
        let isNSIRSource = contract.sourceKindRawValue
            == SceneContractSourceKind.nsirTransition.rawValue

        if isNSIRSource || transitionIndex != nil {
            guard !contract.sourceIsMissing,
                  let transitionIndex,
                  document.transitions.indices.contains(transitionIndex) else {
                throw SceneChoiceError.unresolvedSource
            }
            let transition = document.transitions[transitionIndex]
            let nextTransition = document.transitions.indices.contains(transitionIndex + 1)
                ? document.transitions[transitionIndex + 1]
                : nil
            let stateChanges = transition.effects.map {
                "\($0.dimension.rawValue)·\($0.subject)：\($0.beforeValue) → \($0.afterValue)"
            }.joined(separator: "；")
            let audienceUpdate = transition.effects
                .filter(\.audienceObserves)
                .map { "\($0.subject)：\($0.afterValue)" }
                .joined(separator: "；")
            let costs = transition.cost.map {
                [$0.title, $0.detail]
                    .filter { !$0.trimmed.isEmpty }
                    .joined(separator: "：")
            }.joined(separator: "；")
            let resistance = transition.resistance.joined(separator: "；")
            let functions = transition.dramaticFunctions
                .map(\.rawValue)
                .sorted()
                .joined(separator: "、")
            let fallbackNextPressure = [
                nextTransition?.trigger?.summary ?? "",
                nextTransition?.intention ?? "",
                costs,
                contract.nextPressure
            ]
            .first { !$0.trimmed.isEmpty } ?? "本场是当前因果链的终点"

            return SceneChoiceSourceContext(
                kind: .nsirTransition,
                hierarchyLabel: "来自已提交结构转移",
                sourceBadge: contract.sourceIsDetached
                    ? "来自已提交结构转移 · 已保留作者修改"
                    : "来自已提交结构转移",
                promptBlock: """
                第 \(transitionIndex + 1)/\(document.transitions.count) 个已提交结构转移
                标题：\(transition.title)
                戏剧功能：\(functions.nonemptyFallback)
                触发：\(transition.trigger?.summary.nonemptyFallback ?? "由前序因果触发")
                行动者：\(transition.actorName.nonemptyFallback)
                意图：\(transition.intention.nonemptyFallback)
                策略：\([transition.tactic.verb, transition.tactic.method]
                    .filter { !$0.trimmed.isEmpty }
                    .joined(separator: " · ").nonemptyFallback)
                阻力：\(resistance.nonemptyFallback)
                状态契约：\(stateChanges.nonemptyFallback)
                观众更新：\(audienceUpdate.nonemptyFallback)
                必须付出：\(costs.nonemptyFallback)
                禁止改写：作者锁定命题、当前转移状态契约以及尚未发生的后续转移
                """,
                fallbackNextPressure: fallbackNextPressure,
                creativeStageIndex: nil
            )
        }

        guard let stageIndex = contract.structureStageIndex,
              let decision = project.decisions.first(where: {
                  $0.stageIndex == stageIndex && $0.selectedOptionID != nil
              }),
              let selected = decision.selectedOption else {
            throw SceneChoiceError.unresolvedSource
        }
        let stateChanges = selected.plannedStateChanges?.map {
            "\($0.dimension.rawValue)·\($0.subject)：\($0.beforeValue) → \($0.afterValue)"
        }.joined(separator: "；") ?? "旧项目尚未结构化"

        return SceneChoiceSourceContext(
            kind: .confirmedStage,
            hierarchyLabel: "第 \(stageIndex + 1) 大节拍 · \(decision.stageName)",
            sourceBadge: "来自第 2 层已确认大节拍",
            promptBlock: """
            第 \(stageIndex + 1) 大节拍 · \(decision.stageName)
            \(selected.title)：\(selected.pitch)
            具体抓手：\(selected.concreteDetail)
            必须付出：\(selected.consequence)
            大节拍状态契约：\(stateChanges)
            大节拍观众更新：\(selected.audienceUpdate ?? "待明确")
            大节拍禁止提前变化：\(selected.forbiddenChanges?.joined(separator: "；") ?? "无")
            """,
            fallbackNextPressure: selected.futurePressure,
            creativeStageIndex: stageIndex
        )
    }

    static func canGenerateOptions(
        for contract: SceneContract,
        project: StoryProject
    ) -> Bool {
        (try? sourceContext(for: contract, project: project)) != nil
    }

    static func planScopes(
        for decision: StoryDecision,
        project: StoryProject,
        configuration: AIConfiguration
    ) async throws -> [SceneScopeDraft] {
        guard let selected = decision.selectedOption else {
            throw SceneChoiceError.unresolvedStage
        }
        let stage = project.structureTemplate.stages.indices.contains(decision.stageIndex)
            ? project.structureTemplate.stages[decision.stageIndex]
            : nil
        let session = StoryLanguageRuntime.session(
            configuration: executionConfiguration(configuration),
            instructions: """
            你是大节拍到场景的拆分器。作者已经确认一个大节拍；你只能把这个大节拍
            拆成一至四个有因果顺序的场景，不能增加支线、替换作者选择或改动
            已锁定结构。一个槽位只承担一次关键状态变化。槽位是第三层的范围，不是完整
            场景，也不是四选一方案。若一个场景足以兑现大节拍，就只返回一个。
            """
        )
        let response = try await session.respond(
            to: """
            【锁定结构】
            \(project.structureTemplate.name)
            \(project.structureRulesForPrompt)

            【已确认大节拍】
            第 \(decision.stageIndex + 1) 大节拍 · \(decision.stageName)
            功能：\(stage?.purpose ?? "")
            作者选择：\(selected.title)
            \(selected.pitch)
            具体抓手：\(selected.concreteDetail)
            代价：\(selected.consequence)
            后续压力：\(selected.futurePressure)
            大节拍必须实现的状态差异：
            \(selected.plannedStateChanges?.map { "\($0.dimension.rawValue)·\($0.subject)：\($0.beforeValue) → \($0.afterValue)" }.joined(separator: "\n") ?? "旧项目尚未结构化")
            观众离场认知：\(selected.audienceUpdate ?? "待明确")
            不得提前改变：\(selected.forbiddenChanges?.joined(separator: "；") ?? "无")

            【此前已确认路径】
            \(project.storyPathText)

            【项目事实】
            \(project.projectSummary)
            \(project.storyBibleDigest)
            \(project.protectedCreativeContext(for: decision.stageIndex))

            把这一大节拍拆成必要且最少的一至四个场景。按发生顺序返回。
            """,
            generating: SceneScopeSetDraft.self,
            options: GenerationOptions(
                temperature: 0.32,
                maximumResponseTokens: 2_400
            )
        )
        let scopes = response.content.scenes.map {
            SceneScopeDraft(
                title: $0.title.trimmed,
                purpose: $0.purpose.trimmed,
                entryState: $0.entryState.trimmed,
                exitState: $0.exitState.trimmed
            )
        }
        guard (1...4).contains(scopes.count),
              scopes.allSatisfy({ !$0.title.isEmpty && !$0.purpose.isEmpty && !$0.exitState.isEmpty }) else {
            throw SceneChoiceError.invalidScopeCount
        }
        return scopes
    }

    static func generateOptions(
        for contract: SceneContract,
        project: StoryProject,
        configuration: AIConfiguration
    ) async throws -> [SceneChoiceOption] {
        let source = try sourceContext(for: contract, project: project)
        let ordered = project.sceneContracts.sorted { $0.sceneIndex < $1.sceneIndex }
        let currentIndex = ordered.firstIndex { $0.id == contract.id }
        let previous = currentIndex.flatMap { $0 > 0 ? ordered[$0 - 1] : nil }
        let next = currentIndex.flatMap { $0 + 1 < ordered.count ? ordered[$0 + 1] : nil }
        let session = StoryLanguageRuntime.session(
            configuration: executionConfiguration(configuration),
            instructions: """
            你是第三层场景方案执行器。作者已确认大节拍和当前场景任务；你必须返回
            恰好四个完整场景方案。四个方案都要完成同一个槽位的进入状态、叙事任务和
            离开状态，差异只能来自人物策略、关系压力、信息揭示、空间运用或事件机制。
            每个方案必须明确 before → after 状态差异，并区分人物认知与观众认知。
            场景长度、句子数量和情绪强度都不能替代状态变化。
            不得改变大节拍，不得新增支线，不得把分析意见写进场景内容。
            """
        )
        let response = try await session.respond(
            to: """
            【项目】
            \(project.projectSummary)
            \(project.storyBibleDigest)

            【已确认结构来源】
            \(source.promptBlock)

            【当前场景范围】
            场景 \(contract.stageSceneOrdinal) · \(contract.scopeTitle)
            任务：\(contract.scopePurpose)
            进入状态：\(contract.scopeEntryState)
            离开状态：\(contract.scopeExitState)

            【相邻范围】
            上一场离开：\(previous?.scopeExitState.nonemptyFallback ?? "本场是当前因果链的起点")
            下一场进入：\(next?.scopeEntryState.nonemptyFallback ?? source.fallbackNextPressure.nonemptyFallback)

            【作者创意】
            \(project.protectedCreativeContext(for: source.creativeStageIndex))

            返回恰好四个可以直接确认的场景方案。每个方案都必须包含可拍摄的地点时间、
            视点、即时目标、具体阻碍、可见转折、离场结果、下一场压力、核心状态差异、
            观众认知更新，以及为了后续结构不能提前发生的变化。
            """,
            generating: SceneChoiceSetDraft.self,
            options: GenerationOptions(
                temperature: 0.72,
                maximumResponseTokens: 4_800
            )
        )
        let options = response.content.options.map {
            SceneChoiceOption(
                title: $0.title.trimmed,
                approach: $0.approach.trimmed,
                heading: $0.heading.trimmed,
                pointOfView: $0.pointOfView.trimmed,
                characterGoal: $0.characterGoal.trimmed,
                obstacle: $0.obstacle.trimmed,
                turn: $0.turn.trimmed,
                outcome: $0.outcome.trimmed,
                nextPressure: $0.nextPressure.trimmed,
                requiredStateChanges: [
                    DramaticStateMutation(
                        dimension: semanticDimension($0.stateDimension),
                        subject: $0.stateSubject.trimmed,
                        beforeValue: $0.beforeState.trimmed,
                        afterValue: $0.afterState.trimmed,
                        observerNames: ["观众"]
                    )
                ],
                audienceUpdate: $0.audienceUpdate.trimmed,
                forbiddenChanges: $0.forbiddenChanges.map(\.trimmed).filter { !$0.isEmpty }
            )
        }
        guard options.count == 4,
              Set(options.map(\.title)).count == 4,
              options.allSatisfy(\.isComplete) else {
            throw SceneChoiceError.invalidOptions
        }
        return options
    }

    private static func executionConfiguration(_ configuration: AIConfiguration) -> AIConfiguration {
        configuration.withThinkingEnabled(false)
    }

    private static func semanticDimension(_ value: String) -> DramaticStateDimension {
        let clean = value.trimmed
        return DramaticStateDimension.allCases.first {
            clean.contains($0.rawValue) || $0.rawValue.contains(clean)
        } ?? .world
    }
}

private extension SceneChoiceOption {
    var isComplete: Bool {
        [title, heading, pointOfView, characterGoal, obstacle, turn, outcome, nextPressure]
            .allSatisfy { !$0.trimmed.isEmpty }
            && requiredStateChanges?.contains(where: \.isEffective) == true
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nonemptyFallback: String {
        trimmed.isEmpty ? "未指定" : trimmed
    }
}

enum SceneChoiceError: LocalizedError {
    case unresolvedStage
    case unresolvedSource
    case invalidScopeCount
    case invalidOptions

    var errorDescription: String? {
        switch self {
        case .unresolvedStage:
            "这个大节拍尚未完成确认。"
        case .unresolvedSource:
            "这个场景没有可用的已提交结构转移或已确认大节拍。"
        case .invalidScopeCount:
            "DeepSeek 没有返回一至四个完整场景。"
        case .invalidOptions:
            "DeepSeek 没有返回恰好四个完整且不同的场景方案。"
        }
    }
}
