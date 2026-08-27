import Foundation
import SwiftData

enum ProjectModuleKind: String, CaseIterable, Codable, Identifiable {
    case inspiration = "核心灵感"
    case source = "原始素材"
    case research = "研究档案"
    case character = "人物"
    case relationship = "人物关系"
    case world = "世界"
    case theme = "主题"
    case storyPath = "故事路径"
    case structure = "结构"
    case scene = "场景"
    case blueprint = "全本路线"
    case screenplay = "正式剧本"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .inspiration: "lightbulb.fill"
        case .source: "doc.text.fill"
        case .research: "books.vertical.fill"
        case .character: "person.crop.circle.fill"
        case .relationship: "person.2.fill"
        case .world: "globe.asia.australia.fill"
        case .theme: "scope"
        case .storyPath: "signpost.right.and.left.fill"
        case .structure: "point.3.connected.trianglepath.dotted"
        case .scene: "rectangle.stack.fill"
        case .blueprint: "tree.fill"
        case .screenplay: "text.book.closed.fill"
        }
    }

    var defaultTitle: String {
        switch self {
        case .inspiration: "新的灵感"
        case .source: "原始素材"
        case .research: "研究笔记"
        case .character: "人物设想"
        case .relationship: "关系设计"
        case .world: "世界规则"
        case .theme: "主题命题"
        case .storyPath: "故事选择"
        case .structure: "结构设计"
        case .scene: "场景卡"
        case .blueprint: "全本路线"
        case .screenplay: "剧本段落"
        }
    }

    var promptFocus: String {
        switch self {
        case .inspiration:
            "发现这份灵感最独特、最值得持续生长的戏剧承诺。"
        case .source:
            "严格区分事实与虚构，从素材中提取可持续升级的欲望、阻碍、关系与代价。"
        case .research:
            "把资料转化为人物处境、制度压力、历史回声和可拍摄的现实细节。"
        case .character:
            "围绕目标、需求、错误信念、关系压力和可见选择塑造人物。"
        case .relationship:
            "让关系同时包含情感需要、权力差、秘密、背叛风险和改变人物的能力。"
        case .world:
            "让规则、资源、制度与地点限制人物选择并持续制造冲突。"
        case .theme:
            "把关键词变成主角与对抗力量用行动争论的价值命题。"
        case .storyPath:
            "延续已经确认的故事事实，只改变当前一步的具体走法与代价。"
        case .structure:
            "把事件组织成不可逆选择、因果升级、转折与高潮，而不是情节清单。"
        case .scene:
            "建立即时目标、阻力、策略变化、情绪转折和离场后的局面变化。"
        case .blueprint:
            "尊重全部已确认决定，形成连续、可写、可拍的全本因果路线。"
        case .screenplay:
            "用可拍摄动作、有效对白、潜台词和视觉信息完成正式剧本内容。"
        }
    }

    var workspaceSection: WorkspaceSection {
        switch self {
        case .character, .relationship: .characters
        case .world: .world
        case .theme: .theme
        case .storyPath: .journey
        case .structure, .blueprint: .structure
        case .scene: .scenes
        case .screenplay: .screenplay
        case .inspiration, .source, .research: .overview
        }
    }
}

enum ProjectModuleStatus: String, CaseIterable, Codable, Identifiable {
    case seed = "等待生长"
    case optionsReady = "等待选择"
    case reviewing = "人工审阅"
    case integrated = "已入正式内容"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .seed: "leaf"
        case .optionsReady: "square.grid.2x2"
        case .reviewing: "pencil.and.outline"
        case .integrated: "checkmark.seal.fill"
        }
    }
}

struct ProjectModuleOption: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let oneLine: String
    let draftText: String
    let storyEffect: String
    let tradeoff: String
    let preservedIdeas: [String]
    let responseToFeedback: String

    init(
        id: UUID = UUID(),
        title: String,
        oneLine: String,
        draftText: String,
        storyEffect: String,
        tradeoff: String,
        preservedIdeas: [String] = [],
        responseToFeedback: String = ""
    ) {
        self.id = id
        self.title = title
        self.oneLine = oneLine
        self.draftText = draftText
        self.storyEffect = storyEffect
        self.tradeoff = tradeoff
        self.preservedIdeas = preservedIdeas
        self.responseToFeedback = responseToFeedback
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, oneLine, draftText, storyEffect, tradeoff, preservedIdeas
        case responseToFeedback
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        title = container.projectString(forKey: .title, fallback: "未命名方向")
        oneLine = container.projectString(forKey: .oneLine)
        draftText = container.projectString(forKey: .draftText)
        storyEffect = container.projectString(forKey: .storyEffect)
        tradeoff = container.projectString(forKey: .tradeoff)
        preservedIdeas = container.projectStringArray(forKey: .preservedIdeas)
        responseToFeedback = container.projectString(forKey: .responseToFeedback)
    }
}

struct ProjectModuleOptionsResult: Decodable {
    let guidance: String
    let options: [ProjectModuleOption]

    private enum CodingKeys: String, CodingKey {
        case guidance, options
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guidance = container.projectString(forKey: .guidance)
        options = (try? container.decode([ProjectModuleOption].self, forKey: .options)) ?? []
    }
}

struct ProjectModuleRefinementResult: Decodable {
    let revisedText: String
    let changeSummary: String
    let preservedIdeas: [String]

    private enum CodingKeys: String, CodingKey {
        case revisedText, changeSummary, preservedIdeas
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revisedText = container.projectString(forKey: .revisedText)
        changeSummary = container.projectString(forKey: .changeSummary)
        preservedIdeas = container.projectStringArray(forKey: .preservedIdeas)
    }
}

struct ProjectModuleRevision: Codable, Identifiable, Hashable {
    let id: UUID
    let text: String
    let note: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        note: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.text = text
        self.note = note
        self.createdAt = createdAt
    }
}

enum ProjectReviewOperation: String, CaseIterable, Codable, Identifiable {
    case deepen = "深化"
    case add = "增加"
    case remove = "删除"
    case replace = "替换"
    case sharpen = "强化"
    case simplify = "收紧"
    case reframe = "换个角度"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .deepen: "person.crop.circle.badge.plus"
        case .add: "plus.circle"
        case .remove: "minus.circle"
        case .replace: "arrow.triangle.2.circlepath"
        case .sharpen: "bolt.fill"
        case .simplify: "arrow.down.right.and.arrow.up.left"
        case .reframe: "viewfinder"
        }
    }

    var instruction: String {
        switch self {
        case .deepen: "深化指定部分，让行为、欲望、矛盾和关系更立体，但不要用背景说明代替戏剧行动。"
        case .add: "只增加作者要求的内容，并说明新增内容如何改变后续故事。"
        case .remove: "删除作者指出的问题，同时修复删除后产生的因果断裂。"
        case .replace: "替换指定元素，保留其原有叙事功能与已经确认的上下文。"
        case .sharpen: "强化冲突、差异或表达力度，让效果更明确但不过度夸张。"
        case .simplify: "压缩重复与解释，保留最有戏、最具作者个性的核心。"
        case .reframe: "保留核心事实，从不同人物、关系、价值或观看角度重新设计。"
        }
    }
}

struct ProjectReviewRound: Codable, Identifiable, Hashable {
    let id: UUID
    let operationRawValue: String
    let scope: String
    let feedback: String
    let selectedDirection: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        operation: ProjectReviewOperation,
        scope: String,
        feedback: String,
        selectedDirection: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.operationRawValue = operation.rawValue
        self.scope = scope
        self.feedback = feedback
        self.selectedDirection = selectedDirection
        self.createdAt = createdAt
    }

    var operation: ProjectReviewOperation {
        ProjectReviewOperation(rawValue: operationRawValue) ?? .deepen
    }
}

@Model
final class ProjectArtifact {
    @Attribute(.unique) var id: UUID
    var title: String
    var kindRawValue: String
    var statusRawValue: String
    var originLabel: String
    var humanInput: String
    var lockedIdeas: String
    var workingText: String
    var acceptedText: String
    var aiInstruction: String
    var aiSummary: String
    var optionsData: Data
    var selectedOptionID: UUID?
    var revisionsData: Data
    var integratedSnapshot: String
    var integrationIsDetached: Bool = false
    var reviewFeedback: String = ""
    var reviewOperationRawValue: String = ProjectReviewOperation.deepen.rawValue
    var reviewScope: String = ""
    var authorGuidanceText: String = ""
    var reviewRoundsData: Data = Data()
    var researchQuery: String = ""
    var researchResultData: Data = Data()
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date
    var project: StoryProject?

    init(
        id: UUID = UUID(),
        title: String,
        kind: ProjectModuleKind,
        status: ProjectModuleStatus = .seed,
        originLabel: String = "用户灵感",
        humanInput: String = "",
        lockedIdeas: String = "",
        workingText: String = "",
        acceptedText: String = "",
        aiInstruction: String = "",
        aiSummary: String = "",
        sortIndex: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        project: StoryProject? = nil
    ) {
        self.id = id
        self.title = title
        self.kindRawValue = kind.rawValue
        self.statusRawValue = status.rawValue
        self.originLabel = originLabel
        self.humanInput = humanInput
        self.lockedIdeas = lockedIdeas
        self.workingText = workingText
        self.acceptedText = acceptedText
        self.aiInstruction = aiInstruction
        self.aiSummary = aiSummary
        self.optionsData = Data()
        self.revisionsData = Data()
        self.integratedSnapshot = ""
        self.reviewFeedback = ""
        self.reviewOperationRawValue = ProjectReviewOperation.deepen.rawValue
        self.reviewScope = ""
        self.authorGuidanceText = ""
        self.reviewRoundsData = Data()
        self.researchQuery = ""
        self.researchResultData = Data()
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.project = project
    }
}

@MainActor
extension ProjectArtifact {
    var kind: ProjectModuleKind {
        get { ProjectModuleKind(rawValue: kindRawValue) ?? .inspiration }
        set { kindRawValue = newValue.rawValue }
    }

    var status: ProjectModuleStatus {
        get { ProjectModuleStatus(rawValue: statusRawValue) ?? .seed }
        set { statusRawValue = newValue.rawValue }
    }

    var options: [ProjectModuleOption] {
        get {
            PersistentPayloadCodec.decode(
                [ProjectModuleOption].self,
                from: optionsData,
                default: [],
                label: "ProjectArtifact.options"
            )
        }
        set {
            optionsData = PersistentPayloadCodec.encode(
                newValue,
                preserving: optionsData,
                label: "ProjectArtifact.options"
            )
            updatedAt = .now
        }
    }

    var revisions: [ProjectModuleRevision] {
        get {
            PersistentPayloadCodec.decode(
                [ProjectModuleRevision].self,
                from: revisionsData,
                default: [],
                label: "ProjectArtifact.revisions"
            )
        }
        set {
            revisionsData = PersistentPayloadCodec.encode(
                newValue,
                preserving: revisionsData,
                label: "ProjectArtifact.revisions"
            )
            updatedAt = .now
        }
    }

    var selectedOption: ProjectModuleOption? {
        guard let selectedOptionID else { return nil }
        return options.first { $0.id == selectedOptionID }
    }

    var reviewOperation: ProjectReviewOperation {
        get {
            ProjectReviewOperation(rawValue: reviewOperationRawValue) ?? .deepen
        }
        set {
            reviewOperationRawValue = newValue.rawValue
        }
    }

    var reviewRounds: [ProjectReviewRound] {
        get {
            PersistentPayloadCodec.decode(
                [ProjectReviewRound].self,
                from: reviewRoundsData,
                default: [],
                label: "ProjectArtifact.reviewRounds"
            )
        }
        set {
            reviewRoundsData = PersistentPayloadCodec.encode(
                newValue,
                preserving: reviewRoundsData,
                label: "ProjectArtifact.reviewRounds"
            )
            updatedAt = .now
        }
    }

    var researchResult: RealityResearchResult? {
        get {
            PersistentPayloadCodec.decodeOptional(
                RealityResearchResult.self,
                from: researchResultData,
                label: "ProjectArtifact.researchResult"
            )
        }
        set {
            if let newValue {
                researchResultData = PersistentPayloadCodec.encode(
                    newValue,
                    preserving: researchResultData,
                    label: "ProjectArtifact.researchResult"
                )
            } else {
                researchResultData = Data()
            }
            updatedAt = .now
        }
    }

    func captureReview() -> ProjectReviewRound? {
        let feedback = reviewFeedback.projectTrimmed
        guard !feedback.isEmpty else { return nil }
        let round = ProjectReviewRound(
            operation: reviewOperation,
            scope: reviewScope.projectTrimmed,
            feedback: feedback,
            selectedDirection: selectedOption?.title ?? title
        )
        var all = reviewRounds
        all.insert(round, at: 0)
        reviewRounds = Array(all.prefix(40))

        let scopeText = round.scope.isEmpty ? "当前模块" : round.scope
        let guidance = "• \(reviewOperation.rawValue)「\(scopeText)」：\(feedback)"
        if !authorGuidanceText.contains(guidance) {
            authorGuidanceText = authorGuidanceText.projectTrimmed.isEmpty
                ? guidance
                : "\(authorGuidanceText.projectTrimmed)\n\(guidance)"
        }
        aiInstruction = """
        用户已选择“\(round.selectedDirection)”，现在提出新的审阅意见。
        操作：\(reviewOperation.rawValue)
        修改范围：\(scopeText)
        意见：\(feedback)
        执行原则：\(reviewOperation.instruction)
        请理解意见背后的创作意图，围绕它重新设计4个有实质差异的候选；不要只做同义改写。
        """
        updatedAt = .now
        return round
    }

    func select(_ option: ProjectModuleOption) {
        if !workingText.projectTrimmed.isEmpty {
            recordRevision(note: "选择新方向前")
        }
        selectedOptionID = option.id
        workingText = option.draftText
        aiSummary = option.storyEffect
        status = .reviewing
        updatedAt = .now
    }

    func recordRevision(note: String) {
        let snapshot = workingText.projectTrimmed
        guard !snapshot.isEmpty, revisions.first?.text != snapshot else { return }
        var all = revisions
        all.insert(ProjectModuleRevision(text: snapshot, note: note), at: 0)
        revisions = Array(all.prefix(30))
    }

    func confirmAndIntegrate() {
        guard let project else { return }
        let approved = workingText.projectTrimmed
        guard !approved.isEmpty else { return }

        recordRevision(note: status == .integrated ? "重新确认前" : "确认入稿")
        acceptedText = approved
        guard projectionTexts(in: project).allSatisfy(canReplaceManagedBlock(in:)) else {
            integrationIsDetached = true
            status = .reviewing
            updatedAt = .now
            return
        }
        let newBlock = managedBlock(for: approved)
        integrationIsDetached = false

        switch kind {
        case .inspiration, .character, .relationship:
            project.notes = replacingManagedBlock(in: project.notes, with: newBlock)
        case .source, .research:
            project.sourceFacts = replacingManagedBlock(in: project.sourceFacts, with: newBlock)
        case .world:
            project.worldText = replacingManagedBlock(in: project.worldText, with: newBlock)
        case .theme:
            project.themeText = replacingManagedBlock(in: project.themeText, with: newBlock)
        case .storyPath:
            project.storyPathText = replacingManagedBlock(in: project.storyPathText, with: newBlock)
        case .structure:
            project.structureText = replacingManagedBlock(in: project.structureText, with: newBlock)
        case .scene:
            project.scenesText = replacingManagedBlock(in: project.scenesText, with: newBlock)
        case .blueprint:
            project.blueprintText = replacingManagedBlock(in: project.blueprintText, with: newBlock)
            project.structureText = replacingManagedBlock(in: project.structureText, with: newBlock)
            project.scenesText = replacingManagedBlock(in: project.scenesText, with: newBlock)
        case .screenplay:
            project.screenplayText = replacingManagedBlock(in: project.screenplayText, with: newBlock)
        }

        integratedSnapshot = newBlock
        status = .integrated
        aiInstruction = ""
        updatedAt = .now
        project.touch()
    }

    func reopenForReview() {
        if workingText.projectTrimmed.isEmpty {
            workingText = acceptedText
        }
        status = .reviewing
        updatedAt = .now
    }

    func withdrawFromFormalContent() {
        guard let project, !integratedSnapshot.isEmpty else {
            status = .reviewing
            return
        }

        guard projectionTexts(in: project).allSatisfy(canReplaceManagedBlock(in:)) else {
            integrationIsDetached = true
            updatedAt = .now
            return
        }

        switch kind {
        case .inspiration, .character, .relationship:
            project.notes = removingManagedBlock(from: project.notes)
        case .source, .research:
            project.sourceFacts = removingManagedBlock(from: project.sourceFacts)
        case .world:
            project.worldText = removingManagedBlock(from: project.worldText)
        case .theme:
            project.themeText = removingManagedBlock(from: project.themeText)
        case .storyPath:
            project.storyPathText = removingManagedBlock(from: project.storyPathText)
        case .structure:
            project.structureText = removingManagedBlock(from: project.structureText)
        case .scene:
            project.scenesText = removingManagedBlock(from: project.scenesText)
        case .blueprint:
            project.blueprintText = removingManagedBlock(from: project.blueprintText)
            project.structureText = removingManagedBlock(from: project.structureText)
            project.scenesText = removingManagedBlock(from: project.scenesText)
        case .screenplay:
            project.screenplayText = removingManagedBlock(from: project.screenplayText)
        }

        integratedSnapshot = ""
        integrationIsDetached = false
        status = .reviewing
        updatedAt = .now
        project.touch()
    }

    private var managedStartMarker: String {
        "/* StoryMentor Artifact \(id.uuidString) BEGIN */"
    }

    private var managedEndMarker: String {
        "/* StoryMentor Artifact \(id.uuidString) END */"
    }

    private func managedBlock(for text: String) -> String {
        """
        \(managedStartMarker)
        【\(title)】
        \(text)
        \(managedEndMarker)
        """
    }

    private func projectionTexts(in project: StoryProject) -> [String] {
        switch kind {
        case .inspiration, .character, .relationship:
            [project.notes]
        case .source, .research:
            [project.sourceFacts]
        case .world:
            [project.worldText]
        case .theme:
            [project.themeText]
        case .storyPath:
            [project.storyPathText]
        case .structure:
            [project.structureText]
        case .scene:
            [project.scenesText]
        case .blueprint:
            [project.blueprintText, project.structureText, project.scenesText]
        case .screenplay:
            [project.screenplayText]
        }
    }

    private func canReplaceManagedBlock(in current: String) -> Bool {
        guard !integratedSnapshot.isEmpty else { return true }
        if let range = managedRange(in: current) {
            return String(current[range]) == integratedSnapshot
        }
        return current.range(of: integratedSnapshot) != nil
    }

    private func replacingManagedBlock(in current: String, with replacement: String) -> String {
        if let range = managedRange(in: current) {
            var result = current
            result.replaceSubrange(range, with: replacement)
            return result
        }
        if !integratedSnapshot.isEmpty,
           let range = current.range(of: integratedSnapshot) {
            var result = current
            result.replaceSubrange(range, with: replacement)
            return result
        }
        guard !current.projectTrimmed.isEmpty else { return replacement }
        return "\(current.projectTrimmed)\n\n\(replacement)"
    }

    private func removingManagedBlock(from current: String) -> String {
        if let range = managedRange(in: current) {
            var result = current
            result.removeSubrange(range)
            return result.projectTrimmed
        }
        guard let range = current.range(of: integratedSnapshot) else {
            return current
        }
        var result = current
        result.removeSubrange(range)
        return result.projectTrimmed
    }

    private func managedRange(in current: String) -> Range<String.Index>? {
        guard let start = current.range(of: managedStartMarker)?.lowerBound,
              let endMarkerRange = current.range(
                of: managedEndMarker,
                range: start..<current.endIndex
              ) else {
            return nil
        }
        return start..<endMarkerRange.upperBound
    }
}

private extension KeyedDecodingContainer {
    func projectString(forKey key: Key, fallback: String = "") -> String {
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) { return String(value) }
        if let values = try? decode([String].self, forKey: key) {
            return values.joined(separator: "\n")
        }
        return fallback
    }

    func projectStringArray(forKey key: Key) -> [String] {
        if let values = try? decode([String].self, forKey: key) { return values }
        if let value = try? decode(String.self, forKey: key), !value.isEmpty { return [value] }
        return []
    }
}

private extension String {
    var projectTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
