import Foundation

nonisolated enum NarrativeCompilerEngine {
    struct CandidateSeed: Sendable {
        let title: String
        let thesis: String
        let tactic: String
        let concealment: String
        let primaryDimension: NarrativeStateDimension
        let before: String
        let after: String
        let cost: String
        let obligation: String
        let functions: Set<DramaticFunction>
        let objectives: NarrativeObjectiveVector
    }

    static func formalize(
        kind: CreativePropositionKind,
        text: String,
        characterIDs: [CharacterID],
        revision: RevisionID
    ) -> Proposition {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let forbidden = forbiddenClauses(in: clean)
        return Proposition(
            kind: kind,
            originalText: clean,
            formalStatement: formalStatement(kind: kind, text: clean),
            targetCharacterIDs: characterIDs,
            forbiddenOutcomes: forbidden,
            lockedFacts: [clean],
            undecidedVariables: missingVariables(kind: kind, text: clean),
            status: .locked,
            revision: revision
        )
    }

    static func nextQuestion(
        for proposition: Proposition
    ) -> InformationGainQuestion? {
        questionLibrary(for: proposition.kind)
            .filter { question in
                proposition.undecidedVariables.isEmpty
                    || proposition.undecidedVariables.contains(question.variable)
            }
            .max { $0.expectedInformationGain < $1.expectedInformationGain }
            ?? questionLibrary(for: proposition.kind).max {
                $0.expectedInformationGain < $1.expectedInformationGain
            }
    }

    static func localCandidates(
        proposition: Proposition,
        answer: String,
        characterNames: [String],
        revision: RevisionID
    ) -> [CompilerCandidate] {
        let seeds = candidateSeeds(for: proposition.kind, answer: answer)
        let candidates = seeds.enumerated().map { index, seed in
            makeCandidate(
                seed: seed,
                index: index,
                proposition: proposition,
                answer: answer,
                characterNames: characterNames,
                revision: revision,
                provider: "确定性规划器",
                model: "NSIR Local Planner"
            )
        }
        return NarrativeConstraintSolver.search(candidates, proposition: proposition)
    }

    static func candidate(
        title: String,
        thesis: String,
        tactic: String,
        concealment: String,
        primaryDimension: NarrativeStateDimension,
        before: String,
        after: String,
        cost: String,
        obligation: String,
        functions: Set<DramaticFunction>,
        objectives: NarrativeObjectiveVector,
        proposition: Proposition,
        answer: String,
        characterNames: [String],
        revision: RevisionID,
        provider: String,
        model: String,
        index: Int
    ) -> CompilerCandidate {
        makeCandidate(
            seed: CandidateSeed(
                title: title,
                thesis: thesis,
                tactic: tactic,
                concealment: concealment,
                primaryDimension: primaryDimension,
                before: before,
                after: after,
                cost: cost,
                obligation: obligation,
                functions: functions,
                objectives: objectives
            ),
            index: index,
            proposition: proposition,
            answer: answer,
            characterNames: characterNames,
            revision: revision,
            provider: provider,
            model: model
        )
    }

    static func paretoFront(_ candidates: [CompilerCandidate]) -> [CompilerCandidate] {
        let front = candidates.filter { candidate in
            !candidates.contains { other in
                other.id != candidate.id
                    && other.objectives.dominates(candidate.objectives)
            }
        }
        return front.isEmpty ? candidates : front
    }

    private static func makeCandidate(
        seed: CandidateSeed,
        index: Int,
        proposition: Proposition,
        answer: String,
        characterNames: [String],
        revision: RevisionID,
        provider: String,
        model: String
    ) -> CompilerCandidate {
        let protagonistID = proposition.targetCharacterIDs.first
        let actorName = characterNames.first ?? "命题人物"
        let targetName = characterNames.dropFirst().first ?? "关系对象"
        let origin = Provenance(
            source: "作者命题",
            model: model,
            sourcePropositionIDs: [proposition.id],
            generatedAt: .now
        )

        let triggerID = UUID()
        let tacticID = UUID()
        let costID = UUID()
        let trigger = DramaticTransition(
            id: triggerID,
            title: "触发：\(answer.isEmpty ? seed.before : answer)",
            trigger: Trigger(
                summary: "一个可观察事实威胁作者锁定命题中的珍视状态",
                sourceTransitionID: nil,
                externalEvent: true
            ),
            actor: protagonistID,
            actorName: actorName,
            target: NarrativeTarget(characterID: nil, object: targetName),
            intention: "确认威胁是否真实",
            tactic: Tactic(verb: "察觉", method: "通过具体细节获得证据", concealment: "暂不表态"),
            resistance: ["证据仍存在替代解释"],
            effects: [
                StateMutation(
                    dimension: .audience,
                    subject: seed.thesis,
                    holderID: nil,
                    beforeValue: "观众尚未确认压力",
                    afterValue: "观众看见压力已经进入关系",
                    truthStatus: .suspicion,
                    observerIDs: [],
                    audienceObserves: true
                )
            ],
            visibility: .audienceOnly,
            dramaticFunctions: [.setup],
            provenance: origin,
            confidence: AnalysisConfidence(value: 0.82, basis: "作者命题与所选回答")
        )
        let tactic = DramaticTransition(
            id: tacticID,
            title: seed.title,
            preconditions: [],
            trigger: Trigger(
                summary: "触发证据迫使人物采取保护策略",
                sourceTransitionID: triggerID,
                externalEvent: false
            ),
            actor: protagonistID,
            actorName: actorName,
            target: NarrativeTarget(characterID: nil, object: targetName),
            intention: seed.thesis,
            tactic: Tactic(
                verb: seed.tactic,
                method: "以可拍摄的行动改变局面",
                concealment: seed.concealment
            ),
            resistance: ["对方不接受人物给出的表面理由"],
            effects: [
                StateMutation(
                    dimension: seed.primaryDimension,
                    subject: seed.thesis,
                    holderID: protagonistID,
                    beforeValue: seed.before,
                    afterValue: seed.after,
                    truthStatus: .fact,
                    observerIDs: protagonistID.map { [$0] } ?? [],
                    audienceObserves: true
                ),
                StateMutation(
                    dimension: .identity,
                    subject: "表面理由与真实动机",
                    holderID: protagonistID,
                    beforeValue: "尚未需要自我解释",
                    afterValue: seed.concealment,
                    truthStatus: .belief,
                    observerIDs: protagonistID.map { [$0] } ?? [],
                    audienceObserves: true
                )
            ],
            visibility: VisibilityMap(
                observerIDs: protagonistID.map { [$0] } ?? [],
                audienceObserves: true,
                concealedFromIDs: []
            ),
            cost: [Consequence(title: "即时代价", detail: seed.cost, severity: 0.64)],
            dramaticFunctions: seed.functions,
            partialOrderPredecessorIDs: [triggerID],
            provenance: origin,
            confidence: AnalysisConfidence(value: 0.74, basis: "形式模型候选，待作者裁决")
        )
        let cost = DramaticTransition(
            id: costID,
            title: "反馈：策略产生关系代价",
            trigger: Trigger(
                summary: "对方对保护策略作出不可忽略的反馈",
                sourceTransitionID: tacticID,
                externalEvent: false
            ),
            actor: nil,
            actorName: targetName,
            target: NarrativeTarget(characterID: protagonistID, object: actorName),
            intention: "回应被施加的策略",
            tactic: Tactic(verb: "拒绝配合", method: "指出表面理由中的裂缝", concealment: "不替对方说出真实动机"),
            resistance: ["人物坚持原有防御"],
            effects: [
                StateMutation(
                    dimension: .relationship,
                    subject: "\(actorName)与\(targetName)的关系",
                    beforeValue: "原有平衡仍可维持",
                    afterValue: seed.cost,
                    observerIDs: protagonistID.map { [$0] } ?? [],
                    audienceObserves: true
                )
            ],
            visibility: .audienceOnly,
            cost: [Consequence(title: "后续义务", detail: seed.obligation, severity: 0.52)],
            dramaticFunctions: [.escalation],
            partialOrderPredecessorIDs: [tacticID],
            provenance: origin,
            confidence: AnalysisConfidence(value: 0.69, basis: "候选的逻辑后果")
        )

        let obligation = Obligation(
            title: "回收：\(seed.title)",
            detail: seed.obligation,
            createdByTransitionID: costID,
            ruleClass: .l1
        )
        let transitions = [trigger, tactic, cost]
        let patchID = UUID()
        let patch = StoryPatch(
            id: patchID,
            baseRevision: revision,
            title: seed.title,
            operations: [.addProposition(proposition)]
                + transitions.map(StoryOperation.addTransition)
                + [.addObligation(obligation)],
            createdAt: .now,
            generatedBy: ModelExecutionRecord(
                provider: provider,
                model: model,
                profile: "PlanningProfile",
                contextSummary: "仅使用当前命题、人物名、作者回答与适用规则卡",
                createdAt: .now
            )
        )
        let diff = StateDiff(
            mutations: transitions.flatMap(\.effects),
            introducedObligations: [obligation],
            resolvedObligationIDs: [],
            screenplayPreview: actionSkeleton(
                actor: actorName,
                target: targetName,
                seed: seed
            )
        )
        let trace = RecommendationTrace(
            id: UUID(),
            conclusion: seed.thesis,
            ruleClass: .l2,
            appliedRules: [
                RuleReference(title: "作者公理不可改写", ruleClass: .l0),
                RuleReference(title: "有效状态转移", ruleClass: .l1),
                RuleReference(title: proposition.kind == .emotion ? "情感评价结构" : "命题形式模型", ruleClass: .l2),
                RuleReference(title: "审美只供裁决", ruleClass: .l5)
            ],
            acceptedPremises: [
                PremiseReference(id: UUID(), propositionID: proposition.id, statement: proposition.formalStatement),
                PremiseReference(id: UUID(), propositionID: nil, statement: answer)
            ].filter { !$0.statement.isEmpty },
            assumptions: [
                Assumption(id: UUID(), statement: "\(targetName)会对该策略给出可观察反馈", authorConfirmed: false)
            ],
            evidence: [
                EvidenceReference(id: UUID(), label: "作者原文", sourceID: proposition.id.uuidString, excerpt: proposition.originalText)
            ],
            counterEvidence: [],
            detectedProblem: nil,
            proposedPatchID: patchID,
            resultingStateDiff: diff,
            alternatives: [],
            tradeoffs: [Tradeoff(id: UUID(), gains: seed.thesis, costs: seed.cost)],
            uncertainty: UncertaintyReport(
                confidence: 0.72,
                unresolvedVariables: proposition.undecidedVariables,
                modelDependentClaims: ["具体情绪与冲突定义属于可替换的 L2 形式模型"]
            ),
            requiresAuthorDecision: true
        )
        return CompilerCandidate(
            id: UUID(),
            title: seed.title,
            thesis: seed.thesis,
            transitions: transitions,
            patch: patch,
            trace: trace,
            objectives: seed.objectives,
            actionSkeleton: diff.screenplayPreview
        )
    }

    private static func formalStatement(kind: CreativePropositionKind, text: String) -> String {
        switch kind {
        case .emotion: "TargetExperience(人物, \(text)) ∧ Preserve(作者禁令)"
        case .trauma: "PastEvent → Belief → Defense → CurrentChoice：\(text)"
        case .foreshadowing: "Evidence(e) raises FutureHypothesis while preserving alternatives：\(text)"
        case .microConflict: "¬Reachable(GoalA ∧ GoalB, current horizon)：\(text)"
        case .relationship: "RelationshipVector(before) ≠ RelationshipVector(after)：\(text)"
        case .secretReveal: "Knowledge(character) ≠ Knowledge(audience)：\(text)"
        case .choiceCost: "Choose(A,B) ∧ ¬CanKeep(A ∧ B)：\(text)"
        case .imageAction: "VisibleAction → InterpretableStateMutation：\(text)"
        }
    }

    private static func forbiddenClauses(in text: String) -> [String] {
        let markers = ["不能", "不得", "绝不", "不可以", "一律不", "不要"]
        return text
            .components(separatedBy: CharacterSet(charactersIn: "，。；;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { clause in markers.contains { clause.contains($0) } }
    }

    private static func missingVariables(kind: CreativePropositionKind, text: String) -> [String] {
        switch kind {
        case .emotion: ["珍视对象", "威胁来源", "可承认程度", "行动倾向"]
        case .trauma: ["形成的信念", "保护策略", "当前收益", "触发条件"]
        case .foreshadowing: ["未来解释", "替代解释", "诊断强度", "回收方式"]
        case .microConflict: ["目标A", "目标B", "时间窗口", "策略反馈"]
        case .relationship: ["变化维度", "公开状态", "代价", "不可逆点"]
        case .secretReveal: ["秘密内容", "知情者", "错误信念来源", "揭示顺序"]
        case .choiceCost: ["选项A", "选项B", "不可兼得原因", "延迟代价"]
        case .imageAction: ["动作主体", "可见对象", "替代解释", "后续回收"]
        }
    }

    private static func questionLibrary(
        for kind: CreativePropositionKind
    ) -> [InformationGainQuestion] {
        func question(
            _ prompt: String,
            _ rationale: String,
            _ variable: String,
            _ options: [String],
            _ gain: Double
        ) -> InformationGainQuestion {
            InformationGainQuestion(
                id: UUID(),
                prompt: prompt,
                rationale: rationale,
                variable: variable,
                options: options,
                expectedInformationGain: gain
            )
        }
        switch kind {
        case .emotion:
            return [
                question(
                    "人物真正感到会被夺走的稀缺资格是什么？",
                    "答案会同时决定威胁对象、社会结构、可用行动与掩饰理由。",
                    "珍视对象",
                    ["公开关注", "只对某人展示的脆弱", "共同记忆", "信任", "群体中的第一顺位"],
                    0.94
                ),
                question("她愿意承认多少？", "决定内外动机是否分裂。", "可承认程度", ["完全否认", "承认不满但否认感情", "只对自己承认"], 0.71)
            ]
        case .trauma:
            return [question("那件事让人物形成了哪条至今仍相信的规则？", "信念决定保护策略及其失效方式。", "形成的信念", ["亲近的人终会离开", "被需要才不会被抛弃", "先离开就不会受伤"], 0.92)]
        case .foreshadowing:
            return [question("未来回收时，观众要重新解释人物的哪一种特质？", "先锁定未来解释，才能控制每条线索的诊断强度。", "未来解释", ["控制欲", "残忍", "勇敢", "虚荣", "精心撒谎"], 0.91)]
        case .microConflict:
            return [question("在这段很短的时间里，双方哪两个状态不能同时成立？", "这是微冲突的最小形式定义。", "目标A", ["公开 / 保密", "立即解决 / 拖延", "靠近 / 保持距离", "拿走 / 留下"], 0.95)]
        case .relationship:
            return [question("本场最想改变关系向量中的哪一维？", "不同维度可以同时向相反方向变化。", "变化维度", ["信任", "亲密", "权力", "依赖", "亏欠", "怨恨", "吸引"], 0.9)]
        case .secretReveal:
            return [question("结束时，观众和人物之间要形成哪种信息差？", "知识分布决定悬念、惊讶或讽刺。", "揭示顺序", ["观众知道，人物不知道", "人物知道，观众不知道", "双方都误解", "两个人知道但彼此不知道对方知道"], 0.96)]
        case .choiceCost:
            return [question("人物最不能同时保住的两样东西是什么？", "如果可以兼得，就还没有形成选择。", "不可兼得原因", ["尊严 / 亲人安全", "真相 / 关系", "自由 / 身份", "复仇 / 无辜者"], 0.95)]
        case .imageAction:
            return [question("这个动作最初允许观众怎样误读？", "替代解释让视觉伏笔既可见又不泄底。", "替代解释", ["体贴", "习惯", "笨拙", "礼貌", "偶然"], 0.86)]
        }
    }

    private static func candidateSeeds(
        for kind: CreativePropositionKind,
        answer: String
    ) -> [CandidateSeed] {
        let subject = answer.isEmpty ? kind.rawValue : answer
        func vector(
            _ causality: Double, _ emotion: Double, _ economy: Double, _ novelty: Double
        ) -> NarrativeObjectiveVector {
            NarrativeObjectiveVector(
                coherence: 0.82,
                causality: causality,
                epistemicLegality: 0.91,
                emotionalCoverage: emotion,
                economy: economy,
                genreFit: 0.72,
                novelty: novelty,
                userPreference: 0.5
            )
        }
        switch kind {
        case .emotion:
            return [
                CandidateSeed(title: "控制局面", thesis: "通过控制夺回“\(subject)”", tactic: "打断", concealment: "用工作或秩序理由解释自己的介入", primaryDimension: .relationship, before: "稀缺资格似乎稳定", after: "权力暂时上升，但真实威胁被看见", cost: "信任下降，控制欲变得可见", obligation: "后续必须回应对方对控制行为的识别", functions: [.escalation, .concealment], objectives: vector(0.91, 0.86, 0.78, 0.62)),
                CandidateSeed(title: "主动退出", thesis: "通过退出否认自己在乎“\(subject)”", tactic: "撤离", concealment: "把受伤重新解释为不屑", primaryDimension: .identity, before: "仍有争取资格的机会", after: "人物保住表面尊严，却主动让出位置", cost: "依赖增加，公开亲密下降", obligation: "后续必须让退出造成的空位产生真实后果", functions: [.choice, .concealment], objectives: vector(0.82, 0.92, 0.84, 0.76)),
                CandidateSeed(title: "贬低竞争者", thesis: "通过攻击竞争者否认“\(subject)”的重要性", tactic: "贬低", concealment: "把情感威胁包装成能力判断", primaryDimension: .belief, before: "威胁仍可被承认为不确定", after: "人物建立一套自我合理化的错误解释", cost: "伤及无辜并暴露判断偏差", obligation: "后续必须用事实测试这套错误信念", functions: [.reveal, .concealment], objectives: vector(0.86, 0.81, 0.73, 0.88))
            ]
        case .trauma:
            return [
                CandidateSeed(title: "讨好以防被抛弃", thesis: "旧伤转化为过度满足他人", tactic: "讨好", concealment: "称之为体贴", primaryDimension: .identity, before: "人物可以表达自己的需要", after: "人物压下需要以换取留在关系中", cost: "短期关系稳定，长期怨恨增加", obligation: "让讨好策略在关键时刻失效", functions: [.setup, .concealment], objectives: vector(0.9, 0.88, 0.78, 0.6)),
                CandidateSeed(title: "测试对方会不会离开", thesis: "旧伤转化为关系测试", tactic: "试探", concealment: "制造一个看似无关的小要求", primaryDimension: .relationship, before: "信任仍可直接建立", after: "信任被改造成必须反复证明的义务", cost: "对方感到被控制", obligation: "回收测试被识破后的反噬", functions: [.escalation, .reveal], objectives: vector(0.84, 0.91, 0.7, 0.82)),
                CandidateSeed(title: "先一步切断关系", thesis: "旧伤转化为主动离开", tactic: "切断", concealment: "称之为理性止损", primaryDimension: .goal, before: "人物仍追求亲密", after: "保护策略取代真实目标", cost: "避免被抛弃，也失去真正想要的连接", obligation: "建立一次必须重新选择靠近或逃离的触发", functions: [.choice, .reversal], objectives: vector(0.88, 0.94, 0.87, 0.71))
            ]
        case .foreshadowing:
            return [
                CandidateSeed(title: "弱线索：可被误读的习惯", thesis: "用日常细节支持“\(subject)”但保留替代解释", tactic: "观察", concealment: "允许被解释为体贴或习惯", primaryDimension: .audience, before: "观众没有假设", after: "未来解释的可能性略微上升", cost: "线索过弱时可能被忽略", obligation: "后续加入一次压力测试线索", functions: [.setup], objectives: vector(0.79, 0.62, 0.93, 0.7)),
                CandidateSeed(title: "中线索：秩序被打破", thesis: "在轻微压力下让“\(subject)”显形", tactic: "追问", concealment: "表面仍可解释为重视秩序", primaryDimension: .audience, before: "替代解释占优", after: "两种解释开始竞争", cost: "可能提前引发观众怀疑", obligation: "回收时必须重写这次追问的含义", functions: [.setup, .escalation], objectives: vector(0.86, 0.68, 0.81, 0.83)),
                CandidateSeed(title: "压力测试：越过边界", thesis: "让“\(subject)”在压力下产生越界行动", tactic: "越界", concealment: "人物仍坚持自己出于善意", primaryDimension: .norm, before: "边界仍被遵守", after: "人物首次为目标违反边界", cost: "诊断性强，也更接近泄底", obligation: "最终回收必须解释此前两条较弱线索", functions: [.reveal, .escalation], objectives: vector(0.9, 0.76, 0.69, 0.9))
            ]
        default:
            return genericSeeds(kind: kind, subject: subject, vector: vector)
        }
    }

    private static func genericSeeds(
        kind: CreativePropositionKind,
        subject: String,
        vector: (Double, Double, Double, Double) -> NarrativeObjectiveVector
    ) -> [CandidateSeed] {
        [
            CandidateSeed(title: "关系路径", thesis: "让“\(subject)”首先改变人物关系", tactic: "要求", concealment: "不解释全部动机", primaryDimension: .relationship, before: "关系维持原平衡", after: "一方获得短暂权力，另一方降低信任", cost: "关系产生新的未解决义务", obligation: "必须测试新的权力分配", functions: [.escalation], objectives: vector(0.9, 0.86, 0.77, 0.63)),
            CandidateSeed(title: "信息差路径", thesis: "让“\(subject)”首先改变谁知道什么", tactic: "隐瞒", concealment: "只提供部分事实", primaryDimension: .belief, before: "人物与观众共享同一解释", after: "人物与观众形成可追踪的信息差", cost: "后续每次行动都必须保持知识合法", obligation: "建立明确的揭示或误解回收点", functions: [.reveal, .concealment], objectives: vector(0.84, 0.74, 0.83, 0.86)),
            CandidateSeed(title: "选择代价路径", thesis: "让“\(subject)”通过不可兼得的选择成立", tactic: "拒绝", concealment: "公开承认代价但不承认真正欲望", primaryDimension: .goal, before: "人物仍试图兼得", after: "人物放弃一项价值以保住另一项", cost: "损失成为不可逆事实", obligation: "后续必须让被放弃的价值再次施压", functions: [.choice, .reversal], objectives: vector(0.93, 0.91, 0.72, 0.74))
        ]
    }

    private static func actionSkeleton(
        actor: String,
        target: String,
        seed: CandidateSeed
    ) -> String {
        """
        【动作骨架 · 不是正文写入】
        1. 用一个可见细节让\(actor)意识到：\(seed.before)。
        2. \(actor)不说真实动机，而是\(seed.tactic)，表面理由是“\(seed.concealment)”。
        3. \(target)没有顺从，并用一个反馈迫使策略暴露代价。
        4. 场面结束时：\(seed.after)。
        5. 新义务：\(seed.obligation)。
        """
    }
}

nonisolated enum NarrativeValidationEngine {
    static func validate(
        patch: StoryPatch,
        against document: CompilerWorkspaceDocument
    ) -> ValidationReport {
        var issues: [NarrativeIssue] = []
        var mutations: [StateMutation] = []
        var obligations: [Obligation] = []
        var resolved: [UUID] = []
        var screenplayPreview = ""

        if patch.baseRevision != document.revision {
            issues.append(issue(
                .continuity,
                .error,
                "补丁基线已过期",
                "Patch 基于 revision \(patch.baseRevision)，当前权威版本是 \(document.revision)。请重新模拟。",
                .l1
            ))
        }

        let locked = document.propositions.filter { $0.status == .locked }
        for operation in patch.operations {
            switch operation {
            case .addProposition(let proposition):
                if proposition.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(issue(.incompleteModel, .error, "空作者命题", "L0 命题没有可验证的原文。", .l0))
                }
            case .addTransition(let transition):
                if transition.actor == nil
                    && transition.actorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(issue(.causalGap, .warning, "行动者尚未决定", "该转移需要作者确认行动者，或明确它是外部事件。", .l2, transition.id))
                }
                if !transition.isEffective {
                    issues.append(issue(.continuity, .error, "无效状态转移", "至少需要一项可说明的 before → after 差异。", .l1, transition.id))
                }
                if transition.intention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(issue(.causalGap, .warning, "缺少当前意图", "行动尚未连接到人物的当前目标。", .l2, transition.id))
                }
                if transition.resistance.isEmpty {
                    issues.append(issue(.incompleteModel, .decision, "尚未建立阻力", "这不代表必须争吵；需要确认什么反馈会迫使策略调整。", .l2, transition.id))
                }
                if transition.effects.contains(where: {
                    $0.dimension == .belief
                        && $0.beforeValue.contains("未知")
                        && transition.trigger == nil
                }) {
                    issues.append(issue(.knowledgeLeak, .error, "知识没有来源", "人物从未知直接进入已知，但当前转移没有获知、观察或推断来源。", .l1, transition.id))
                }
                for condition in transition.preconditions where !conditionSatisfied(condition, state: document.state) {
                    issues.append(issue(.causalGap, .error, "前置条件不成立", "\(condition.subject) 尚不满足“\(condition.operation.rawValue) \(condition.expectedValue)”。", .l1, transition.id))
                }
                for premise in locked {
                    for forbidden in premise.forbiddenOutcomes where violates(forbidden, transition: transition) {
                        issues.append(issue(.authorConstraint, .error, "违反作者锁定禁令", "候选结果触及：\(forbidden)", .l0, transition.id))
                    }
                }
                mutations.append(contentsOf: transition.effects)
            case .addObligation(let value): obligations.append(value)
            case .resolveObligation(let id): resolved.append(id)
            case .updateState(let values): mutations.append(contentsOf: values)
            case .stageScreenplayText(let text): screenplayPreview = text
            }
        }

        let duplicatePropositions = patch.operations.compactMap { operation -> Proposition? in
            if case .addProposition(let value) = operation { value } else { nil }
        }.filter { proposed in document.propositions.contains { $0.id == proposed.id } }
        if !duplicatePropositions.isEmpty {
            issues.append(issue(.continuity, .note, "命题已存在", "提交时会按稳定 ID 去重，不会生成第二份作者公理。", .l1))
        }

        let blocking = issues.contains { $0.severity == .error }
        return ValidationReport(
            valid: !blocking,
            checkedRevision: document.revision,
            issues: issues,
            stateDiff: StateDiff(
                mutations: mutations,
                introducedObligations: obligations,
                resolvedObligationIDs: resolved,
                screenplayPreview: screenplayPreview
            ),
            checkedRuleIDs: document.rules.filter(\.enabled).map(\.id),
            generatedAt: .now
        )
    }

    static func applying(
        _ patch: StoryPatch,
        validation: ValidationReport,
        to document: CompilerWorkspaceDocument,
        trace: RecommendationTrace?
    ) -> CompilerWorkspaceDocument? {
        guard validation.valid,
              patch.baseRevision == document.revision else { return nil }
        var result = document
        for operation in patch.operations {
            switch operation {
            case .addProposition(let value):
                if !result.propositions.contains(where: { $0.id == value.id }) {
                    result.propositions.append(value)
                }
            case .addTransition(let value):
                if !result.transitions.contains(where: { $0.id == value.id }) {
                    result.transitions.append(value)
                }
                apply(value.effects, to: &result.state, transitionID: value.id)
            case .addObligation(let value):
                if !result.obligations.contains(where: { $0.id == value.id }) {
                    result.obligations.append(value)
                }
            case .resolveObligation(let id):
                if let index = result.obligations.firstIndex(where: { $0.id == id }) {
                    result.obligations[index].status = .satisfied
                }
            case .updateState(let values):
                apply(values, to: &result.state, transitionID: nil)
            case .stageScreenplayText:
                // Text is intentionally not part of NSIR commit. The caller may
                // present and apply it through the screenplay editor separately.
                break
            }
        }
        result.stagedPatches.removeAll { $0.id == patch.id }
        result.validationHistory.append(validation)
        if let trace { result.recommendationTraces.append(trace) }
        result.revision += 1
        result.updatedAt = .now
        return result
    }

    static func minimumRepairs(for report: ValidationReport) -> [Alternative] {
        report.issues.filter { $0.severity == .error }.flatMap { issue in
            switch issue.kind {
            case .knowledgeLeak:
                [
                    Alternative(id: UUID(), title: "增加获知事件", difference: "在依赖知识前加入观察、听闻或可靠推断。"),
                    Alternative(id: UUID(), title: "改为猜测", difference: "保留行为，但把确定知识降为怀疑。"),
                    Alternative(id: UUID(), title: "删除知识依赖", difference: "让行动由当前可知事实触发。")
                ]
            case .authorConstraint:
                [Alternative(id: UUID(), title: "保留作者禁令", difference: "只调整候选结果，不修改 L0 命题。")]
            case .causalGap:
                [Alternative(id: UUID(), title: "补前置转移", difference: "以最小新事件建立当前缺少的原因。")]
            default:
                [Alternative(id: UUID(), title: "最小局部修复", difference: "只修改报告定位的状态差异，不重写整条路线。")]
            }
        }
    }

    static func audit(_ document: CompilerWorkspaceDocument) -> [NarrativeIssue] {
        var issues: [NarrativeIssue] = []
        let transitionIDs = Set(document.transitions.map(\.id))
        if transitionIDs.count != document.transitions.count {
            issues.append(issue(.continuity, .error, "转移 ID 重复", "NSIR 中存在重复稳定 ID，无法可靠建立因果图。", .l1))
        }
        for transition in document.transitions {
            if !transition.isEffective {
                issues.append(issue(.continuity, .error, "无效权威转移", "\(transition.title) 没有 before → after 差异。", .l1, transition.id))
            }
            for predecessor in transition.partialOrderPredecessorIDs {
                if predecessor == transition.id {
                    issues.append(issue(.causalGap, .error, "因果自环", "转移不能把自己作为前置条件。", .l1, transition.id))
                } else if !transitionIDs.contains(predecessor) {
                    issues.append(issue(.causalGap, .error, "缺失因果前置", "\(transition.title) 引用了不存在的前置转移。", .l1, transition.id))
                }
            }
            if transition.dramaticFunctions.contains(.payoff),
               transition.partialOrderPredecessorIDs.isEmpty {
                issues.append(issue(.unresolvedSetup, .warning, "回收没有可追溯设置", "该转移标为回收，但没有连接任何前置线索。", .l1, transition.id))
            }
        }
        if containsCausalCycle(document.transitions) {
            issues.append(issue(.causalGap, .error, "部分序因果图存在环", "至少一组转移互相要求对方先发生。", .l1))
        }

        var lastValueByKey: [String: String] = [:]
        for transition in document.transitions {
            for mutation in transition.effects where mutation.isEffective {
                let holder = mutation.holderID?.uuidString ?? "global"
                let key = "\(mutation.dimension.code)|\(holder)|\(mutation.subject)"
                if let last = lastValueByKey[key],
                   !mutation.beforeValue.contains("未知"),
                   !mutation.beforeValue.contains("尚未"),
                   last.localizedCaseInsensitiveCompare(mutation.beforeValue) != .orderedSame {
                    issues.append(issue(
                        .continuity,
                        .warning,
                        "状态链断裂",
                        "\(mutation.subject) 上一次为“\(last)”，当前却从“\(mutation.beforeValue)”开始。",
                        .l1,
                        transition.id
                    ))
                }
                lastValueByKey[key] = mutation.afterValue
            }
        }

        for map in document.sourceMaps {
            for transitionID in map.transitionIDs where !transitionIDs.contains(transitionID) {
                issues.append(issue(.semanticDrift, .warning, "来源映射悬空", "文本范围仍指向已不存在的转移。", .l1, transitionID))
            }
            if map.alignmentConfidence < 0.45 {
                issues.append(issue(.semanticDrift, .decision, "低置信度文本对齐", "文本与 NSIR 的实现关系需要作者确认。", .l2, map.transitionIDs.first))
            }
        }
        return issues
    }

    private static func apply(
        _ mutations: [StateMutation],
        to state: inout StoryState,
        transitionID: TransitionID?
    ) {
        for mutation in mutations where mutation.isEffective {
            let holder = mutation.holderID?.uuidString ?? "global"
            let key = "\(mutation.dimension.code)|\(holder)|\(mutation.subject)"
            state.indexedValues[key] = mutation.afterValue
            switch mutation.dimension {
            case .world:
                state.worldFacts[mutation.subject] = mutation.afterValue
            case .belief:
                if let holderID = mutation.holderID {
                    state.beliefs.removeAll { $0.holderID == holderID && $0.subject == mutation.subject }
                    state.beliefs.append(Belief(
                        holderID: holderID,
                        subject: mutation.subject,
                        value: mutation.afterValue,
                        truthStatus: mutation.truthStatus,
                        learnedAtTransitionID: transitionID
                    ))
                }
            case .goal:
                if let holderID = mutation.holderID {
                    state.goals.append(Goal(ownerID: holderID, desiredState: mutation.afterValue))
                }
            case .audience:
                state.audience.knows.append(mutation.afterValue)
            case .motif:
                state.motifStates[mutation.subject] = mutation.afterValue
            case .relationship, .norm, .affect, .identity, .resource:
                break
            }
        }
    }

    private static func conditionSatisfied(_ condition: Condition, state: StoryState) -> Bool {
        let holder = condition.holderID?.uuidString ?? "global"
        let key = "\(condition.dimension.code)|\(holder)|\(condition.subject)"
        let value = state.indexedValues[key]
        switch condition.operation {
        case .equals: return value == condition.expectedValue
        case .notEquals: return value != condition.expectedValue
        case .contains: return value?.localizedCaseInsensitiveContains(condition.expectedValue) == true
        case .exists: return value != nil
        case .notExists: return value == nil
        }
    }

    private static func violates(_ forbidden: String, transition: DramaticTransition) -> Bool {
        let normalized = forbidden
            .replacingOccurrences(of: "不能", with: "")
            .replacingOccurrences(of: "不得", with: "")
            .replacingOccurrences(of: "绝不", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 3 else { return false }
        let outcome = transition.effects.map(\.afterValue).joined(separator: " ")
        return outcome.localizedCaseInsensitiveContains(normalized)
    }

    private static func issue(
        _ kind: NarrativeIssueKind,
        _ severity: IssueSeverity,
        _ title: String,
        _ detail: String,
        _ ruleClass: RuleClass,
        _ transitionID: TransitionID? = nil
    ) -> NarrativeIssue {
        NarrativeIssue(
            id: UUID(),
            kind: kind,
            severity: severity,
            title: title,
            detail: detail,
            ruleClass: ruleClass,
            evidence: [],
            transitionID: transitionID
        )
    }

    private static func containsCausalCycle(_ transitions: [DramaticTransition]) -> Bool {
        let predecessors = Dictionary(uniqueKeysWithValues: transitions.map {
            ($0.id, $0.partialOrderPredecessorIDs)
        })
        var visiting: Set<UUID> = []
        var visited: Set<UUID> = []
        func visit(_ id: UUID) -> Bool {
            if visiting.contains(id) { return true }
            if visited.contains(id) { return false }
            visiting.insert(id)
            for predecessor in predecessors[id] ?? [] where predecessors[predecessor] != nil {
                if visit(predecessor) { return true }
            }
            visiting.remove(id)
            visited.insert(id)
            return false
        }
        return transitions.contains { visit($0.id) }
    }
}

nonisolated enum NarrativeConstraintKind: String, Hashable, Sendable {
    case preserveAuthorAxiom
    case effectiveTransition
    case causalFeedback
    case explicitCost
    case introducedObligation
    case structuralDifference
}

nonisolated struct WeightedNarrativeConstraint: Sendable {
    var kind: NarrativeConstraintKind
    var ruleClass: RuleClass
    var weight: Double
    var hard: Bool
}

nonisolated struct ConstraintEvaluation: Sendable {
    var hardConstraintsSatisfied: Bool
    var softUtility: Double
    var failures: [NarrativeConstraintKind]
}

/// Deterministic weighted-constraint and beam gate. `softUtility` is only an
/// internal search heuristic; it is never presented as a story-quality score.
nonisolated enum NarrativeConstraintSolver {
    static let standardConstraints = [
        WeightedNarrativeConstraint(kind: .preserveAuthorAxiom, ruleClass: .l0, weight: 1, hard: true),
        WeightedNarrativeConstraint(kind: .effectiveTransition, ruleClass: .l1, weight: 1, hard: true),
        WeightedNarrativeConstraint(kind: .causalFeedback, ruleClass: .l2, weight: 0.78, hard: false),
        WeightedNarrativeConstraint(kind: .explicitCost, ruleClass: .l2, weight: 0.72, hard: false),
        WeightedNarrativeConstraint(kind: .introducedObligation, ruleClass: .l1, weight: 0.9, hard: true),
        WeightedNarrativeConstraint(kind: .structuralDifference, ruleClass: .l4, weight: 0.58, hard: false)
    ]

    static func search(
        _ proposals: [CompilerCandidate],
        proposition: Proposition,
        beamWidth: Int = 3
    ) -> [CompilerCandidate] {
        let evaluated = proposals.map { candidate in
            (candidate, evaluate(candidate, proposition: proposition))
        }
        let legal = evaluated.filter { $0.1.hardConstraintsSatisfied }
        let beam = legal
            .sorted { lhs, rhs in
                if lhs.1.softUtility == rhs.1.softUtility {
                    return lhs.0.id.uuidString < rhs.0.id.uuidString
                }
                return lhs.1.softUtility > rhs.1.softUtility
            }
            .prefix(max(beamWidth, 1))
            .map { $0.0 }
        return NarrativeCompilerEngine.paretoFront(beam.isEmpty ? proposals : beam)
    }

    static func evaluate(
        _ candidate: CompilerCandidate,
        proposition: Proposition
    ) -> ConstraintEvaluation {
        var failures: [NarrativeConstraintKind] = []
        var satisfiedWeight = 0.0
        var totalSoftWeight = 0.0
        for constraint in standardConstraints {
            let satisfied: Bool
            switch constraint.kind {
            case .preserveAuthorAxiom:
                satisfied = candidate.patch.operations.contains { operation in
                    if case .addProposition(let value) = operation {
                        return value.id == proposition.id && value.originalText == proposition.originalText
                    }
                    return false
                }
            case .effectiveTransition:
                satisfied = !candidate.transitions.isEmpty
                    && candidate.transitions.allSatisfy(\.isEffective)
            case .causalFeedback:
                satisfied = candidate.transitions.contains { !$0.resistance.isEmpty }
            case .explicitCost:
                satisfied = candidate.transitions.contains { !$0.cost.isEmpty }
            case .introducedObligation:
                satisfied = candidate.patch.operations.contains {
                    if case .addObligation = $0 { return true }
                    return false
                }
            case .structuralDifference:
                satisfied = !candidate.thesis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if !satisfied { failures.append(constraint.kind) }
            if !constraint.hard {
                totalSoftWeight += constraint.weight
                if satisfied { satisfiedWeight += constraint.weight }
            }
        }
        let hardKinds = Set(standardConstraints.filter(\.hard).map(\.kind))
        return ConstraintEvaluation(
            hardConstraintsSatisfied: failures.allSatisfy { !hardKinds.contains($0) },
            softUtility: totalSoftWeight == 0 ? 0 : satisfiedWeight / totalSoftWeight,
            failures: failures
        )
    }
}
