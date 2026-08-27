import Foundation
import FoundationModels

enum ScreenplayGenerationMode: String, CaseIterable, Identifiable {
    case draft = "起草本场"
    case continueWriting = "继续写"
    case dialogue = "强化对白"
    case visualAction = "视觉化动作"
    case pressure = "增加压力"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .draft: "wand.and.stars"
        case .continueWriting: "text.append"
        case .dialogue: "quote.bubble.fill"
        case .visualAction: "camera.fill"
        case .pressure: "bolt.fill"
        }
    }

    var instruction: String {
        switch self {
        case .draft:
            "依据作者已确认的场景与小节拍润色完整场景。保持小节拍顺序、行动、结果和事实不变。"
        case .continueWriting:
            "保留已有内容与语气，从当前停笔处继续，直到本场兑现转折和离场钩子。返回包含原文的完整场景。"
        case .dialogue:
            "保留事件和因果，重写整场对白。每个人说话方式不同，减少信息直说，用行动、回避和潜台词表达欲望。"
        case .visualAction:
            "保留事件和对白，强化可拍摄动作、空间关系、物件使用和人物反应，删除无法被镜头看见的心理说明。"
        case .pressure:
            "保留已确定事实，增加对手的主动策略、时间压力和选择代价，让转折由人物行动造成。"
        }
    }
}

struct ScreenplaySceneAIResult {
    let fountainText: String
    let scenePurpose: String
    let emotionalTurn: String
    let beatSummary: [String]
    let continuityWarnings: [String]
    let choicesForAuthor: [String]
    let structureAnchor: String
    let knowledgeSources: [String]

    init(
        fountainText: String,
        scenePurpose: String,
        emotionalTurn: String,
        beatSummary: [String],
        continuityWarnings: [String],
        choicesForAuthor: [String],
        structureAnchor: String = "",
        knowledgeSources: [String] = []
    ) {
        self.fountainText = FountainParser.localizingSceneHeadings(
            in: fountainText
        )
        self.scenePurpose = scenePurpose
        self.emotionalTurn = emotionalTurn
        self.beatSummary = beatSummary
        self.continuityWarnings = continuityWarnings
        self.choicesForAuthor = choicesForAuthor
        self.structureAnchor = structureAnchor
        self.knowledgeSources = knowledgeSources
    }
}

@Generable
nonisolated private struct ScreenplaySceneGenerationDraft {
    var fountainText: String
    var scenePurpose: String
    var emotionalTurn: String

    @Guide(description: "按作者已确认的小节拍顺序概括执行结果，不得另造小节拍")
    var beatSummary: [String]

    var continuityWarnings: [String]

    @Guide(description: "只有会改变人物选择、事实边界或全片方向时才列出，最多三项")
    var choicesForAuthor: [String]
}

@Generable
nonisolated private struct ScreenplaySceneOptionGenerationDraft {
    @Guide(description: "八到十六字的方案名，直接体现本方案的独特写法")
    var title: String

    @Guide(description: "说明本方案的动作、对白或空间执行机制，以及它与另外两个方案的根本区别")
    var approach: String

    var fountainText: String
    var scenePurpose: String
    var emotionalTurn: String

    @Guide(description: "按作者已确认的小节拍顺序概括执行结果，不得另造小节拍")
    var beatSummary: [String]

    var continuityWarnings: [String]

    @Guide(description: "只有会改变人物选择、事实边界或全片方向时才列出，最多三项")
    var choicesForAuthor: [String]
}

@Generable
nonisolated private struct ScreenplaySceneOptionSetGenerationDraft {
    @Guide(
        description: "恰好三个完整的 Final Draft/Fountain 场景方案；都必须执行同一场景契约和已确认小节拍，但动作机制、对白策略或空间调度必须真正不同",
        .count(3)
    )
    var options: [ScreenplaySceneOptionGenerationDraft]
}

private struct ScreenplayGenerationContext {
    let projectContext: String
    let structureContext: String
    let structureAnchorLabel: String
    let realityContext: String
    let theoryContext: String
    let knowledgeSourceLabels: [String]
    let storyDNAContext: String
    let allScenePlan: String
    let upstreamSignature: String
    let sceneCard: String
    let previousScene: String
    let currentScene: String
    let nextSceneCard: String
    let mode: ScreenplayGenerationMode
    let length: ScreenplaySceneLength
    let authorInstruction: String
}

@MainActor
struct ScreenplayWritingEngine {
    let settings: AISettingsStore

    func generate(
        project: StoryProject,
        scene: FountainSceneSnapshot,
        sceneContractID: UUID? = nil,
        nextSceneContractID: UUID? = nil,
        sceneCard: SceneCardReference?,
        nextSceneCard: SceneCardReference?,
        mode: ScreenplayGenerationMode,
        length: ScreenplaySceneLength,
        authorInstruction: String
    ) async throws -> ScreenplaySceneAIResult {
        let context = await generationContext(
            project: project,
            scene: scene,
            sceneContractID: sceneContractID,
            nextSceneContractID: nextSceneContractID,
            sceneCard: sceneCard,
            nextSceneCard: nextSceneCard,
            mode: mode,
            length: length,
            authorInstruction: authorInstruction
        )
        return try await ScreenplayDeepSeekService(
            configuration: settings.configuration()
        ).generate(context)
    }

    func generateOptions(
        project: StoryProject,
        scene: FountainSceneSnapshot,
        sceneContractID: UUID? = nil,
        nextSceneContractID: UUID? = nil,
        sceneCard: SceneCardReference?,
        nextSceneCard: SceneCardReference?,
        mode: ScreenplayGenerationMode,
        length: ScreenplaySceneLength,
        authorInstruction: String
    ) async throws -> [ScreenplaySceneDraftOption] {
        let context = await generationContext(
            project: project,
            scene: scene,
            sceneContractID: sceneContractID,
            nextSceneContractID: nextSceneContractID,
            sceneCard: sceneCard,
            nextSceneCard: nextSceneCard,
            mode: mode,
            length: length,
            authorInstruction: authorInstruction
        )
        return try await ScreenplayDeepSeekService(
            configuration: settings.configuration()
        ).generateOptions(context)
    }

    private func generationContext(
        project: StoryProject,
        scene: FountainSceneSnapshot,
        sceneContractID: UUID?,
        nextSceneContractID: UUID?,
        sceneCard: SceneCardReference?,
        nextSceneCard: SceneCardReference?,
        mode: ScreenplayGenerationMode,
        length: ScreenplaySceneLength,
        authorInstruction: String
    ) async -> ScreenplayGenerationContext {
        let allScenes = FountainParser.scenes(in: project.screenplayText)
        let previousScene = scene.index > 0
            ? String(allScenes[scene.index - 1].text.suffix(2_000))
            : "这是全片第一场。"
        let contracts = project.sceneContracts.sorted { $0.sceneIndex < $1.sceneIndex }
        let contract = sceneContractID.flatMap { contractID in
            contracts.first { $0.id == contractID }
        }
        let nextContract = nextSceneContractID.flatMap { contractID in
            contracts.first { $0.id == contractID }
        } ?? contract.flatMap { current in
            guard let index = contracts.firstIndex(where: { $0.id == current.id }),
                  index + 1 < contracts.count else { return nil }
            return contracts[index + 1]
        }
        let structureAnchor = ScreenplayProductionContextBuilder.anchor(
            for: contract,
            in: project
        )
        let structureContext = ScreenplayProductionContextBuilder
            .fullStructureTrack(for: project)

        let rawProjectContext = """
        项目：\(project.title)
        类型：\(project.genre.rawValue)
        项目创作方向与后来注入：\(project.creativeContext())
        一句话：\(project.logline)
        戏剧问题：\(project.dramaticPromise)
        核心冲突：\(project.coreConflictText)
        主题：\(project.themeText)
        世界规则：\(project.worldText)
        动态剧本圣经：
        \(project.storyBibleDigest)
        作者总笔记：\(project.notes)
        结构路线：\(project.structureText)
        已确认故事路径：\(project.storyPathText)
        人物：
        \(project.characters.map {
            "\($0.role.rawValue) \($0.name)：\($0.seedText)；目标 \($0.externalGoal)；需求 \($0.internalNeed)；恐惧 \($0.fear)；错误信念 \($0.falseBelief)"
        }.joined(separator: "\n"))
        全本场景路线：
        \(String(project.scenesText.prefix(9_000)))
        项目内经作者确认的创作卡：
        \(project.artifacts
            .filter { $0.status == .integrated }
            .sorted { $0.sortIndex < $1.sortIndex }
            .map { "【\($0.kind.rawValue) · \($0.title)】\n\($0.acceptedText)" }
            .joined(separator: "\n\n"))
        \(ProjectPreferenceEngine.promptBlock(for: project))
        """
        let prepared = await AppleTextService.prepareForAnalysis(
            rawProjectContext,
            enabled: settings.useApplePreprocessing
        )
        let protectedProjectContext = """
        \(prepared.text)

        \(project.protectedCreativeContext(for: nil))
        """
        let query = ScreenplayProductionContextBuilder.retrievalQuery(
            project: project,
            scene: scene,
            contract: contract,
            task: mode.rawValue
        )
        let theory: [TheoryEvidence]
        if settings.useKnowledgeBase {
            theory = (try? await TheoryIndexStore.shared.search(
                query: query,
                route: TheoryRouting.route(for: .screenplay),
                maximumMatches: 5,
                maximumCharacters: 2_600
            )) ?? []
        } else {
            theory = []
        }
        let cases = StoryDNAService.shared.matches(
            query: query,
            genre: project.genre.rawValue,
            limit: 3
        )
        let reality = project.sourceText.contains("【现实资料包】")
            ? String(project.sourceText.prefix(7_000))
            : project.sourceFacts
        let allScenePlan = contracts
            .map { contractBlock($0, project: project) }
            .joined(separator: "\n\n")

        return ScreenplayGenerationContext(
            projectContext: protectedProjectContext,
            structureContext: structureContext,
            structureAnchorLabel: structureAnchor?.label ?? "未映射结构阶段",
            realityContext: reality,
            theoryContext: theory.map(\.promptBlock).joined(separator: "\n\n"),
            knowledgeSourceLabels: theory.map(\.sourceLabel),
            storyDNAContext: cases.map(\.promptBlock).joined(separator: "\n\n"),
            allScenePlan: String(allScenePlan.prefix(18_000)),
            upstreamSignature: ScreenplayProjectionEngine.sourceSignature(
                for: project
            ),
            sceneCard: contract.map { contractBlock($0, project: project) }
                ?? sceneCard?.promptBlock
                ?? "场景标题：\(scene.heading)",
            previousScene: previousScene,
            currentScene: scene.text,
            nextSceneCard: nextContract.map {
                contractBlock($0, project: project)
            }
                ?? nextSceneCard?.promptBlock
                ?? "这是最后一场，必须留下完整余味。",
            mode: mode,
            length: length,
            authorInstruction: authorInstruction
        )
    }

    private func contractBlock(
        _ contract: SceneContract,
        project: StoryProject
    ) -> String {
        let microBeats = contract.microBeats
            .sorted()
            .compactMap { beat -> String? in
                guard let selected = beat.selectedOption else { return nil }
                return """
                小节拍 \(beat.ordinal) · \(beat.purpose)
                作者选择：\(selected.title)
                戏剧动作：\(selected.dramaticAction)
                结果：\(selected.outcome)
                状态差异：\(selected.stateChanges?.map { "\($0.dimension.rawValue)·\($0.subject)：\($0.beforeValue) → \($0.afterValue)" }.joined(separator: "；") ?? "沿用旧版小节拍描述")
                观众更新：\(selected.audienceUpdate ?? "待正文自然实现")
                已确认文本：\(selected.screenplayText)
                """
            }
            .joined(separator: "\n")
        return """
        【结构锚点】
        \(ScreenplayProductionContextBuilder.anchor(for: contract, in: project)?.promptBlock ?? "当前场景尚未建立结构锚点。")

        场 \(contract.sceneIndex)：\(contract.heading)
        视点：\(contract.pointOfView)
        即时目标：\(contract.characterGoal)
        阻碍：\(contract.obstacle)
        转折：\(contract.turn)
        结果：\(contract.outcome)
        下一场压力：\(contract.nextPressure)
        进入状态：\(contract.stateContract.entrySnapshot)
        必须实现：\(contract.stateContract.requiredChanges.map { "\($0.dimension.rawValue)·\($0.subject)：\($0.beforeValue) → \($0.afterValue)" }.joined(separator: "；"))
        观众离场认知：\(contract.stateContract.audienceOutcome)
        禁止提前改变：\(contract.stateContract.forbiddenChanges.joined(separator: "；"))

        【已确认小节拍 · 不得改变顺序或事实】
        \(microBeats.isEmpty ? "尚未确认小节拍" : microBeats)
        """
    }
}

@MainActor
private struct ScreenplayDeepSeekService {
    let configuration: AIConfiguration

    func generate(
        _ context: ScreenplayGenerationContext
    ) async throws -> ScreenplaySceneAIResult {
        let session = StoryLanguageRuntime.session(
            configuration: configuration,
            instructions: instructions(for: context, optionSet: false)
        )
        let response = try await session.respond(
            to: prompt(for: context, optionSet: false),
            generating: ScreenplaySceneGenerationDraft.self,
            options: GenerationOptions(
                temperature: context.mode == .dialogue ? 0.58 : 0.35,
                maximumResponseTokens: maxTokens(for: context.length)
            )
        )
        let draft = response.content
        return ScreenplaySceneAIResult(
            fountainText: draft.fountainText,
            scenePurpose: draft.scenePurpose,
            emotionalTurn: draft.emotionalTurn,
            beatSummary: draft.beatSummary,
            continuityWarnings: draft.continuityWarnings,
            choicesForAuthor: Array(draft.choicesForAuthor.prefix(3)),
            structureAnchor: context.structureAnchorLabel,
            knowledgeSources: context.knowledgeSourceLabels
        )
    }

    func generateOptions(
        _ context: ScreenplayGenerationContext
    ) async throws -> [ScreenplaySceneDraftOption] {
        let session = StoryLanguageRuntime.session(
            configuration: configuration,
            instructions: instructions(for: context, optionSet: true)
        )
        let response = try await session.respond(
            to: prompt(for: context, optionSet: true),
            generating: ScreenplaySceneOptionSetGenerationDraft.self,
            options: GenerationOptions(
                temperature: context.mode == .dialogue ? 0.68 : 0.55,
                maximumResponseTokens: optionMaxTokens(for: context.length)
            )
        )
        let sourceFingerprint = ScreenplayDraftOptionPolicy.fingerprint(
            context.currentScene
        )
        let options = response.content.options.map { draft in
            ScreenplaySceneDraftOption(
                title: draft.title.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                approach: draft.approach.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                fountainText: draft.fountainText,
                scenePurpose: draft.scenePurpose,
                emotionalTurn: draft.emotionalTurn,
                beatSummary: draft.beatSummary,
                continuityWarnings: draft.continuityWarnings,
                choicesForAuthor: Array(draft.choicesForAuthor.prefix(3)),
                modeRawValue: context.mode.rawValue,
                sourceSceneFingerprint: sourceFingerprint,
                sourceUpstreamSignature: context.upstreamSignature,
                structureAnchor: context.structureAnchorLabel,
                knowledgeSources: context.knowledgeSourceLabels
            )
        }
        guard ScreenplayDraftOptionPolicy.isValidSet(options) else {
            throw ScreenplayWritingError.invalidOptionSet
        }
        return options
    }

    private func instructions(
        for context: ScreenplayGenerationContext,
        optionSet: Bool
    ) -> String {
        let optionRule = optionSet
            ? "必须交付恰好三个完整方案。三个方案完成相同场景契约与小节拍，但应分别通过不同的动作机制、对白策略或空间调度来实现，不能只是换词。"
            : "交付一个可审阅的完整场景。"
        return """
        你是剧本场景执行器，不是创意作者。作者的创意、固定结构、场景与已确认小节拍是硬约束。
        你必须阅读全片所有场景路线，遵守人物、世界、现实证据和前后场连续性，不得新增剧情方向、人物、主题或设定。
        你的职责是把前序工作落实为专业剧本正文；不得跳过、重排或替换作者选择的场景和小节拍。
        必须把当前场的目标、阻力和状态差异写成可拍的动作与对白，同时只完成它在全片结构轨道中的局部职责。
        RAG 理论证据只用来检验和改善执行方法，不得覆盖作者已确认的事实、选择、结构或人物动机。
        只有真正会改变人物选择、事实边界或全片方向的问题，才放入 choicesForAuthor；即使存在这些问题，也要先交付可审阅的完整场景。
        \(optionRule)
        当前任务：\(context.mode.instruction)
        长度目标：\(context.length.prompt)

        剧本使用 Fountain（可直接进入 Final Draft 工作流）：
        1. 场景标题只使用中文“内. 地点 - 日/夜”“外. 地点 - 日/夜”或“内/外. 地点 - 日/夜”，不得使用 INT.、EXT.。
        2. 动作使用现在时，只写镜头能够看见或听见的内容。
        3. 中文人物提示使用“@人物名”，下一行直接写对白。
        4. 括号提示极少使用；转场只在真正必要时使用。
        5. 不写小说式心理解释，不堆砌形容词，不用对白重复观众已经知道的信息。
        6. 每场必须有人物目标、对抗、策略变化、情绪转向和不可撤销的新局面。
        7. 现实资料只能作为质感与约束；未确认的真实人物动机不得当作事实。
        8. 剧本的最小功能单位是情境更新。每个已确认状态差异必须由可见或可听的行动、言语行为、感知、沉默、声音或事件真正造成。
        9. 严格区分世界事实、人物知道或相信什么，以及观众知道什么；不得提前实现状态契约明确禁止的变化。
        返回 Foundation Models 强类型结果。
        """
    }

    private func prompt(
        for context: ScreenplayGenerationContext,
        optionSet: Bool
    ) -> String {
        let completionRule = optionSet
            ? "返回恰好三个各自完整的场景正文。每个方案都必须从场景标题开始，能独立替换当前场。"
            : "返回修改后的完整场景，而不是只返回新增段落。"
        return """
        【项目圣经】
        \(context.projectContext)

        【全本结构执行轨道 · 必须保持】
        \(context.structureContext)

        【全片所有场景路线 · 必须整体阅读】
        \(context.allScenePlan.isEmpty ? "沿用项目圣经中的全本场景路线。" : context.allScenePlan)

        【现实资料】
        \(context.realityContext.isEmpty ? "没有独立现实资料包。" : context.realityContext)

        【当前场景与已确认小节拍】
        \(context.sceneCard)

        【上一场结尾】
        \(context.previousScene)

        【当前已有场景】
        \(context.currentScene)

        【下一场需要承接】
        \(context.nextSceneCard)

        【专业理论】
        \(context.theoryContext.isEmpty ? "没有命中理论片段。" : context.theoryContext)

        【经典作品的叙事功能参考】
        \(context.storyDNAContext.isEmpty ? "没有匹配案例。" : context.storyDNAContext)

        【作者本轮要求】
        \(context.authorInstruction.isEmpty ? "遵循已确认场景与小节拍完成本轮任务。" : context.authorInstruction)

        \(completionRule)
        """
    }

    private func maxTokens(for length: ScreenplaySceneLength) -> Int {
        switch length {
        case .compact: 2_800
        case .standard: 4_800
        case .extended: 6_800
        }
    }

    private func optionMaxTokens(for length: ScreenplaySceneLength) -> Int {
        switch length {
        case .compact: 7_200
        case .standard: 13_500
        case .extended: 19_000
        }
    }

}

enum ScreenplayWritingError: LocalizedError {
    case invalidResponse
    case invalidOptionSet
    case noScenes
    case missingAPIKey
    case unlockedStructure
    case missingSceneMapping
    case incompleteSmallBeats
    case incompleteProfessionalScene

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "AI 没有返回可读取的场景。"
        case .invalidOptionSet:
            "AI 没有返回三个可独立替换当前场的完整 Final Draft/Fountain 方案，请重试。"
        case .noScenes:
            "请先在前序工作区完成至少一个场景。"
        case .missingAPIKey:
            "请先在 AI 设置中配置 DeepSeek 或硅基流动 API。"
        case .unlockedStructure:
            "请先锁定全本结构，再把每场结构职责编译为最终正文。"
        case .missingSceneMapping:
            "结构已经锁定，但还没有完整场景映射。请先在场景工作台把结构阶段拆成场景。"
        case .incompleteSmallBeats:
            "请先确认全部场景的小节拍，再进入最终剧本写作。"
        case .incompleteProfessionalScene:
            "AI 返回的场景仍包含结构注释或占位内容，未写成可独立交付的完整剧本场景。"
        }
    }
}
