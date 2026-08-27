import Foundation
import FoundationModels

@Generable
nonisolated private struct DramaticMutationAIDraft {
    @Guide(description: "只能是：世界事实、认知与信念、目标与策略、关系与权力、承诺与规范、观众认知")
    var dimension: String
    @Guide(description: "被改变的具体事实、信念、目标、关系、规范或观众理解")
    var subject: String
    @Guide(description: "认知或目标属于谁；不适用时写空字符串")
    var holder: String
    @Guide(description: "更新发生之前的状态；原文无法确定时写未知")
    var beforeValue: String
    @Guide(description: "更新发生之后可以从正文得到的状态")
    var afterValue: String
    @Guide(description: "只能是：事实、人物相信、错误信念、怀疑、预期")
    var truthStatus: String
    @Guide(description: "知道或目睹该变化的人物；观众知道时必须包含观众")
    var observers: [String]
}

@Generable
nonisolated private struct DramaticUpdateAIDraft {
    @Guide(description: "只能是：对白、动作、沉默、感知、揭示、声音、空间关系、事件")
    var carrier: String
    @Guide(description: "一个能够说明人物借此做了什么的行动性动词，例如拒绝、威胁、识破、撤销、服从")
    var actionVerb: String
    @Guide(description: "行动者；无人行动的外部事件可写环境")
    var actor: String
    @Guide(description: "被施加作用的人物、关系、物件或状态")
    var target: String
    @Guide(description: "行动者试图改变什么")
    var intention: String
    @Guide(description: "此行动遭遇的直接反作用；没有时写无直接阻力")
    var resistance: String
    @Guide(description: "碰撞后真正成立的新局面")
    var outcome: String
    @Guide(description: "一句关系性谓词总结，例如她通过归还戒指撤销婚姻承诺")
    var summary: String
    @Guide(description: "必须逐字来自当前场景、能够覆盖本次更新的最短连续原文；可以跨越多段")
    var sourceQuote: String
    @Guide(description: "本次不可分更新产生的一项或多项状态差异")
    var mutations: [DramaticMutationAIDraft]
    @Guide(description: "0到1，原文对该解释的支持程度")
    var confidence: Double
    @Guide(description: "0到1，对本场和全片因果的相对重要度")
    var salience: Double
    @Guide(description: "0到1，更新发生后难以恢复原状的程度")
    var irreversibility: Double
}

@Generable
nonisolated private struct DramaticSceneAnalysisAIDraft {
    @Guide(description: "正文实际实现的、按发生顺序排列的最少必要情境更新；允许为空")
    var updates: [DramaticUpdateAIDraft]
    @Guide(description: "只依据这些更新概括本场从何状态进入、以何状态离开")
    var realizedSceneSummary: String
    @Guide(description: "边界、歧义、计划未兑现或观众与人物认知混淆问题；没有则为空数组")
    var warnings: [String]
}

nonisolated struct DramaticAnalyzedUpdate: Sendable {
    let carrier: DramaticCarrier
    let actionVerb: String
    let actor: String
    let target: String
    let intention: String
    let resistance: String
    let outcome: String
    let summary: String
    let sourceQuote: String
    let mutations: [DramaticStateMutation]
    let confidence: Double
    let salience: Double
    let irreversibility: Double
}

nonisolated struct DramaticSceneAnalysis: Sendable {
    let updates: [DramaticAnalyzedUpdate]
    let realizedSceneSummary: String
    let warnings: [String]
    let modelLabel: String
}

@MainActor
enum DramaticSemanticEngine {
    static func analyze(
        sceneText: String,
        sceneContract: SceneContract?,
        project: StoryProject,
        settings: AISettingsStore
    ) async throws -> DramaticSceneAnalysis {
        let clean = sceneText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw DramaticSemanticError.emptyScene }

        let prompt = analysisPrompt(
            sceneText: clean,
            sceneContract: sceneContract,
            project: project
        )

        // DeepSeek is the primary reasoning provider. Apple Foundation Models
        // may still compact long context elsewhere, but its local intelligence
        // is not used to adjudicate NSIR or dramatic semantics.
        if settings.hasAPIKey {
            let configuration = try settings.configuration()
            let executionConfiguration = configuration.withThinkingEnabled(false)
            let session = StoryLanguageRuntime.session(
                configuration: executionConfiguration,
                instructions: semanticInstructions
            )
            let response = try await session.respond(
                to: prompt,
                generating: DramaticSceneAnalysisAIDraft.self,
                options: GenerationOptions(
                    temperature: 0.16,
                    maximumResponseTokens: 7_000
                )
            )
            return validated(
                response.content,
                sourceText: clean,
                modelLabel: configuration.model
            )
        }

        return deterministicFallback(sceneText: clean, sceneContract: sceneContract)
    }

    private static let semanticInstructions = """
    你是 StoryMentor 的戏剧情境更新分析器，不是摘要器，也不是创意作者。
    剧本的最小单位是功能上不可再分的语境更新：行动、言语行为、感知、沉默、声音或事件，
    使世界事实、人物知识与信念、人物目标与策略、关系与权力、承诺与规范、观众认知中的
    至少一项发生独立变化。文字长度、句号、段落和镜头都不能决定边界。

    严格规则：
    1. 一个复句可以有两次更新；多句也可以共同完成一次更新。
    2. 纯身体动作只有在目的—关系结构中改变状态时才成立；不要把每个动作都报成更新。
    3. 同一次不可分行动可以有多个状态差异，但不能把两个独立功能合并。
    4. 必须区分人物知道什么与观众知道什么，以及事实、错误信念、怀疑和预期。
    5. sourceQuote 必须是输入正文里的连续原文，不得改写或杜撰。
    6. 不为满足数量强行拆分。没有有效变化时允许返回空数组。
    7. 只分析正文实际实现的内容；场景契约只用于比较，不得用它补写正文没有发生的事。
    返回 Foundation Models 强类型结果。
    """

    private static func analysisPrompt(
        sceneText: String,
        sceneContract: SceneContract?,
        project: StoryProject
    ) -> String {
        let contract: String
        if let sceneContract {
            contract = """
            场景目标：\(sceneContract.characterGoal)
            阻碍：\(sceneContract.obstacle)
            计划转折：\(sceneContract.turn)
            计划结果：\(sceneContract.outcome)
            进入状态：\(sceneContract.scopeEntryState)
            离开状态：\(sceneContract.scopeExitState)
            """
        } else {
            contract = "这是导入或独立创作的正文，没有预先场景契约。"
        }

        return """
        【作者锁定事实与全片方向】
        \(project.projectSummary)
        \(project.storyBibleDigest)

        【计划场景契约·只用于比较】
        \(contract)

        【当前场景正文·唯一实现证据】
        \(sceneText)

        找出按因果顺序排列、必要且最少的戏剧情境更新。先确定每次变化前后状态，再决定边界。
        """
    }

    private static func validated(
        _ draft: DramaticSceneAnalysisAIDraft,
        sourceText: String,
        modelLabel: String
    ) -> DramaticSceneAnalysis {
        var updates: [DramaticAnalyzedUpdate] = []
        var rejectedAnchorCount = 0
        for value in draft.updates {
            let mutations = value.mutations.compactMap(mutation(from:))
                .filter(\.isEffective)
            guard !value.actionVerb.semanticTrimmed.isEmpty,
                  !value.summary.semanticTrimmed.isEmpty,
                  !value.sourceQuote.semanticTrimmed.isEmpty,
                  !mutations.isEmpty else {
                continue
            }
            guard sourceText.contains(value.sourceQuote.semanticTrimmed) else {
                rejectedAnchorCount += 1
                continue
            }
            updates.append(
                DramaticAnalyzedUpdate(
                    carrier: carrier(from: value.carrier),
                    actionVerb: value.actionVerb.semanticTrimmed,
                    actor: value.actor.semanticTrimmed,
                    target: value.target.semanticTrimmed,
                    intention: value.intention.semanticTrimmed,
                    resistance: value.resistance.semanticTrimmed,
                    outcome: value.outcome.semanticTrimmed,
                    summary: value.summary.semanticTrimmed,
                    sourceQuote: value.sourceQuote.semanticTrimmed,
                    mutations: mutations,
                    confidence: unit(value.confidence),
                    salience: unit(value.salience),
                    irreversibility: unit(value.irreversibility)
                )
            )
        }
        var warnings = draft.warnings.map(\.semanticTrimmed).filter { !$0.isEmpty }
        if rejectedAnchorCount > 0 {
            warnings.append("\(rejectedAnchorCount) 项候选无法逐字锚定到正文，已拒绝入库。")
        }
        return DramaticSceneAnalysis(
            updates: updates,
            realizedSceneSummary: draft.realizedSceneSummary.semanticTrimmed,
            warnings: warnings,
            modelLabel: modelLabel
        )
    }

    private static func mutation(
        from draft: DramaticMutationAIDraft
    ) -> DramaticStateMutation? {
        let subject = draft.subject.semanticTrimmed
        let after = draft.afterValue.semanticTrimmed
        guard !subject.isEmpty, !after.isEmpty else { return nil }
        return DramaticStateMutation(
            dimension: dimension(from: draft.dimension),
            subject: subject,
            holder: draft.holder.semanticTrimmed,
            beforeValue: draft.beforeValue.semanticTrimmed,
            afterValue: after,
            truthStatus: truthStatus(from: draft.truthStatus),
            observerNames: draft.observers.map(\.semanticTrimmed).filter { !$0.isEmpty }
        )
    }

    private static func dimension(from value: String) -> DramaticStateDimension {
        let clean = value.semanticTrimmed
        return DramaticStateDimension.allCases.first {
            clean.contains($0.rawValue) || $0.rawValue.contains(clean)
        } ?? .world
    }

    private static func carrier(from value: String) -> DramaticCarrier {
        let clean = value.semanticTrimmed
        return DramaticCarrier.allCases.first {
            clean.contains($0.rawValue) || $0.rawValue.contains(clean)
        } ?? .event
    }

    private static func truthStatus(from value: String) -> DramaticTruthStatus {
        let clean = value.semanticTrimmed
        return DramaticTruthStatus.allCases.first {
            clean.contains($0.rawValue) || $0.rawValue.contains(clean)
        } ?? .fact
    }

    private static func unit(_ value: Double) -> Double {
        guard value.isFinite else { return 0.5 }
        return min(max(value, 0), 1)
    }

    private static func deterministicFallback(
        sceneText: String,
        sceneContract: SceneContract?
    ) -> DramaticSceneAnalysis {
        let paragraphs = FountainParser.paragraphs(in: sceneText)
        let signals = [
            "发现", "知道", "认出", "意识到", "承认", "揭露", "告诉", "拒绝", "同意",
            "威胁", "命令", "承诺", "原谅", "背叛", "离开", "带走", "夺走", "锁上",
            "打开", "关上", "打碎", "摘下", "放下", "交出", "死亡", "死了", "辞职",
            "分手", "开除", "投降", "服从", "逃走", "阻止"
        ]
        var updates: [DramaticAnalyzedUpdate] = []
        var previousWasCharacter = false
        var characterName = ""
        for paragraph in paragraphs {
            let text = paragraph.trimmedText
            guard !text.isEmpty, paragraph.inferredType != .sceneHeading,
                  paragraph.inferredType != .note else { continue }
            if paragraph.inferredType == .character {
                characterName = text.trimmingCharacters(
                    in: CharacterSet(charactersIn: "@^ ")
                )
                previousWasCharacter = true
                continue
            }
            let hasSignal = signals.contains { text.contains($0) }
            guard hasSignal else {
                previousWasCharacter = false
                continue
            }
            let carrier: DramaticCarrier = previousWasCharacter || paragraph.inferredType == .dialogue
                ? .dialogue
                : .action
            let verb = signals.first { text.contains($0) } ?? "改变"
            let actor = characterName.isEmpty ? "正文中的行动者" : characterName
            let dimension: DramaticStateDimension
            if ["发现", "知道", "认出", "意识到"].contains(verb) {
                dimension = .knowledge
            } else if ["承诺", "命令", "同意", "开除"].contains(verb) {
                dimension = .norm
            } else if ["拒绝", "原谅", "背叛", "分手", "服从"].contains(verb) {
                dimension = .relationship
            } else {
                dimension = .world
            }
            updates.append(
                DramaticAnalyzedUpdate(
                    carrier: carrier,
                    actionVerb: verb,
                    actor: actor,
                    target: "当前局面",
                    intention: sceneContract?.characterGoal ?? "改变当前局面",
                    resistance: "等待作者或模型进一步确认",
                    outcome: text,
                    summary: "\(actor)通过\(verb)改变当前局面",
                    sourceQuote: text,
                    mutations: [
                        DramaticStateMutation(
                            dimension: dimension,
                            subject: text,
                            holder: dimension == .knowledge ? actor : "",
                            beforeValue: "尚未发生",
                            afterValue: text,
                            truthStatus: .fact,
                            observerNames: ["观众"]
                        )
                    ],
                    confidence: 0.35,
                    salience: 0.4,
                    irreversibility: 0.35
                )
            )
            previousWasCharacter = false
        }
        return DramaticSceneAnalysis(
            updates: updates,
            realizedSceneSummary: updates.map(\.summary).joined(separator: " → "),
            warnings: ["当前使用确定性预分析；配置 DeepSeek 后可获得更完整的语义边界候选。"],
            modelLabel: "确定性预分析"
        )
    }
}

enum DramaticSemanticError: LocalizedError {
    case emptyScene
    case invalidAnalysis

    var errorDescription: String? {
        switch self {
        case .emptyScene: "当前场景没有可以分析的正文。"
        case .invalidAnalysis: "模型没有返回可验证的戏剧情境更新。"
        }
    }
}

private extension String {
    var semanticTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
