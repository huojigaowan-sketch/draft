import Foundation
import FoundationModels

@Generable
nonisolated struct CaptainAreaRevisionDraft {
    @Guide(description: "只能填写以下九个名称之一：故事前提、人物、人物关系、世界、主题、核心冲突、固定结构、场景、剧本")
    var area: String

    @Guide(description: "具体落点，例如人物姓名、大节拍、场次或现有文本位置")
    var target: String

    @Guide(description: "可以直接纳入对应故事模块的具体增量内容")
    var update: String

    @Guide(description: "这项变化会给其他区域带来的因果、情绪或连续性后果")
    var consequence: String
}

@Generable
nonisolated struct CaptainImpactMapDraft {
    var premise: Bool
    var characters: Bool
    var relationships: Bool
    var world: Bool
    var theme: Bool
    var conflict: Bool
    var structure: Bool
    var scenes: Bool
    var screenplay: Bool
}

@Generable
nonisolated struct CaptainCommandOptionDraft {
    @Guide(description: "八到十六字的方案名称")
    var title: String

    @Guide(description: "用一到两句话说明这个方案如何执行作者想法，以及与另外三个方案的根本差别")
    var strategy: String

    @Guide(description: "必须被完整保留、不能被AI稀释或替换的作者创新核心")
    var protectedCore: String

    @Guide(description: "九个故事区域的完整影响判断，每个布尔值都必须填写")
    var impactMap: CaptainImpactMapDraft

    @Guide(description: "只列出 impactMap 中为 true 的区域；area 使用规定的中文名称，每个区域恰好一项")
    var changes: [CaptainAreaRevisionDraft]

    @Guide(description: "本方案明确保持不动的作者决定、锁定事实与结构规则")
    var preservedFacts: [String]

    @Guide(description: "采用本方案后必须继续检查的因果、动机、节奏、格式或连续性风险")
    var continuityRisks: [String]
}

@Generable
nonisolated struct CaptainCommandSetDraft {
    @Guide(description: "准确复述作者本轮真正要求改变的东西，不评价、不扩写作者没有提出的创意")
    var interpretation: String

    @Guide(
        description: "恰好四个完整、具体且执行策略真正不同的方案",
        .count(4)
    )
    var options: [CaptainCommandOptionDraft]
}

@MainActor
enum CaptainCommandEngine {
    static func generate(
        command: String,
        originContext: String,
        project: StoryProject,
        configuration: AIConfiguration
    ) async throws -> CaptainCommandResult {
        let cleanCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCommand.isEmpty else {
            throw CaptainCommandError.emptyCommand
        }

        let executionConfiguration = configuration.withThinkingEnabled(false)
        let session = StoryLanguageRuntime.session(
            configuration: executionConfiguration,
            instructions: """
            你是飞船上的故事执行系统，人类作者是船长。
            船长提供唯一的创新与创意主权；你不负责引导船长想什么，也不把他的想法改写成
            陈旧类型片套路。你的职责是定位影响、完成机械性创作劳动、维护固定结构与连续性，
            然后给出恰好四个可供船长选择的执行方案。

            每个方案必须在 impactMap 中逐项检查故事前提、人物、人物关系、世界、主题、
            核心冲突、固定结构、场景和正式剧本。changes 只列出 impactMap 中为 true 的区域，
            area 必须严格使用以下名称之一：故事前提、人物、人物关系、世界、主题、核心冲突、
            固定结构、场景、剧本。每个受影响区域恰好一项，不输出未受影响区域的空修改。

            update 必须是可直接写入相应模块的具体内容，而不是“建议加强”“可以考虑”等意见。
            人物更新要包含行为、欲望、需求、错误信念、秘密或弧线中真正
            相关的细节；关系更新要说明情感需要、权力差、秘密与压力；世界更新要形成可执行
            规则；主题要成为行动中的价值命题；结构只安排事件与代价，绝不能更换或推翻船长
            已锁定的结构模板；场景要有目标、阻力、转折和结果；剧本更新只能提供可拍摄动作、
            对白或标准剧本段落，不能写分析说明。

            四个方案都必须忠实执行同一个作者想法，差别来自落地机制、人物选择、关系压力、
            信息揭示或事件安排，不能通过削弱、否定或替换作者想法来制造差异。
            所有受影响区域都必须最终还原为 W/K/G/R/D/E 的状态契约：修改前是什么、修改后
            必须是什么、哪些变化不得提前发生、观众认知如何变化。节奏只依据有效状态变化
            影响量除以时间；不得用更多句子、动作或事件名称冒充节奏。
            """
        )

        let response = try await session.respond(
            to: """
            【船长本轮指令 · 必须逐字尊重】
            \(String(cleanCommand.prefix(8_000)))

            【输入所在层级 · 用于理解语境，不得限制全本影响分析】
            \(originContext)

            【项目态势】
            \(projectContext(project))

            【固定结构 · 不得替换】
            \(String(project.structureRulesForPrompt.prefix(8_000)))

            为船长返回恰好四个执行方案。每个 update 控制在必要的具体程度，避免重复整部
            故事；但必须丰富到确认后可以直接进入对应模块。不要提出第五个方案，不要反问。
            """,
            generating: CaptainCommandSetDraft.self,
            options: GenerationOptions(
                temperature: 0.68,
                maximumResponseTokens: 7_000
            )
        )

        do {
            return try validatedResult(response.content)
        } catch let validationError as CaptainCommandError {
            let repaired = try await session.respond(
                to: """
                上一次结果未通过应用层一致性检查：\(validationError.localizedDescription)
                请从头返回同一作者指令的四个方案。每个方案的 impactMap 九项都要填写，
                changes 必须与值为 true 的区域逐项、唯一、完全对应；area 只能使用规定名称。
                保持内容紧凑、具体，不改变作者创意核心和锁定结构。
                """,
                generating: CaptainCommandSetDraft.self,
                options: GenerationOptions(
                    temperature: 0.28,
                    maximumResponseTokens: 7_000
                )
            )
            return try validatedResult(repaired.content)
        }
    }

    private static func validatedResult(
        _ draft: CaptainCommandSetDraft
    ) throws -> CaptainCommandResult {
        let options = try draft.options.map { try $0.captainOption() }
        let result = CaptainCommandResult(
            interpretation: draft.interpretation,
            options: options
        )
        guard result.options.count == 4 else {
            throw CaptainCommandError.incompleteOptions
        }
        guard Set(result.options.map {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
        }).count == 4 else {
            throw CaptainCommandError.duplicatedOptions
        }
        guard result.options.allSatisfy({ !$0.affectedChanges.isEmpty }) else {
            throw CaptainCommandError.emptyChanges
        }
        return result
    }

    private static func projectContext(_ project: StoryProject) -> String {
        let characters = project.characters
            .sorted { $0.role == .protagonist && $1.role != .protagonist }
            .prefix(24)
            .map {
                """
                \($0.role.rawValue)「\($0.name)」
                年龄/职业：\($0.age) / \($0.occupation)
                核心：\($0.seedText)
                目标：\($0.externalGoal)
                需求：\($0.internalNeed)
                恐惧：\($0.fear)
                错误信念：\($0.falseBelief)
                缺点/优势：\($0.flaw) / \($0.strength)
                秘密：\($0.secret)
                弧线：\($0.arc)
                """
            }
            .joined(separator: "\n")

        let names = Dictionary(
            uniqueKeysWithValues: project.characters.map { ($0.id, $0.name) }
        )
        let relationships = project.characterRelationships.prefix(40).map {
            let from = names[$0.fromCharacterID] ?? "未知人物"
            let to = names[$0.toCharacterID] ?? "未知人物"
            return "\(from) → \(to)：\($0.kind.rawValue)，张力\($0.tension)，\($0.detail)"
        }
        .joined(separator: "\n")

        let decisions = project.decisions
            .filter { $0.selectedOption != nil }
            .sorted { $0.stageIndex < $1.stageIndex }
            .prefix(32)
            .compactMap { decision -> String? in
                guard let option = decision.selectedOption else { return nil }
                return """
                \(decision.stageIndex + 1). \(decision.stageName)：\(option.title)
                \(option.pitch)
                具体事实：\(option.concreteDetail)
                代价：\(option.consequence)
                后续压力：\(option.futurePressure)
                """
            }
            .joined(separator: "\n")

        let sceneContracts = project.sceneContracts
            .sorted { $0.sceneIndex < $1.sceneIndex }
            .prefix(48)
            .map { scene in
                let microBeats = scene.microBeats
                    .sorted()
                    .compactMap { beat -> String? in
                        guard let selected = beat.selectedOption else { return nil }
                        return "  小节拍 \(beat.ordinal)：\(selected.title)；\(selected.outcome)"
                    }
                    .joined(separator: "\n")
                return """
                场\(scene.sceneIndex) \(scene.heading)：\(scene.characterGoal)；阻碍 \(scene.obstacle)；转折 \(scene.turn)；结果 \(scene.outcome)
                \(microBeats.isEmpty ? "  小节拍尚未确认" : microBeats)
                """
            }
            .joined(separator: "\n")

        let canonicalFacts = project.canonicalFacts.prefix(60).map {
            "\($0.isLockedByAuthor ? "已锁定" : "事实") · \($0.kind.rawValue)：\($0.subject) \($0.predicate) \($0.value)"
        }
        .joined(separator: "\n")

        let activeIdeas = project.activeCreativeIdeas.prefix(12)
            .map(\.promptLine)
            .joined(separator: "\n")

        return """
        标题：\(project.title)
        类型：\(project.genre.rawValue)
        一句话：\(project.logline)
        戏剧问题：\(project.dramaticPromise)
        作者长期方向：\(String(project.creativeDirectionText.prefix(5_000)))
        作者后来确认的创意：\(String(activeIdeas.prefix(6_000)))

        【剧本圣经】
        \(String(project.storyBibleDigest.prefix(8_000)))

        【人物】
        \(characters.isEmpty ? "尚未建立" : characters)

        【人物关系】
        \(relationships.isEmpty ? "尚未建立" : relationships)

        【世界】
        \(String(project.worldText.prefix(6_000)))

        【主题】
        \(String(project.themeText.prefix(4_000)))

        【核心冲突】
        \(String(project.coreConflictText.prefix(4_000)))

        【已确认结构选择】
        \(decisions.isEmpty ? "尚未推进" : decisions)

        【全本路线】
        \(String(project.structureText.prefix(7_000)))

        【场景与场内小节拍】
        \(sceneContracts.isEmpty ? String(project.scenesText.prefix(7_000)) : sceneContracts)

        【正式剧本节选】
        \(screenplayExcerpt(project.screenplayText))

        【事实账本】
        \(canonicalFacts.isEmpty ? "尚未建立" : canonicalFacts)

        \(project.dramaticSemanticFoundationPrompt)
        """
    }

    private static func screenplayExcerpt(_ text: String) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "尚未开始正式剧本" }
        guard clean.count > 8_000 else { return clean }
        return String(clean.prefix(5_500))
            + "\n\n【中段省略】\n\n"
            + String(clean.suffix(2_500))
    }
}

private extension CaptainCommandOptionDraft {
    func captainOption() throws -> CaptainCommandOption {
        var seen = Set<CaptainStoryArea>()
        let mappedChanges = try changes.map { draft -> CaptainAreaChange in
            guard let area = CaptainStoryArea(rawValue: draft.area) else {
                throw CaptainCommandError.invalidArea(draft.area)
            }
            guard seen.insert(area).inserted else {
                throw CaptainCommandError.duplicatedArea(area.rawValue)
            }
            return draft.change(for: area)
        }
        guard seen == impactMap.affectedAreas else {
            throw CaptainCommandError.inconsistentImpactMap
        }

        return CaptainCommandOption(
            title: title,
            strategy: strategy,
            protectedCore: protectedCore,
            changes: mappedChanges,
            preservedFacts: preservedFacts,
            continuityRisks: continuityRisks
        )
    }
}

private extension CaptainImpactMapDraft {
    var affectedAreas: Set<CaptainStoryArea> {
        var result = Set<CaptainStoryArea>()
        if premise { result.insert(.premise) }
        if characters { result.insert(.characters) }
        if relationships { result.insert(.relationships) }
        if world { result.insert(.world) }
        if theme { result.insert(.theme) }
        if conflict { result.insert(.conflict) }
        if structure { result.insert(.structure) }
        if scenes { result.insert(.scenes) }
        if screenplay { result.insert(.screenplay) }
        return result
    }
}

private extension CaptainAreaRevisionDraft {
    func change(for area: CaptainStoryArea) -> CaptainAreaChange {
        CaptainAreaChange(
            area: area,
            affected: true,
            target: target,
            update: update,
            consequence: consequence
        )
    }
}

enum CaptainCommandError: LocalizedError {
    case emptyCommand
    case incompleteOptions
    case duplicatedOptions
    case emptyChanges
    case invalidArea(String)
    case duplicatedArea(String)
    case inconsistentImpactMap

    var errorDescription: String? {
        switch self {
        case .emptyCommand:
            "请先写下船长指令。"
        case .incompleteOptions:
            "DeepSeek 没有返回恰好四个完整方案。"
        case .duplicatedOptions:
            "四个方案没有形成真实差异，请重新生成。"
        case .emptyChanges:
            "至少一个方案没有产生可执行变更，请重新生成。"
        case .invalidArea(let area):
            "DeepSeek 返回了无法识别的故事区域“\(area)”。"
        case .duplicatedArea(let area):
            "DeepSeek 重复返回了“\(area)”区域。"
        case .inconsistentImpactMap:
            "DeepSeek 的影响矩阵与实际修改清单不一致。"
        }
    }
}
