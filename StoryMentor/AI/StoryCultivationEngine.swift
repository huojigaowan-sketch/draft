import Foundation

struct StoryCultivationOutcome {
    let snapshot: StoryCultivationSnapshot
    let usage: TokenUsage
    let comparison: StoryExperimentComparison?
}

struct StoryCultivationAIResult: Decodable {
    struct Atom: Decodable {
        let content: String
        let type: String
        let importance: Double

        private enum CodingKeys: String, CodingKey { case content, type, importance }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            content = try values.decodeIfPresent(String.self, forKey: .content) ?? "尚待辨认的碎片"
            type = try values.decodeIfPresent(String.self, forKey: .type) ?? StoryAtomType.unknown.rawValue
            importance = try values.decodeIfPresent(Double.self, forKey: .importance) ?? 0.5
        }
    }

    struct Psychology: Decodable {
        let character: String
        let need: String
        let desire: String
        let fear: String
        let wound: String
        let belief: String
        let defense: String
        let contradiction: String

        private enum CodingKeys: String, CodingKey {
            case character, need, desire, fear, wound, belief, defense, contradiction
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            character = try values.decodeIfPresent(String.self, forKey: .character) ?? "主人公"
            need = try values.decodeIfPresent(String.self, forKey: .need) ?? HumanNeed.belonging.rawValue
            desire = try values.decodeIfPresent(String.self, forKey: .desire) ?? "尚待实验"
            fear = try values.decodeIfPresent(String.self, forKey: .fear) ?? "尚待实验"
            wound = try values.decodeIfPresent(String.self, forKey: .wound) ?? "尚待发现"
            belief = try values.decodeIfPresent(String.self, forKey: .belief) ?? "尚待发现"
            defense = try values.decodeIfPresent(String.self, forKey: .defense) ?? "尚待发现"
            contradiction = try values.decodeIfPresent(String.self, forKey: .contradiction) ?? "尚待实验"
        }
    }

    struct Variable: Decodable {
        let name: String
        let question: String
        let options: [String]

        private enum CodingKeys: String, CodingKey { case name, question, options }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            name = try values.decodeIfPresent(String.self, forKey: .name) ?? "实验变量"
            question = try values.decodeIfPresent(String.self, forKey: .question) ?? "改变它会发生什么？"
            options = try values.decodeIfPresent([String].self, forKey: .options) ?? []
        }
    }

    struct Experiment: Decodable {
        let axis: String
        let title: String
        let hypothesis: String
        let whyItMatters: String
        let variables: [Variable]

        private enum CodingKeys: String, CodingKey {
            case axis, title, hypothesis, whyItMatters, variables
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            axis = try values.decodeIfPresent(String.self, forKey: .axis) ?? StoryExperimentAxis.character.rawValue
            title = try values.decodeIfPresent(String.self, forKey: .title) ?? "人物压力实验"
            hypothesis = try values.decodeIfPresent(String.self, forKey: .hypothesis) ?? "改变压力，观察选择。"
            whyItMatters = try values.decodeIfPresent(String.self, forKey: .whyItMatters) ?? "验证这个碎片能否迫使人物行动。"
            variables = try values.decodeIfPresent([Variable].self, forKey: .variables) ?? []
        }
    }

    struct Evaluation: Decodable {
        let strengths: [String]
        let gaps: [String]
        let nextStep: String

        private enum CodingKeys: String, CodingKey { case strengths, gaps, nextStep }

        init(strengths: [String], gaps: [String], nextStep: String) {
            self.strengths = strengths
            self.gaps = gaps
            self.nextStep = nextStep
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            strengths = try values.decodeIfPresent([String].self, forKey: .strengths) ?? []
            gaps = try values.decodeIfPresent([String].self, forKey: .gaps) ?? []
            nextStep = try values.decodeIfPresent(String.self, forKey: .nextStep) ?? "选择一个变量继续实验。"
        }
    }

    struct Crystal: Decodable {
        let coreIdea: String
        let characterInsight: String
        let conflict: String
        let theme: String
        let whyInteresting: String

        private enum CodingKeys: String, CodingKey {
            case coreIdea, characterInsight, conflict, theme, whyInteresting
        }

        init(
            coreIdea: String,
            characterInsight: String,
            conflict: String,
            theme: String,
            whyInteresting: String
        ) {
            self.coreIdea = coreIdea
            self.characterInsight = characterInsight
            self.conflict = conflict
            self.theme = theme
            self.whyInteresting = whyInteresting
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            coreIdea = try values.decodeIfPresent(String.self, forKey: .coreIdea) ?? "尚待培养"
            characterInsight = try values.decodeIfPresent(String.self, forKey: .characterInsight) ?? "尚待实验"
            conflict = try values.decodeIfPresent(String.self, forKey: .conflict) ?? "尚待实验"
            theme = try values.decodeIfPresent(String.self, forKey: .theme) ?? "尚待实验"
            whyInteresting = try values.decodeIfPresent(String.self, forKey: .whyInteresting) ?? "仍需一次高杠杆实验。"
        }
    }

    struct Comparison: Decodable {
        let conditionChange: String
        let structureChange: String
        let characterChange: String
        let dialogueChange: String
        let emotionChange: String
        let invariants: [String]
        let questions: [String]

        private enum CodingKeys: String, CodingKey {
            case conditionChange, structureChange, characterChange
            case dialogueChange, emotionChange, invariants, questions
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            conditionChange = try values.decodeIfPresent(String.self, forKey: .conditionChange) ?? ""
            structureChange = try values.decodeIfPresent(String.self, forKey: .structureChange) ?? ""
            characterChange = try values.decodeIfPresent(String.self, forKey: .characterChange) ?? ""
            dialogueChange = try values.decodeIfPresent(String.self, forKey: .dialogueChange) ?? ""
            emotionChange = try values.decodeIfPresent(String.self, forKey: .emotionChange) ?? ""
            invariants = try values.decodeIfPresent([String].self, forKey: .invariants) ?? []
            questions = try values.decodeIfPresent([String].self, forKey: .questions) ?? []
        }

        var model: StoryExperimentComparison {
            StoryExperimentComparison(
                conditionChange: conditionChange,
                structureChange: structureChange,
                characterChange: characterChange,
                dialogueChange: dialogueChange,
                emotionChange: emotionChange,
                invariants: invariants,
                questions: questions
            )
        }
    }

    let atoms: [Atom]
    let characters: [String]
    let humanNeeds: [String]
    let desires: [String]
    let fears: [String]
    let contradictions: [String]
    let valueConflicts: [String]
    let dramaticQuestions: [String]
    let themes: [String]
    let psychology: [Psychology]
    let discovery: String
    let hiddenQuestion: String
    let experiments: [Experiment]
    let evaluation: Evaluation
    let crystal: Crystal
    let comparison: Comparison?

    private enum CodingKeys: String, CodingKey {
        case atoms, characters, humanNeeds, desires, fears, contradictions
        case valueConflicts, dramaticQuestions, themes, psychology
        case discovery, hiddenQuestion, experiments, evaluation, crystal, comparison
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        atoms = try values.decodeIfPresent([Atom].self, forKey: .atoms) ?? []
        characters = try values.decodeIfPresent([String].self, forKey: .characters) ?? []
        humanNeeds = try values.decodeIfPresent([String].self, forKey: .humanNeeds) ?? []
        desires = try values.decodeIfPresent([String].self, forKey: .desires) ?? []
        fears = try values.decodeIfPresent([String].self, forKey: .fears) ?? []
        contradictions = try values.decodeIfPresent([String].self, forKey: .contradictions) ?? []
        valueConflicts = try values.decodeIfPresent([String].self, forKey: .valueConflicts) ?? []
        dramaticQuestions = try values.decodeIfPresent([String].self, forKey: .dramaticQuestions) ?? []
        themes = try values.decodeIfPresent([String].self, forKey: .themes) ?? []
        psychology = try values.decodeIfPresent([Psychology].self, forKey: .psychology) ?? []
        discovery = try values.decodeIfPresent(String.self, forKey: .discovery) ?? "这个碎片正在寻找一个必须行动的人。"
        hiddenQuestion = try values.decodeIfPresent(String.self, forKey: .hiddenQuestion) ?? "人物愿意为真正需要的东西失去什么？"
        experiments = try values.decodeIfPresent([Experiment].self, forKey: .experiments) ?? []
        evaluation = try values.decodeIfPresent(Evaluation.self, forKey: .evaluation)
            ?? Evaluation(strengths: [], gaps: [], nextStep: "选择一个变量继续实验。")
        crystal = try values.decodeIfPresent(Crystal.self, forKey: .crystal)
            ?? Crystal(coreIdea: "尚待培养", characterInsight: "尚待实验", conflict: "尚待实验", theme: "尚待实验", whyInteresting: "仍需一次高杠杆实验。")
        comparison = try values.decodeIfPresent(Comparison.self, forKey: .comparison)
    }
}

@MainActor
struct StoryCultivationEngine {
    let settings: AISettingsStore

    func cultivate(
        rawIdea: String,
        authorIntent: String,
        previous: StoryCultivationSnapshot? = nil,
        decision: StoryExperimentDecision? = nil,
        progress: ((Double, String) -> Void)? = nil
    ) async throws -> StoryCultivationOutcome {
        let idea = rawIdea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idea.isEmpty else { throw StoryCultivationError.emptyIdea }

        progress?(0.08, "分离创意原子")
        let prepared = await AppleTextService.prepareForAnalysis(
            idea,
            enabled: settings.useApplePreprocessing
        )

        progress?(0.28, "匹配故事理论与人物心理")
        let evidence: [TheoryEvidence]
        if settings.useKnowledgeBase {
            evidence = (try? await TheoryIndexStore.shared.search(
                query: String(idea.prefix(2_400)),
                route: TheoryRouting.route(for: .overview),
                maximumMatches: 5,
                maximumCharacters: 2_800
            )) ?? []
        } else {
            evidence = []
        }

        let priorDecisions = previous?.decisions ?? []
        let decisions = priorDecisions + (decision.map { [$0] } ?? [])

        guard settings.hasAPIKey else {
            progress?(0.72, "使用本地培养模型建立实验")
            var snapshot = localSnapshot(
                rawIdea: idea,
                authorIntent: authorIntent,
                previous: previous,
                decisions: decisions
            )
            snapshot.provenanceNote = "本地培养模型 · \(prepared.note) · 理论命中 \(evidence.count) 条"
            let comparison = comparison(
                aiComparison: nil,
                baseline: previous,
                variant: snapshot,
                decision: decision
            )
            progress?(1, "三个单变量实验已就绪")
            return StoryCultivationOutcome(
                snapshot: snapshot,
                usage: .zero,
                comparison: comparison
            )
        }

        progress?(0.46, "DeepSeek 正在推演故事潜能")
        let completion = try await DeepSeekClient(
            configuration: settings.configuration()
        ).cultivateStorySeed(
            StoryCultivationContext(
                rawIdea: prepared.text,
                authorIntent: authorIntent,
                previousState: previous.map(summary) ?? "",
                authorChoice: decision.map(decisionSummary) ?? "",
                theoryContext: evidence.map(\.promptBlock).joined(separator: "\n\n")
            )
        )
        var snapshot = map(
            completion.result,
            rawIdea: idea,
            decisions: decisions,
            round: (previous?.round ?? 0) + 1
        )
        snapshot.provenanceNote = "DeepSeek · \(prepared.note) · 理论命中 \(evidence.count) 条"
        let comparison = comparison(
            aiComparison: completion.result.comparison,
            baseline: previous,
            variant: snapshot,
            decision: decision
        )
        progress?(1, "单变量对照与新问题已就绪")
        return StoryCultivationOutcome(
            snapshot: snapshot,
            usage: completion.usage,
            comparison: comparison
        )
    }

    private func comparison(
        aiComparison: StoryCultivationAIResult.Comparison?,
        baseline: StoryCultivationSnapshot?,
        variant: StoryCultivationSnapshot,
        decision: StoryExperimentDecision?
    ) -> StoryExperimentComparison? {
        guard let baseline, let decision else { return nil }
        if let aiComparison {
            return aiComparison.model
        }
        return StoryExperimentComparison.comparing(
            baseline: baseline,
            variant: variant,
            decision: decision
        )
    }

    private func map(
        _ result: StoryCultivationAIResult,
        rawIdea: String,
        decisions: [StoryExperimentDecision],
        round: Int
    ) -> StoryCultivationSnapshot {
        let needs = unique(result.humanNeeds.compactMap(HumanNeed.init(rawValue:)))
        let experiments = result.experiments.prefix(3).map { item in
            StoryExperiment(
                axis: StoryExperimentAxis(rawValue: item.axis) ?? .character,
                title: item.title,
                hypothesis: item.hypothesis,
                whyItMatters: item.whyItMatters,
                variables: item.variables.map {
                    StoryExperimentVariable(
                        name: $0.name,
                        question: $0.question,
                        options: $0.options
                    )
                }
            )
        }
        let fallbackExperiments = experiments.count == 3
            ? experiments
            : defaultExperiments(rawIdea: rawIdea)

        return StoryCultivationSnapshot(
            schemaVersion: 1,
            rawIdea: rawIdea,
            atoms: result.atoms.map {
                StoryAtom(
                    content: $0.content,
                    type: StoryAtomType(rawValue: $0.type) ?? .unknown,
                    importance: $0.importance
                )
            },
            characters: unique(result.characters),
            humanNeeds: needs.isEmpty ? [.belonging, .safety] : needs,
            desires: unique(result.desires),
            fears: unique(result.fears),
            contradictions: unique(result.contradictions),
            valueConflicts: unique(result.valueConflicts),
            dramaticQuestions: unique(result.dramaticQuestions),
            themes: unique(result.themes),
            psychology: result.psychology.map {
                CharacterPsychology(
                    character: $0.character,
                    need: HumanNeed(rawValue: $0.need) ?? .belonging,
                    desire: $0.desire,
                    fear: $0.fear,
                    wound: $0.wound,
                    belief: $0.belief,
                    defense: $0.defense,
                    contradiction: $0.contradiction
                )
            },
            discovery: result.discovery,
            hiddenQuestion: result.hiddenQuestion,
            experiments: fallbackExperiments,
            decisions: decisions,
            evaluation: StoryPotentialEvaluation(
                strengths: unique(result.evaluation.strengths),
                gaps: unique(result.evaluation.gaps),
                nextStep: result.evaluation.nextStep
            ),
            crystal: StoryCrystal(
                coreIdea: result.crystal.coreIdea,
                characterInsight: result.crystal.characterInsight,
                conflict: result.crystal.conflict,
                theme: result.crystal.theme,
                whyInteresting: result.crystal.whyInteresting
            ),
            round: max(round, 1),
            provenanceNote: ""
        )
    }

    private func localSnapshot(
        rawIdea: String,
        authorIntent: String,
        previous: StoryCultivationSnapshot?,
        decisions: [StoryExperimentDecision]
    ) -> StoryCultivationSnapshot {
        let lastChoice = decisions.last?.selectedValues.values.sorted().joined(separator: "、") ?? ""
        let character = inferredCharacter(in: rawIdea)
        let desire = authorIntent.storyScienceTrimmed.isEmpty
            ? "维持自己舍不得失去的关系或状态"
            : authorIntent.storyScienceTrimmed
        let fear = inferredFear(in: rawIdea)
        let needs: [HumanNeed] = rawIdea.contains("死") || rawIdea.contains("失去")
            ? [.belonging, .safety]
            : [.esteem, .belonging]
        let discovery = lastChoice.isEmpty
            ? "你现在创造的是：一个用具体行动对抗失去，却还没有承认自己真正需求的人。"
            : "你的选择“\(lastChoice)”让故事从漂亮设定变成了人物必须承担后果的行动。"
        let hidden = rawIdea.contains("死") || rawIdea.contains("忘")
            ? "真正的问题可能不是如何留住过去，而是：人物是否相信放手等于背叛？"
            : "真正的问题不是接下来发生什么，而是：人物愿意牺牲哪一种价值来保护另一种？"
        let core = rawIdea.count > 110 ? String(rawIdea.prefix(110)) + "…" : rawIdea
        let round = max((previous?.round ?? 0) + 1, 1)

        return StoryCultivationSnapshot(
            schemaVersion: 1,
            rawIdea: rawIdea,
            atoms: inferredAtoms(from: rawIdea, character: character, lastChoice: lastChoice),
            characters: [character],
            humanNeeds: needs,
            desires: [desire],
            fears: [fear],
            contradictions: ["越想保护珍视之物，越可能用错误方式把它推远"],
            valueConflicts: ["安全 vs 归属", "记住过去 vs 继续生活"],
            dramaticQuestions: ["当两种珍视的价值不能同时保全，人物会选择哪一个？"],
            themes: ["爱是否允许一个人改变，而不把改变视为背叛？"],
            psychology: [
                CharacterPsychology(
                    character: character,
                    need: needs[0],
                    desire: desire,
                    fear: fear,
                    belief: "只要维持原来的行动，一切就还没有真正失去",
                    defense: "否认与合理化",
                    contradiction: "想靠控制获得安全，却因此无法真正连接"
                )
            ],
            discovery: discovery,
            hiddenQuestion: hidden,
            experiments: defaultExperiments(rawIdea: rawIdea),
            decisions: decisions,
            evaluation: StoryPotentialEvaluation(
                strengths: ["已有清晰、可感知的核心画面", "人物行动与潜在情感需求之间存在张力"],
                gaps: ["尚未形成不可避免的两难选择", "行动的外部后果仍需被具体化"],
                nextStep: "不要扩写情节；先选择一个实验，验证人物最害怕失去什么。"
            ),
            crystal: StoryCrystal(
                coreIdea: core,
                characterInsight: "\(character)真正需要的不是维持现状，而是确认自己不会因改变而失去爱的资格。",
                conflict: "人物必须在自我保护与真实连接之间做出不可两全的选择。",
                theme: "改变不一定背叛曾经珍视的东西。",
                whyInteresting: "一个日常动作正在掩盖无法承认的需要；一旦动作产生回应，人物就必须选择。"
            ),
            round: round,
            provenanceNote: ""
        )
    }

    private func defaultExperiments(rawIdea: String) -> [StoryExperiment] {
        [
            StoryExperiment(
                axis: .character,
                title: "愿望兑现实验",
                hypothesis: "如果人物真的得到表面愿望，隐藏恐惧会不会反而暴露？",
                whyItMatters: "强人物不是因为愿望强，而是因为愿望与需要彼此冲突。",
                variables: [
                    StoryExperimentVariable(
                        name: "愿望的代价",
                        question: "得到想要的东西时，他必须失去什么？",
                        options: ["失去安全", "失去被爱的资格", "失去对过去的忠诚感"]
                    ),
                    StoryExperimentVariable(
                        name: "承认方式",
                        question: "人物如何面对真正需要？",
                        options: ["承认", "否认", "合理化"]
                    )
                ]
            ),
            StoryExperiment(
                axis: .conflict,
                title: "不可两全实验",
                hypothesis: "让保护一个人的行为同时伤害这个人，冲突是否变得不可回避？",
                whyItMatters: "冲突的生命力来自价值互斥，而不是争吵次数。",
                variables: [
                    StoryExperimentVariable(
                        name: "珍视价值",
                        question: "人物最想保住哪一种价值？",
                        options: ["爱情", "尊严", "安全", "过去"]
                    ),
                    StoryExperimentVariable(
                        name: "行动方式",
                        question: "压力下他会怎么行动？",
                        options: ["攻击", "逃避", "控制", "自毁"]
                    )
                ]
            ),
            StoryExperiment(
                axis: .world,
                title: "条件突变实验",
                hypothesis: "如果世界突然回应人物的执念，这个碎片能否迫使人物选择？",
                whyItMatters: "世界条件只在它改变人物选择时才具有戏剧功能。",
                variables: [
                    StoryExperimentVariable(
                        name: "回应来源",
                        question: "是谁或什么打破原来的平衡？",
                        options: ["最想逃避的人", "最可信的制度", "不可能出现的回应"]
                    ),
                    StoryExperimentVariable(
                        name: "秘密时机",
                        question: "真相何时暴露？",
                        options: ["立刻暴露", "选择之后暴露", "由人物亲手揭开"]
                    )
                ]
            )
        ]
    }

    private func inferredAtoms(
        from idea: String,
        character: String,
        lastChoice: String
    ) -> [StoryAtom] {
        var atoms = [
            StoryAtom(content: character, type: .character, importance: 0.9),
            StoryAtom(content: idea, type: inferredPrimaryType(in: idea), importance: 1),
            StoryAtom(content: inferredFear(in: idea), type: .emotion, importance: 0.82),
            StoryAtom(content: "为什么必须继续？继续会造成什么？", type: .unknown, importance: 0.88)
        ]
        if !lastChoice.isEmpty {
            atoms.append(StoryAtom(content: lastChoice, type: .choice, importance: 0.94))
        }
        return atoms
    }

    private func inferredCharacter(in idea: String) -> String {
        let candidates = ["女人", "男人", "女孩", "男孩", "老人", "母亲", "父亲", "孩子", "警察", "医生"]
        return candidates.first(where: idea.contains) ?? "这个创意中的主人公"
    }

    private func inferredFear(in idea: String) -> String {
        if idea.contains("死") || idea.contains("失去") { return "忘记与被遗忘" }
        if idea.contains("秘密") || idea.contains("谎") { return "真相暴露后不再被接纳" }
        if idea.contains("爱") || idea.contains("嫉妒") { return "不再被选择" }
        return "一旦改变，就会失去目前仍能依靠的东西"
    }

    private func inferredPrimaryType(in idea: String) -> StoryAtomType {
        if idea.contains("说") || idea.contains("问") || idea.contains("：") { return .dialogue }
        if idea.contains("世界") || idea.contains("规则") || idea.contains("所有人") { return .worldRule }
        if idea.contains("看见") || idea.contains("画面") || idea.contains("梦") { return .image }
        return .event
    }

    private func summary(_ snapshot: StoryCultivationSnapshot) -> String {
        """
        第 \(snapshot.round) 轮发现：\(snapshot.discovery)
        隐藏问题：\(snapshot.hiddenQuestion)
        当前冲突：\(snapshot.crystal.conflict)
        当前主题：\(snapshot.crystal.theme)
        已完成实验：\(snapshot.decisions.map(decisionSummary).joined(separator: "；"))
        """
    }

    private func decisionSummary(_ decision: StoryExperimentDecision) -> String {
        let values = decision.selectedValues
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "，")
        let details = [
            decision.choiceRecord.map { "选择来源=\($0.source.rawValue)" },
            decision.authorObservation.storyScienceTrimmed.isEmpty
                ? nil
                : "实验前注意=\(decision.authorObservation.storyScienceTrimmed)",
            decision.reviewDisposition.map { "作者判断=\($0.rawValue)" },
            decision.choiceReason?.storyScienceTrimmed.isEmpty == false
                ? "选择理由=\(decision.choiceReason ?? "")"
                : nil,
            decision.authorRevision?.storyScienceTrimmed.isEmpty == false
                ? "人工修改意见=\(decision.authorRevision ?? "")"
                : nil,
            decision.newDiscovery?.storyScienceTrimmed.isEmpty == false
                ? "本轮新发现=\(decision.newDiscovery ?? "")"
                : nil
        ].compactMap { $0 }
        let suffix = details.isEmpty ? "" : "；" + details.joined(separator: "；")
        return "\(decision.experimentTitle)：\(values)\(suffix)"
    }

    private func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }
}

enum StoryCultivationError: LocalizedError {
    case emptyIdea

    var errorDescription: String? {
        switch self {
        case .emptyIdea: "请先放入一个人物、画面、情绪、事件、梦或一句对白。"
        }
    }
}
