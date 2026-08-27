import Foundation

struct StoryBibleSyncOutcome {
    let revision: Int
    let note: String
}

private struct StoryBibleProjection {
    let character: String
    let world: String
    let theme: String
    let conflict: String

    var digest: String {
        """
        【人物小传】
        \(character)

        【世界规则】
        \(world)

        【主题命题】
        \(theme)

        【核心冲突】
        \(conflict)
        """
    }
}

@MainActor
struct StoryBibleSyncEngine {
    let settings: AISettingsStore

    func synchronize(_ project: StoryProject) async -> StoryBibleSyncOutcome {
        let locked = project.decisions
            .filter { $0.selectedOption != nil }
            .sorted { $0.stageIndex < $1.stageIndex }

        guard !locked.isEmpty else {
            return StoryBibleSyncOutcome(
                revision: project.storyBibleRevision,
                note: "还没有需要同步的锁定选择"
            )
        }

        let ledger = locked.compactMap { decision -> String? in
            guard let option = decision.selectedOption else { return nil }
            return """
            【\(decision.stageIndex + 1) · \(decision.stageName)】
            \(option.title)：\(option.pitch)
            具体事实：\(option.concreteDetail)
            代价：\(option.consequence)
            后续压力：\(option.futurePressure)
            现实质感：\(option.realityTexture)
            """
        }
        .joined(separator: "\n\n")

        let fallback = deterministicProjection(for: project, decisions: locked)
        let localInput = """
        【作者现有内容】
        人物：\(project.characters.map {
            "\($0.role.rawValue) \($0.name)：\($0.seedText)；目标 \($0.externalGoal)；需求 \($0.internalNeed)；恐惧 \($0.fear)；弧线 \($0.arc)"
        }.joined(separator: "\n"))
        世界：\(project.worldText)
        主题：\(project.themeText)
        核心戏剧问题：\(project.dramaticPromise)

        【已锁定选择账本】
        \(ledger)

        \(project.dramaticSemanticFoundationPrompt)
        """

        let localResult = settings.useApplePreprocessing
            ? await AppleTextService.projectStoryBible(localInput)
            : nil
        let projection = localResult
            .flatMap(parseProjection)
            ?? fallback
        let usedAppleModel = localResult.flatMap(parseProjection) != nil

        project.characterBibleText = projection.character
        project.worldBibleText = projection.world
        project.themeBibleText = projection.theme
        project.coreConflictText = projection.conflict
        project.storyBibleDigest = projection.digest
        project.storyBibleRevision += 1
        project.storyBibleUpdatedAt = .now
        project.storyBibleSyncNote = usedAppleModel
            ? "Apple Foundation Models 已在本机增量同步，未消耗 DeepSeek Token"
            : "已用确定性增量规则同步，未消耗 DeepSeek Token"

        if !projection.world.isPlaceholder {
            project.worldText = replacingManagedBlock(
                in: project.worldText,
                with: projection.world
            )
        }
        if !projection.theme.isPlaceholder {
            project.themeText = replacingManagedBlock(
                in: project.themeText,
                with: projection.theme
            )
        }
        if let protagonist = project.characters.first(where: { $0.role == .protagonist }),
           !projection.character.isPlaceholder {
            protagonist.seedText = replacingManagedBlock(
                in: protagonist.seedText,
                with: projection.character
            )
            protagonist.touch()
        }

        project.touch()
        return StoryBibleSyncOutcome(
            revision: project.storyBibleRevision,
            note: project.storyBibleSyncNote
        )
    }

    private func parseProjection(_ text: String) -> StoryBibleProjection? {
        let character = section("人物小传", in: text)
        let world = section("世界规则", in: text)
        let theme = section("主题命题", in: text)
        let conflict = section("核心冲突", in: text)
        guard !character.isEmpty, !world.isEmpty, !theme.isEmpty, !conflict.isEmpty else {
            return nil
        }
        return StoryBibleProjection(
            character: character,
            world: world,
            theme: theme,
            conflict: conflict
        )
    }

    private func section(_ title: String, in text: String) -> String {
        let marker = "【\(title)】"
        guard let start = text.range(of: marker) else { return "" }
        let remainder = text[start.upperBound...]
        let end = remainder.range(of: "【")?.lowerBound ?? remainder.endIndex
        return remainder[..<end]
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func deterministicProjection(
        for project: StoryProject,
        decisions: [StoryDecision]
    ) -> StoryBibleProjection {
        let characterKeys = ["主人公", "人物", "弱点", "需要", "欲望", "关系", "对手", "自我"]
        let worldKeys = ["世界", "环境", "规则", "日常", "资源", "制度"]
        let themeKeys = ["主题", "道德", "高潮", "最低谷", "揭示", "新平衡", "结尾", "最后"]

        func lines(matching keys: [String]) -> [String] {
            decisions.compactMap { decision in
                guard let option = decision.selectedOption,
                      keys.contains(where: { decision.stageName.localizedCaseInsensitiveContains($0) })
                else { return nil }
                return "\(decision.stageName)：\(option.pitch)；代价是\(option.consequence)"
            }
        }

        var characterLines = lines(matching: characterKeys)
        if characterLines.isEmpty, let first = decisions.first?.selectedOption {
            characterLines = ["主角被锁定在这一行动逻辑中：\(first.pitch)"]
        }
        characterLines.append(contentsOf: project.narrativeProjections
            .filter { $0.scope == .character && $0.status != .stale }
            .prefix(4)
            .map { "正文实证：\($0.summary)" })

        var worldLines = lines(matching: worldKeys)
        let textures = decisions.compactMap(\.selectedOption)
            .map(\.realityTexture)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        worldLines.append(contentsOf: textures.suffix(2).map { "现实约束：\($0)" })
        if let actualWorld = DramaticProjectionEngine.projection(.world, key: "root", in: project) {
            worldLines.append("正文实证：\(actualWorld.summary)")
        }

        var themeLines = lines(matching: themeKeys)
        if themeLines.isEmpty,
           !project.dramaticPromise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            themeLines = ["故事持续检验的问题：\(project.dramaticPromise)"]
        }
        if let actualTheme = DramaticProjectionEngine.projection(.theme, key: "root", in: project) {
            themeLines.append("正文实证：\(actualTheme.summary)")
        }

        var conflictLines = decisions.suffix(4).compactMap { decision -> String? in
            guard let option = decision.selectedOption else { return nil }
            return "\(option.title)：\(option.consequence)；接下来\(option.futurePressure)"
        }
        if let actualConflict = DramaticProjectionEngine.projection(.conflict, key: "root", in: project) {
            conflictLines.append("正文实证：\(actualConflict.summary)")
        }

        return StoryBibleProjection(
            character: joined(characterLines),
            world: joined(worldLines),
            theme: joined(themeLines),
            conflict: joined(conflictLines)
        )
    }

    private func joined(_ lines: [String]) -> String {
        let unique = lines.reduce(into: [String]()) { result, line in
            let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, !result.contains(clean) else { return }
            result.append(clean)
        }
        return unique.isEmpty
            ? "尚待后续选择确认"
            : unique.suffix(5).joined(separator: "\n")
    }

    private func replacingManagedBlock(in source: String, with value: String) -> String {
        let startMarker = "【剧本圣经·动态同步】"
        let endMarker = "【/剧本圣经·动态同步】"
        var manual = source
        if let start = manual.range(of: startMarker),
           let end = manual.range(of: endMarker, range: start.upperBound..<manual.endIndex) {
            manual.removeSubrange(start.lowerBound..<end.upperBound)
        }
        manual = manual.trimmingCharacters(in: .whitespacesAndNewlines)
        let block = "\(startMarker)\n\(value)\n\(endMarker)"
        return manual.isEmpty ? block : "\(manual)\n\n\(block)"
    }
}

private extension String {
    var isPlaceholder: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines) == "尚待后续选择确认"
    }
}
