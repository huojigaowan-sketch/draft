import Foundation

extension String {
    nonisolated var storyScienceTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated enum StorySciencePhase: String, CaseIterable, Codable, Identifiable, Sendable {
    case incubator = "故事培养舱"
    case laboratory = "正念实验室"
    case compiler = "故事编译器"

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .incubator: "培养"
        case .laboratory: "实验"
        case .compiler: "生产"
        }
    }

    var systemImage: String {
        switch self {
        case .incubator: "leaf.fill"
        case .laboratory: "flask.fill"
        case .compiler: "text.book.closed.fill"
        }
    }

    var tintRole: String {
        switch self {
        case .incubator: "mint"
        case .laboratory: "accent"
        case .compiler: "warm"
        }
    }
}

nonisolated enum StoryAtomType: String, CaseIterable, Codable, Identifiable, Sendable {
    case character = "人物"
    case emotion = "情绪"
    case image = "画面"
    case event = "事件"
    case worldRule = "世界规则"
    case dialogue = "对白"
    case relationship = "关系"
    case unknown = "未知"
    case choice = "选择"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .character: "person.fill"
        case .emotion: "heart.fill"
        case .image: "photo.fill"
        case .event: "bolt.fill"
        case .worldRule: "globe.asia.australia.fill"
        case .dialogue: "quote.bubble.fill"
        case .relationship: "point.3.connected.trianglepath.dotted"
        case .unknown: "questionmark"
        case .choice: "arrow.triangle.branch"
        }
    }
}

nonisolated struct StoryAtom: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var content: String
    var type: StoryAtomType
    var importance: Double

    init(
        id: UUID = UUID(),
        content: String,
        type: StoryAtomType,
        importance: Double = 0.5
    ) {
        self.id = id
        self.content = content
        self.type = type
        self.importance = min(max(importance, 0), 1)
    }
}

nonisolated enum HumanNeed: String, CaseIterable, Codable, Identifiable, Sendable {
    case physiological = "生存"
    case safety = "安全"
    case belonging = "归属"
    case esteem = "尊严"
    case selfActualization = "自我实现"

    var id: String { rawValue }
}

nonisolated struct CharacterPsychology: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var character: String
    var need: HumanNeed
    var desire: String
    var fear: String
    var wound: String
    var belief: String
    var defense: String
    var contradiction: String

    init(
        id: UUID = UUID(),
        character: String,
        need: HumanNeed,
        desire: String,
        fear: String,
        wound: String = "尚待发现",
        belief: String = "尚待发现",
        defense: String = "尚待发现",
        contradiction: String
    ) {
        self.id = id
        self.character = character
        self.need = need
        self.desire = desire
        self.fear = fear
        self.wound = wound
        self.belief = belief
        self.defense = defense
        self.contradiction = contradiction
    }
}

nonisolated enum StoryExperimentAxis: String, CaseIterable, Codable, Identifiable, Sendable {
    case character = "人物实验"
    case conflict = "冲突实验"
    case world = "世界实验"
    case theme = "主题实验"
    case ending = "结局实验"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .character: "person.crop.circle.badge.questionmark"
        case .conflict: "arrow.left.and.right.circle.fill"
        case .world: "globe.desk.fill"
        case .theme: "scope"
        case .ending: "flag.pattern.checkered"
        }
    }
}

nonisolated struct StoryExperimentVariable: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var question: String
    var options: [String]

    init(
        id: UUID = UUID(),
        name: String,
        question: String,
        options: [String]
    ) {
        self.id = id
        self.name = name
        self.question = question
        self.options = Array(options.filter { !$0.storyScienceTrimmed.isEmpty }.prefix(5))
    }
}

nonisolated struct StoryExperiment: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var axis: StoryExperimentAxis
    var title: String
    var hypothesis: String
    var whyItMatters: String
    var variables: [StoryExperimentVariable]

    init(
        id: UUID = UUID(),
        axis: StoryExperimentAxis,
        title: String,
        hypothesis: String,
        whyItMatters: String,
        variables: [StoryExperimentVariable]
    ) {
        self.id = id
        self.axis = axis
        self.title = title
        self.hypothesis = hypothesis
        self.whyItMatters = whyItMatters
        self.variables = Array(variables.prefix(1))
    }
}

nonisolated enum MindfulReviewDisposition: String, CaseIterable, Codable, Identifiable, Sendable {
    case accepted = "接受这个方向"
    case rejected = "保留原版"
    case modified = "带着修改继续"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .accepted: "checkmark.circle.fill"
        case .rejected: "arrow.uturn.backward.circle.fill"
        case .modified: "pencil.circle.fill"
        }
    }
}

nonisolated enum StoryExperimentChoiceOrigin: String, Codable, Identifiable, Sendable {
    case aiSuggestion = "AI 建议"
    case authorDesigned = "作者自定"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .aiSuggestion: "sparkles"
        case .authorDesigned: "pencil.and.outline"
        }
    }
}

nonisolated struct StoryExperimentChoiceRecord: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var round: Int
    var axis: StoryExperimentAxis
    var variableID: UUID
    var variableName: String
    var prompt: String
    var aiCandidates: [String]
    var finalValue: String
    var source: StoryExperimentChoiceOrigin
    var selectedCandidateIndex: Int?
    var selectedAt: Date

    init(
        schemaVersion: Int = 1,
        round: Int,
        axis: StoryExperimentAxis,
        variableID: UUID,
        variableName: String,
        prompt: String,
        aiCandidates: [String],
        finalValue: String,
        source: StoryExperimentChoiceOrigin,
        selectedCandidateIndex: Int?,
        selectedAt: Date = .now
    ) {
        self.schemaVersion = schemaVersion
        self.round = round
        self.axis = axis
        self.variableID = variableID
        self.variableName = variableName
        self.prompt = prompt
        self.aiCandidates = aiCandidates
        self.finalValue = finalValue
        self.source = source
        self.selectedCandidateIndex = selectedCandidateIndex
        self.selectedAt = selectedAt
    }
}

nonisolated struct StoryExperimentComparison: Codable, Hashable, Sendable {
    var conditionChange: String
    var structureChange: String
    var characterChange: String
    var dialogueChange: String
    var emotionChange: String
    var invariants: [String]
    var questions: [String]

    static func comparing(
        baseline: StoryCultivationSnapshot,
        variant: StoryCultivationSnapshot,
        decision: StoryExperimentDecision
    ) -> StoryExperimentComparison {
        let selection = decision.selectedValues.first
        let condition = selection.map { "\($0.key)：\($0.value)" } ?? "尚未记录条件"
        let stableItems = [
            baseline.crystal.coreIdea == variant.crystal.coreIdea ? "故事核心" : nil,
            baseline.crystal.characterInsight == variant.crystal.characterInsight ? "人物洞察" : nil,
            baseline.crystal.conflict == variant.crystal.conflict ? "核心冲突" : nil,
            baseline.crystal.theme == variant.crystal.theme ? "主题假设" : nil
        ].compactMap { $0 }

        return StoryExperimentComparison(
            conditionChange: condition,
            structureChange: changeDescription(
                before: baseline.crystal.conflict,
                after: variant.crystal.conflict,
                unchanged: "核心冲突暂未改变"
            ),
            characterChange: changeDescription(
                before: baseline.crystal.characterInsight,
                after: variant.crystal.characterInsight,
                unchanged: "人物洞察保持不变"
            ),
            dialogueChange: "本轮没有代写台词；作者原文保持不变。",
            emotionChange: changeDescription(
                before: baseline.crystal.whyInteresting,
                after: variant.crystal.whyInteresting,
                unchanged: "情绪吸引力的判断保持不变"
            ),
            invariants: stableItems.isEmpty ? ["原始创意与作者意图"] : stableItems,
            questions: [
                "哪些变化确实由“\(condition)”引发，而不是来自其他假设？",
                "什么仍然可以保持？为什么它比环境更稳定？",
                "这个对照让你注意到原版中的哪个隐含前提？"
            ]
        )
    }

    private static func changeDescription(
        before: String,
        after: String,
        unchanged: String
    ) -> String {
        let cleanBefore = before.storyScienceTrimmed
        let cleanAfter = after.storyScienceTrimmed
        guard cleanBefore != cleanAfter else { return unchanged }
        return "原版：\(cleanBefore)\n变体：\(cleanAfter)"
    }
}

nonisolated struct StoryExperimentDecision: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var experimentID: UUID
    var experimentTitle: String
    var selectedValues: [String: String]
    var authorObservation: String
    var selectedVariableName: String?
    var selectedOptionIndex: Int?
    var choiceRecord: StoryExperimentChoiceRecord?
    var comparison: StoryExperimentComparison?
    var reviewDisposition: MindfulReviewDisposition?
    var choiceReason: String?
    var authorRevision: String?
    var newDiscovery: String?
    var reviewedAt: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        experimentID: UUID,
        experimentTitle: String,
        selectedValues: [String: String],
        authorObservation: String,
        selectedVariableName: String? = nil,
        selectedOptionIndex: Int? = nil,
        choiceRecord: StoryExperimentChoiceRecord? = nil,
        comparison: StoryExperimentComparison? = nil,
        reviewDisposition: MindfulReviewDisposition? = nil,
        choiceReason: String? = nil,
        authorRevision: String? = nil,
        newDiscovery: String? = nil,
        reviewedAt: Date? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.experimentID = experimentID
        self.experimentTitle = experimentTitle
        self.selectedValues = selectedValues
        self.authorObservation = authorObservation
        self.selectedVariableName = selectedVariableName
        self.selectedOptionIndex = selectedOptionIndex
        self.choiceRecord = choiceRecord
        self.comparison = comparison
        self.reviewDisposition = reviewDisposition
        self.choiceReason = choiceReason
        self.authorRevision = authorRevision
        self.newDiscovery = newDiscovery
        self.reviewedAt = reviewedAt
        self.createdAt = createdAt
    }
}

nonisolated struct StoryPotentialEvaluation: Codable, Hashable, Sendable {
    var strengths: [String]
    var gaps: [String]
    var nextStep: String

    static let empty = StoryPotentialEvaluation(
        strengths: [],
        gaps: [],
        nextStep: "先把一个真实吸引你的碎片放进培养舱。"
    )
}

nonisolated struct StoryCrystal: Codable, Hashable, Sendable {
    var coreIdea: String
    var characterInsight: String
    var conflict: String
    var theme: String
    var whyInteresting: String

    static let empty = StoryCrystal(
        coreIdea: "",
        characterInsight: "",
        conflict: "",
        theme: "",
        whyInteresting: ""
    )

    var isReadyForProduction: Bool {
        !coreIdea.storyScienceTrimmed.isEmpty
            && !characterInsight.storyScienceTrimmed.isEmpty
            && !conflict.storyScienceTrimmed.isEmpty
    }

    var compilerProposition: String {
        """
        【故事核心】
        \(coreIdea)

        【人物洞察】
        \(characterInsight)

        【不可两全的冲突】
        \(conflict)

        【主题假设】
        \(theme)

        【为什么值得追随】
        \(whyInteresting)
        """
    }
}

nonisolated struct StoryCultivationSnapshot: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var rawIdea: String
    var atoms: [StoryAtom]
    var characters: [String]
    var humanNeeds: [HumanNeed]
    var desires: [String]
    var fears: [String]
    var contradictions: [String]
    var valueConflicts: [String]
    var dramaticQuestions: [String]
    var themes: [String]
    var psychology: [CharacterPsychology]
    var discovery: String
    var hiddenQuestion: String
    var experiments: [StoryExperiment]
    var decisions: [StoryExperimentDecision]
    var evaluation: StoryPotentialEvaluation
    var crystal: StoryCrystal
    var round: Int
    var provenanceNote: String

    static func empty(rawIdea: String = "") -> StoryCultivationSnapshot {
        StoryCultivationSnapshot(
            schemaVersion: 1,
            rawIdea: rawIdea,
            atoms: [],
            characters: [],
            humanNeeds: [],
            desires: [],
            fears: [],
            contradictions: [],
            valueConflicts: [],
            dramaticQuestions: [],
            themes: [],
            psychology: [],
            discovery: "",
            hiddenQuestion: "",
            experiments: [],
            decisions: [],
            evaluation: .empty,
            crystal: .empty,
            round: 0,
            provenanceNote: ""
        )
    }

    var hasAnalysis: Bool {
        !discovery.storyScienceTrimmed.isEmpty && !experiments.isEmpty
    }
}

nonisolated struct StoryExperimentCandidate: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var decision: StoryExperimentDecision
    var baseline: StoryCultivationSnapshot
    var proposal: StoryCultivationSnapshot
    var comparison: StoryExperimentComparison
    var createdAt: Date

    init(
        id: UUID = UUID(),
        decision: StoryExperimentDecision,
        baseline: StoryCultivationSnapshot,
        proposal: StoryCultivationSnapshot,
        comparison: StoryExperimentComparison,
        createdAt: Date = .now
    ) {
        self.id = id
        self.decision = decision
        self.baseline = baseline
        self.proposal = proposal
        self.comparison = comparison
        self.createdAt = createdAt
    }

    func resolvedSnapshot(
        disposition: MindfulReviewDisposition,
        choiceReason: String,
        authorRevision: String,
        newDiscovery: String
    ) -> StoryCultivationSnapshot {
        var reviewedDecision = decision
        reviewedDecision.comparison = comparison
        reviewedDecision.reviewDisposition = disposition
        reviewedDecision.choiceReason = choiceReason.storyScienceTrimmed
        reviewedDecision.authorRevision = authorRevision.storyScienceTrimmed
        reviewedDecision.newDiscovery = newDiscovery.storyScienceTrimmed
        reviewedDecision.reviewedAt = .now

        var resolved = disposition == .rejected ? baseline : proposal
        resolved.decisions = baseline.decisions + [reviewedDecision]
        return resolved
    }
}
