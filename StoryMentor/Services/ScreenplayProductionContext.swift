import Foundation

/// The exact structural obligation carried by one screenplay scene.
/// Explicit scene mappings win; older/NSIR-only projects receive a stable
/// proportional fallback so no scene reaches drafting without a whole-story
/// function.
struct ScreenplayStructureAnchor: Hashable {
    let templateID: String
    let templateName: String
    let stageIndex: Int
    let stageCount: Int
    let stageName: String
    let purpose: String
    let choiceFocus: String
    let selectedChoice: String
    let pacingSummary: String
    let isInferred: Bool

    var label: String {
        "\(templateName) · \(stageName)"
    }

    var progressLabel: String {
        "\(stageIndex + 1)/\(stageCount)"
    }

    var promptBlock: String {
        """
        结构体系：\(templateName)
        当前阶段：\(stageIndex + 1)/\(stageCount) · \(stageName)\(isInferred ? "（依全片顺序推定）" : "")
        全片功能：\(purpose)
        本阶段选择焦点：\(choiceFocus)
        作者已确认：\(selectedChoice.isEmpty ? "沿用已锁定的场景契约" : selectedChoice)
        节奏与情绪：\(pacingSummary)
        执行原则：本场只完成它在该阶段中的局部功能，不得抢先完成后续阶段；结构名称不得写入台词或注释。
        """
    }
}

enum ScreenplayProductionContextBuilder {
    /// A deliberately imported/plain screenplay may still use the editor and
    /// delivery tools without being forced through StoryMentor's structure
    /// pipeline. Any upstream structure, decision, NSIR, or scene-plan data
    /// means the project is structured and must finish that pipeline.
    @MainActor
    static func isStandaloneScreenplay(_ project: StoryProject) -> Bool {
        project.sceneContracts.isEmpty
            && project.decisions.isEmpty
            && project.nsirWorkspaceData.isEmpty
            && !project.hasSelectedStructureTemplate
            && project.structureText.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
            && project.scenesText.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
    }

    @MainActor
    static func anchor(
        for contract: SceneContract?,
        in project: StoryProject
    ) -> ScreenplayStructureAnchor? {
        guard let contract else { return nil }
        let template = project.structureTemplate
        guard !template.stages.isEmpty else { return nil }

        let resolved: (index: Int, inferred: Bool)
        if let explicit = contract.structureStageIndex,
           template.stages.indices.contains(explicit) {
            resolved = (explicit, false)
        } else {
            let ordered = project.sceneContracts.sorted { $0.sceneIndex < $1.sceneIndex }
            guard let position = ordered.firstIndex(where: { $0.id == contract.id }) else {
                return nil
            }
            let proportional = min(
                template.stages.count - 1,
                Int(
                    floor(
                        Double(position) * Double(template.stages.count)
                            / Double(max(ordered.count, 1))
                    )
                )
            )
            resolved = (proportional, true)
        }

        let stage = template.stages[resolved.index]
        let decision = project.decisions
            .filter { $0.stageIndex == resolved.index && $0.selectedOptionID != nil }
            .max { $0.resolvedAt ?? $0.createdAt < $1.resolvedAt ?? $1.createdAt }
        let selectedChoice = decision.flatMap { decision -> String? in
            let direct = decision.selectedAnswerText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !direct.isEmpty { return direct }
            guard let option = decision.selectedOption else { return nil }
            return [option.title, option.pitch]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "：")
        } ?? ""
        let pacing = project.pacingPlan(
            for: resolved.index,
            total: template.stages.count
        )
        let pacingSummary = "\(pacing.paceMode.rawValue) · \(pacing.targetEmotion.rawValue) \(Int(pacing.intensity))/100 · \(pacing.eventScale)"

        return ScreenplayStructureAnchor(
            templateID: template.id,
            templateName: template.name,
            stageIndex: resolved.index,
            stageCount: template.stages.count,
            stageName: stage.name,
            purpose: stage.purpose,
            choiceFocus: stage.choiceFocus,
            selectedChoice: String(selectedChoice.prefix(800)),
            pacingSummary: pacingSummary,
            isInferred: resolved.inferred
        )
    }

    @MainActor
    static func fullStructureTrack(for project: StoryProject) -> String {
        if isStandaloneScreenplay(project) {
            return "独立导入剧本：保留现有场景顺序、因果链和作者结构，不套用尚未由作者锁定的模板。"
        }
        let template = project.structureTemplate
        let contracts = project.sceneContracts.sorted { $0.sceneIndex < $1.sceneIndex }
        let stageLines = template.stages.indices.map { index in
            let stage = template.stages[index]
            let sceneNumbers = contracts.compactMap { contract -> String? in
                guard anchor(for: contract, in: project)?.stageIndex == index else {
                    return nil
                }
                return String(contract.sceneIndex)
            }
            let decision = project.decisions
                .filter { $0.stageIndex == index && $0.selectedOptionID != nil }
                .max { $0.resolvedAt ?? $0.createdAt < $1.resolvedAt ?? $1.createdAt }
            let choice = decision?.selectedAnswerText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let selected = (choice?.isEmpty == false ? choice : decision?.selectedOption?.title)
                ?? "待由已确认场景具体化"
            return "\(index + 1). \(stage.name)｜功能：\(stage.purpose)｜作者选择：\(String(selected.prefix(360)))｜场景：\(sceneNumbers.isEmpty ? "待映射" : sceneNumbers.joined(separator: "、"))"
        }
        .joined(separator: "\n")

        return """
        锁定结构：\(template.name)
        体验目标：\(template.experience)
        套用风险：\(template.caution)
        完整阶段轨道：
        \(stageLines)
        """
    }

    @MainActor
    static func retrievalQuery(
        project: StoryProject,
        scene: FountainSceneSnapshot,
        contract: SceneContract?,
        task: String
    ) -> String {
        let anchor = anchor(for: contract, in: project)
        return [
            project.title,
            project.genre.rawValue,
            project.structureTemplate.name,
            anchor?.stageName,
            anchor?.purpose,
            contract?.scopePurpose,
            contract?.characterGoal,
            contract?.obstacle,
            contract?.turn,
            scene.heading,
            task,
            TheoryRouting.route(for: .screenplay).focus
        ]
        .compactMap { $0 }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }
}
