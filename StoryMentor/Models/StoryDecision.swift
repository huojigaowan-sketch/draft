import Foundation
import SwiftData

enum JourneyPhase: String, CaseIterable, Codable, Identifiable {
    case protagonistCore = "主人公矛盾"
    case urgency = "为何必须现在"
    case antagonist = "对抗力量"
    case keyRelationship = "关键关系"
    case worldPressure = "环境压力"
    case irreversibleChoice = "第一次不可逆选择"
    case midpoint = "中点反转"
    case lowestPoint = "最低谷"
    case climaxChoice = "高潮选择"
    case endingImage = "结尾意象"

    var id: String { rawValue }

    static let ordered: [JourneyPhase] = [
        .protagonistCore, .urgency, .antagonist, .keyRelationship, .worldPressure,
        .irreversibleChoice, .midpoint, .lowestPoint, .climaxChoice, .endingImage
    ]

    var instruction: String {
        switch self {
        case .protagonistCore: "确定主人公最有戏的内在矛盾。"
        case .urgency: "设计为什么故事必须在此刻开始。"
        case .antagonist: "设计会主动调整策略的对抗力量。"
        case .keyRelationship: "建立情感需求与背叛风险并存的关系。"
        case .worldPressure: "让制度、地点或资源持续增加代价。"
        case .irreversibleChoice: "让主人公主动越过无法退回的边界。"
        case .midpoint: "用揭示或反转改写后半程策略。"
        case .lowestPoint: "让旧方法造成最大损失。"
        case .climaxChoice: "用不能两全的行动回答主题。"
        case .endingImage: "用具体画面显示故事已经改变。"
        }
    }
}

enum StoryPaceMode: String, CaseIterable, Codable, Identifiable {
    case accelerate = "加速推进"
    case deepen = "延长加深"
    case miniClimax = "小高潮"
    case revelation = "平缓揭示"
    case release = "情绪缓冲"

    var id: String { rawValue }

    var instruction: String {
        switch self {
        case .accelerate: "提高单位时间内有效情境更新的影响总量，并缩短状态变化后的反应间隔。"
        case .deepen: "不靠增加事件数量，让同一行动扩大关系、认知、承诺或目标变化的深度与代价。"
        case .miniClimax: "让一条局部状态链结算，并产生高不可逆性的事实、关系或承诺变化。"
        case .revelation: "用人物认知与观众认知的不对称变化改写后续选择，不要求身体伤害。"
        case .release: "降低有效更新密度，让人物消化此前变化，但仍为下一次状态转移建立明确条件。"
        }
    }
}

enum StoryTargetEmotion: String, CaseIterable, Codable, Identifiable {
    case curiosity = "好奇"
    case tension = "紧张"
    case fear = "恐惧"
    case grief = "悲伤"
    case anger = "愤怒"
    case intimacy = "亲密"
    case hope = "希望"
    case awe = "震撼"

    var id: String { rawValue }
}

struct StagePacingPlan: Codable, Identifiable, Hashable {
    var id: Int { stageIndex }
    var stageIndex: Int
    var paceModeRawValue: String
    var intensity: Double
    var targetEmotionRawValue: String
    var eventScale: String
    var authorNote: String
    var updatedAt: Date?

    init(
        stageIndex: Int,
        paceMode: StoryPaceMode,
        intensity: Double,
        targetEmotion: StoryTargetEmotion,
        eventScale: String,
        authorNote: String = "",
        updatedAt: Date? = nil
    ) {
        self.stageIndex = stageIndex
        paceModeRawValue = paceMode.rawValue
        self.intensity = min(100, max(0, intensity))
        targetEmotionRawValue = targetEmotion.rawValue
        self.eventScale = eventScale
        self.authorNote = authorNote
        self.updatedAt = updatedAt
    }

    var paceMode: StoryPaceMode {
        get { StoryPaceMode(rawValue: paceModeRawValue) ?? .deepen }
        set { paceModeRawValue = newValue.rawValue }
    }

    var targetEmotion: StoryTargetEmotion {
        get { StoryTargetEmotion(rawValue: targetEmotionRawValue) ?? .curiosity }
        set { targetEmotionRawValue = newValue.rawValue }
    }

    var promptBlock: String {
        """
        【本阶段节奏与情绪硬约束】
        节奏唯一计算口径：Σ(每次有效 W/K/G/R/D/E 状态变化的影响值) ÷ 本阶段时长。
        字数、句数、剪辑次数、动作数量和情绪形容词都不能代替有效情境更新。
        推进方式：\(paceMode.rawValue)
        执行定义：\(paceMode.instruction)
        情绪强度：\(Int(intensity))/100
        目标情绪：\(targetEmotion.rawValue)
        事件尺度：\(eventScale)
        作者补充：\(authorNote.isEmpty ? "无" : authorNote)
        这是创作目标，不是正文实测值。四个候选必须写清准备造成的 before → after 状态差异，
        分别说明如何兑现这些约束，不能用无关的大事件或更多文字虚假提速。
        """
    }

    static func suggested(stageIndex: Int, total: Int) -> StagePacingPlan {
        let denominator = Double(max(total - 1, 1))
        let position = Double(stageIndex) / denominator
        let intensity: Double
        let mode: StoryPaceMode
        let emotion: StoryTargetEmotion
        let scale: String

        switch position {
        case ..<0.18:
            intensity = 32 + position * 80
            mode = .deepen
            emotion = .curiosity
            scale = "人物、关系或规则出现第一次偏差"
        case ..<0.48:
            intensity = 48 + position * 38
            mode = .accelerate
            emotion = .tension
            scale = "新阻碍、新人物或计划升级"
        case ..<0.62:
            intensity = 72
            mode = .miniClimax
            emotion = .awe
            scale = "局部胜负、重大揭示或不可逆损失"
        case ..<0.82:
            intensity = 64 + position * 25
            mode = .accelerate
            emotion = .fear
            scale = "危机收紧、盟友流失或代价兑现"
        default:
            intensity = min(100, 72 + position * 28)
            mode = .miniClimax
            emotion = position > 0.94 ? .awe : .tension
            scale = "高潮选择、关系结算或最终余波"
        }
        return StagePacingPlan(
            stageIndex: stageIndex,
            paceMode: mode,
            intensity: intensity,
            targetEmotion: emotion,
            eventScale: scale
        )
    }
}

struct StoryOptionRevision: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let pitch: String
    let concreteDetail: String
    let consequence: String
    let futurePressure: String
    let sampleMoment: String
    let evidenceBasis: [String]
    let realityTexture: String
    let instruction: String
    let createdAt: Date

    init(option: StoryChoiceOption, instruction: String, createdAt: Date = .now) {
        id = UUID()
        title = option.title
        pitch = option.pitch
        concreteDetail = option.concreteDetail
        consequence = option.consequence
        futurePressure = option.futurePressure
        sampleMoment = option.sampleMoment
        evidenceBasis = option.evidenceBasis
        realityTexture = option.realityTexture
        self.instruction = instruction
        self.createdAt = createdAt
    }
}

struct StoryChoiceOption: Codable, Identifiable, Hashable {
    var id: UUID
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
    var plannedStateChanges: [DramaticStateMutation]?
    var audienceUpdate: String?
    var forbiddenChanges: [String]?
    var isLiked: Bool
    var feedback: String
    var revisions: [StoryOptionRevision]

    init(
        id: UUID = UUID(),
        title: String,
        pitch: String,
        concreteDetail: String,
        consequence: String,
        futurePressure: String,
        sampleMoment: String,
        evidenceBasis: [String] = [],
        sourceCount: Int = 0,
        realityTexture: String = "",
        paceEffect: String = "",
        emotionShift: String = "",
        eventScale: String = "",
        plannedStateChanges: [DramaticStateMutation]? = nil,
        audienceUpdate: String? = nil,
        forbiddenChanges: [String]? = nil,
        isLiked: Bool = false,
        feedback: String = "",
        revisions: [StoryOptionRevision] = []
    ) {
        self.id = id
        self.title = title
        self.pitch = pitch
        self.concreteDetail = concreteDetail
        self.consequence = consequence
        self.futurePressure = futurePressure
        self.sampleMoment = sampleMoment
        self.evidenceBasis = evidenceBasis
        self.sourceCount = sourceCount
        self.realityTexture = realityTexture
        self.paceEffect = paceEffect
        self.emotionShift = emotionShift
        self.eventScale = eventScale
        self.plannedStateChanges = plannedStateChanges
        self.audienceUpdate = audienceUpdate
        self.forbiddenChanges = forbiddenChanges
        self.isLiked = isLiked
        self.feedback = feedback
        self.revisions = revisions
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, pitch, concreteDetail, consequence, futurePressure, sampleMoment
        case evidenceBasis, sourceCount, realityTexture, paceEffect, emotionShift, eventScale
        case plannedStateChanges, audienceUpdate, forbiddenChanges
        case isLiked, feedback, revisions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "未命名选择"
        pitch = try container.decodeIfPresent(String.self, forKey: .pitch) ?? ""
        concreteDetail = try container.decodeIfPresent(String.self, forKey: .concreteDetail) ?? ""
        consequence = try container.decodeIfPresent(String.self, forKey: .consequence) ?? ""
        futurePressure = try container.decodeIfPresent(String.self, forKey: .futurePressure) ?? ""
        sampleMoment = try container.decodeIfPresent(String.self, forKey: .sampleMoment) ?? ""
        evidenceBasis = try container.decodeIfPresent([String].self, forKey: .evidenceBasis) ?? []
        sourceCount = try container.decodeIfPresent(Int.self, forKey: .sourceCount) ?? 0
        realityTexture = try container.decodeIfPresent(String.self, forKey: .realityTexture) ?? ""
        paceEffect = try container.decodeIfPresent(String.self, forKey: .paceEffect) ?? ""
        emotionShift = try container.decodeIfPresent(String.self, forKey: .emotionShift) ?? ""
        eventScale = try container.decodeIfPresent(String.self, forKey: .eventScale) ?? ""
        plannedStateChanges = try container.decodeIfPresent(
            [DramaticStateMutation].self,
            forKey: .plannedStateChanges
        )
        audienceUpdate = try container.decodeIfPresent(String.self, forKey: .audienceUpdate)
        forbiddenChanges = try container.decodeIfPresent([String].self, forKey: .forbiddenChanges)
        isLiked = try container.decodeIfPresent(Bool.self, forKey: .isLiked) ?? false
        feedback = try container.decodeIfPresent(String.self, forKey: .feedback) ?? ""
        revisions = try container.decodeIfPresent(
            [StoryOptionRevision].self,
            forKey: .revisions
        ) ?? []
    }

    mutating func applyRefinement(
        _ replacement: StoryChoiceOption,
        instruction: String
    ) {
        let archived = StoryOptionRevision(option: self, instruction: instruction)
        revisions.append(archived)
        title = replacement.title
        pitch = replacement.pitch
        concreteDetail = replacement.concreteDetail
        consequence = replacement.consequence
        futurePressure = replacement.futurePressure
        sampleMoment = replacement.sampleMoment
        evidenceBasis = replacement.evidenceBasis
        sourceCount = replacement.sourceCount
        realityTexture = replacement.realityTexture
        paceEffect = replacement.paceEffect
        emotionShift = replacement.emotionShift
        eventScale = replacement.eventScale
        plannedStateChanges = replacement.plannedStateChanges
        audienceUpdate = replacement.audienceUpdate
        forbiddenChanges = replacement.forbiddenChanges
        feedback = instruction
    }

    var preferenceText: String {
        [
            title, pitch, concreteDetail, consequence, futurePressure, realityTexture,
            paceEffect, emotionShift, eventScale,
            audienceUpdate ?? "", forbiddenChanges?.joined(separator: " ") ?? "",
            plannedStateChanges?.map {
                "\($0.dimension.rawValue) \($0.subject) \($0.beforeValue) \($0.afterValue)"
            }.joined(separator: " ") ?? ""
        ]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct JourneyDecisionResult: Decodable {
    let question: String
    let coachNote: String
    let options: [StoryChoiceOption]

    private enum CodingKeys: String, CodingKey { case question, coachNote, options }

    init(question: String, coachNote: String, options: [StoryChoiceOption]) {
        self.question = question
        self.coachNote = coachNote
        self.options = options
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        question = try container.decodeIfPresent(
            String.self,
            forKey: .question
        ) ?? "接下来，哪一种变化最吸引你？"
        coachNote = try container.decodeIfPresent(String.self, forKey: .coachNote) ?? ""
        options = try container.decodeIfPresent([StoryChoiceOption].self, forKey: .options) ?? []
    }
}

struct JourneyOptionRefinementResult: Decodable {
    let option: StoryChoiceOption
}

struct BlueprintScene: Decodable, Identifiable {
    let id = UUID()
    let number: Int
    let title: String
    let purpose: String
    let conflict: String
    let turningPoint: String
    let endingHook: String

    private enum CodingKeys: String, CodingKey {
        case number, title, purpose, conflict, turningPoint, endingHook
    }

    init(
        number: Int,
        title: String,
        purpose: String,
        conflict: String,
        turningPoint: String,
        endingHook: String
    ) {
        self.number = number
        self.title = title
        self.purpose = purpose
        self.conflict = conflict
        self.turningPoint = turningPoint
        self.endingHook = endingHook
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        number = try container.decodeIfPresent(Int.self, forKey: .number) ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "未命名场景"
        purpose = try container.decodeIfPresent(String.self, forKey: .purpose) ?? ""
        conflict = try container.decodeIfPresent(String.self, forKey: .conflict) ?? ""
        turningPoint = try container.decodeIfPresent(String.self, forKey: .turningPoint) ?? ""
        endingHook = try container.decodeIfPresent(String.self, forKey: .endingHook) ?? ""
    }
}

struct JourneyBlueprint: Decodable {
    let title: String
    let logline: String
    let theme: String
    let protagonistArc: String
    let antagonistDesign: String
    let actOne: String
    let actTwo: String
    let actThree: String
    let scenes: [BlueprintScene]
    let nextWritingTask: String

    private enum CodingKeys: String, CodingKey {
        case title, logline, theme, protagonistArc, antagonistDesign
        case actOne, actTwo, actThree, scenes, nextWritingTask
    }

    init(
        title: String,
        logline: String,
        theme: String,
        protagonistArc: String,
        antagonistDesign: String,
        actOne: String,
        actTwo: String,
        actThree: String,
        scenes: [BlueprintScene],
        nextWritingTask: String
    ) {
        self.title = title
        self.logline = logline
        self.theme = theme
        self.protagonistArc = protagonistArc
        self.antagonistDesign = antagonistDesign
        self.actOne = actOne
        self.actTwo = actTwo
        self.actThree = actThree
        self.scenes = scenes
        self.nextWritingTask = nextWritingTask
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        logline = try container.decodeIfPresent(String.self, forKey: .logline) ?? ""
        theme = try container.decodeIfPresent(String.self, forKey: .theme) ?? ""
        protagonistArc = try container.decodeIfPresent(String.self, forKey: .protagonistArc) ?? ""
        antagonistDesign = try container.decodeIfPresent(String.self, forKey: .antagonistDesign) ?? ""
        actOne = try container.decodeIfPresent(String.self, forKey: .actOne) ?? ""
        actTwo = try container.decodeIfPresent(String.self, forKey: .actTwo) ?? ""
        actThree = try container.decodeIfPresent(String.self, forKey: .actThree) ?? ""
        scenes = try container.decodeIfPresent([BlueprintScene].self, forKey: .scenes) ?? []
        nextWritingTask = try container.decodeIfPresent(String.self, forKey: .nextWritingTask) ?? ""
    }
}

@Model
final class StoryDecision {
    @Attribute(.unique) var id: UUID
    var phaseRawValue: String
    var stageIndex: Int = 0
    var question: String
    var coachNote: String
    var optionsData: Data
    var selectedOptionID: UUID?
    var selectedAnswerText: String
    var authorBrief: String = ""
    var authorBriefUpdatedAt: Date?
    var optionsGeneratedAt: Date?
    var optionsContextFingerprint: String = ""
    @Transient var optionsRequestToken: UUID?
    var researchQuery: String = ""
    var researchDepthRawValue: String = ResearchDepth.deep.rawValue
    var researchResultData: Data = Data()
    var researchUpdatedAt: Date?
    var createdAt: Date
    var resolvedAt: Date?
    var project: StoryProject?

    init(
        id: UUID = UUID(),
        stageName: String,
        stageIndex: Int,
        question: String,
        coachNote: String,
        options: [StoryChoiceOption],
        selectedOptionID: UUID? = nil,
        selectedAnswerText: String = "",
        authorBrief: String = "",
        researchQuery: String = "",
        researchDepth: ResearchDepth = .deep,
        createdAt: Date = .now,
        resolvedAt: Date? = nil,
        project: StoryProject? = nil
    ) {
        self.id = id
        phaseRawValue = stageName
        self.stageIndex = stageIndex
        self.question = question
        self.coachNote = coachNote
        optionsData = PersistentPayloadCodec.encode(
            options,
            preserving: Data(),
            label: "StoryDecision.options"
        )
        self.selectedOptionID = selectedOptionID
        self.selectedAnswerText = selectedAnswerText
        self.authorBrief = authorBrief
        self.researchQuery = researchQuery
        researchDepthRawValue = researchDepth.rawValue
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.project = project
    }
}

extension StoryDecision {
    var stageName: String { phaseRawValue }

    var phase: JourneyPhase {
        JourneyPhase(rawValue: phaseRawValue) ?? .protagonistCore
    }

    var options: [StoryChoiceOption] {
        get {
            PersistentPayloadCodec.decode(
                [StoryChoiceOption].self,
                from: optionsData,
                default: [],
                label: "StoryDecision.options"
            )
        }
        set {
            optionsData = PersistentPayloadCodec.encode(
                newValue,
                preserving: optionsData,
                label: "StoryDecision.options"
            )
        }
    }

    var selectedOption: StoryChoiceOption? {
        guard let selectedOptionID else { return nil }
        return options.first { $0.id == selectedOptionID }
    }

    var researchDepth: ResearchDepth {
        get { ResearchDepth(rawValue: researchDepthRawValue) ?? .deep }
        set { researchDepthRawValue = newValue.rawValue }
    }

    @MainActor
    var researchResult: RealityResearchResult? {
        get {
            PersistentPayloadCodec.decodeOptional(
                RealityResearchResult.self,
                from: researchResultData,
                label: "StoryDecision.researchResult"
            )
        }
        set {
            if let newValue {
                researchResultData = PersistentPayloadCodec.encode(
                    newValue,
                    preserving: researchResultData,
                    label: "StoryDecision.researchResult"
                )
            } else {
                researchResultData = Data()
            }
            if newValue == nil {
                researchUpdatedAt = nil
            } else {
                researchUpdatedAt = .now
            }
        }
    }
}
