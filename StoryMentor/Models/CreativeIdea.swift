import Foundation

enum CreativeIdeaScope: String, CaseIterable, Codable, Identifiable {
    case project = "从现在影响全本"
    case stage = "只影响当前大节拍"
    case inbox = "先存进灵感盒"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .project: "arrow.triangle.branch"
        case .stage: "scope"
        case .inbox: "tray.full"
        }
    }

    var explanation: String {
        switch self {
        case .project:
            "之后的人物、结构、场景和剧本生成都会优先考虑。"
        case .stage:
            "只改变当前大节拍的四个候选，不污染后面的创作方向。"
        case .inbox:
            "先安全保存，等你决定启用时再交给 AI。"
        }
    }
}

struct CreativeIdea: Codable, Identifiable, Hashable {
    var id: UUID
    var text: String
    var scopeRawValue: String
    var targetStageIndex: Int?
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        scope: CreativeIdeaScope,
        targetStageIndex: Int? = nil,
        isActive: Bool? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.text = text
        scopeRawValue = scope.rawValue
        self.targetStageIndex = targetStageIndex
        self.isActive = isActive ?? (scope != .inbox)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var scope: CreativeIdeaScope {
        get { CreativeIdeaScope(rawValue: scopeRawValue) ?? .inbox }
        set { scopeRawValue = newValue.rawValue }
    }

    var promptLine: String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch scope {
        case .project:
            return "全本方向：\(clean)"
        case .stage:
            return "当前大节拍：\(clean)"
        case .inbox:
            return clean
        }
    }
}

extension StoryProject {
    @MainActor
    var creativeIdeas: [CreativeIdea] {
        get {
            PersistentPayloadCodec.decode(
                [CreativeIdea].self,
                from: creativeIdeasData,
                default: [],
                label: "StoryProject.creativeIdeas"
            )
        }
        set {
            creativeIdeasData = PersistentPayloadCodec.encode(
                newValue,
                preserving: creativeIdeasData,
                label: "StoryProject.creativeIdeas"
            )
            touch()
        }
    }

    @MainActor
    var activeCreativeIdeas: [CreativeIdea] {
        creativeIdeas
            .filter(\.isActive)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    @MainActor
    func creativeIdeas(for stageIndex: Int?) -> [CreativeIdea] {
        activeCreativeIdeas.filter { idea in
            switch idea.scope {
            case .project:
                return true
            case .stage:
                return stageIndex != nil && idea.targetStageIndex == stageIndex
            case .inbox:
                return false
            }
        }
    }

    @MainActor
    func creativeContext(for stageIndex: Int? = nil) -> String {
        let baseline = creativeDirectionText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let scopedIdeas = Array(creativeIdeas(for: stageIndex).prefix(10))
        var remainingIdeaCharacters = 12_000
        var injectedLines: [String] = []
        for (index, idea) in scopedIdeas.enumerated() {
            let laterIdeas = scopedIdeas.dropFirst(index + 1)
            let reservedForLaterIdeas = laterIdeas.reduce(0) {
                $0 + min($1.promptLine.count, 600)
            }
            let available = max(
                0,
                remainingIdeaCharacters - reservedForLaterIdeas
            )
            let allowance = min(4_100, available)
            guard allowance > 0 else { continue }
            let excerpt = String(idea.promptLine.prefix(allowance))
            injectedLines.append(excerpt)
            remainingIdeaCharacters -= excerpt.count
        }
        let injected = injectedLines.joined(separator: "\n")

        let blocks = [
            injected.isEmpty ? nil : "作者后来注入、从现在起生效的想法：\n\(injected)",
            baseline.isEmpty ? nil : "长期创作方向：\(String(baseline.prefix(4_000)))"
        ].compactMap { $0 }

        let context = blocks.isEmpty
            ? "作者暂未指定额外方向。"
            : blocks.joined(separator: "\n")
        return String(context.prefix(18_000))
    }

    @MainActor
    func protectedCreativeContext(for stageIndex: Int? = nil) -> String {
        """
        【作者创意指令 · 未经摘要 · 必须优先执行】
        \(creativeContext(for: stageIndex))

        \(dramaticSemanticFoundationPrompt)
        """
    }

    @MainActor
    func latestCreativeChange(for stageIndex: Int?) -> Date? {
        let scopedChanges = creativeIdeas
            .filter { idea in
                switch idea.scope {
                case .project:
                    return true
                case .stage:
                    return stageIndex != nil && idea.targetStageIndex == stageIndex
                case .inbox:
                    return false
                }
            }
            .map(\.updatedAt)
        return (scopedChanges + [creativeIdeasContextUpdatedAt].compactMap { $0 }).max()
    }

    @MainActor
    func addCreativeIdea(
        text: String,
        scope: CreativeIdeaScope,
        stageIndex: Int?
    ) -> UUID? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        var ideas = creativeIdeas
        let idea = CreativeIdea(
            text: String(clean.prefix(4_000)),
            scope: scope,
            targetStageIndex: scope == .stage ? stageIndex : nil
        )
        ideas.insert(
            idea,
            at: 0
        )
        creativeIdeas = Array(ideas.prefix(80))
        if scope != .inbox {
            creativeIdeasContextUpdatedAt = .now
        }
        return idea.id
    }

    @MainActor
    func setCreativeIdeaActive(_ ideaID: UUID, active: Bool) {
        var ideas = creativeIdeas
        guard let index = ideas.firstIndex(where: { $0.id == ideaID }) else { return }
        let affectedCurrentContext = ideas[index].scope == .project
            || (
                ideas[index].scope == .stage
                    && ideas[index].targetStageIndex == nextStructureStageIndex
            )
        if active, ideas[index].scope == .inbox {
            ideas[index].scope = .project
            ideas[index].targetStageIndex = nil
        }
        ideas[index].isActive = active
        ideas[index].updatedAt = .now
        let nowAffectsCurrentContext = ideas[index].scope == .project
            || (
                ideas[index].scope == .stage
                    && ideas[index].targetStageIndex == nextStructureStageIndex
            )
        creativeIdeas = ideas
        if affectedCurrentContext || nowAffectsCurrentContext {
            creativeIdeasContextUpdatedAt = .now
        }
    }

    @MainActor
    func removeCreativeIdea(_ ideaID: UUID) {
        let removed = creativeIdeas.first { $0.id == ideaID }
        creativeIdeas = creativeIdeas.filter { $0.id != ideaID }
        if removed?.isActive == true,
           removed?.scope == .project
            || (
                removed?.scope == .stage
                    && removed?.targetStageIndex == nextStructureStageIndex
            ) {
            creativeIdeasContextUpdatedAt = .now
        }
    }
}
