import Foundation
import SwiftData

struct SceneCompilationIssue: Identifiable, Hashable {
    enum Severity: Int, Hashable {
        case blocker
        case warning
        case note

        var title: String {
            switch self {
            case .blocker: "阻塞"
            case .warning: "待确认"
            case .note: "提示"
            }
        }

        var systemImage: String {
            switch self {
            case .blocker: "xmark.octagon.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .note: "info.circle.fill"
            }
        }
    }

    let id: String
    let severity: Severity
    let sceneIndex: Int?
    let title: String
    let detail: String
}

enum SceneCompilationEngine {

    /// True when the scene is still an upstream execution skeleton rather
    /// than clean, camera-ready screenplay prose. This deliberately avoids a
    /// length heuristic so an authored short scene is never mistaken for a
    /// placeholder.
    static func needsProfessionalDraft(_ scene: FountainSceneSnapshot) -> Bool {
        if scene.isSkeleton { return true }
        let text = scene.text
        if text.contains("[[") || text.contains("]]" ) { return true }
        let generatedSkeletonMarkers = [
            "场中人物开始推进：",
            "局面继续推进：",
            "阻力显现：",
            "行动迫使局面转向：",
            "场景结束时：",
            "新的压力随之形成：",
            "写下一个具体、可见的动作"
        ]
        return generatedSkeletonMarkers.contains { text.contains($0) }
    }

    @MainActor
    static func screenplaySkeleton(for project: StoryProject) -> String {
        let contracts = project.sceneContracts.sorted { $0.sceneIndex < $1.sceneIndex }
        return contracts.map { screenplayDraft(for: $0, project: project) }
        .joined(separator: "\n\n")
    }

    /// Produces the readable, editable realization of one upstream scene.
    /// Confirmed micro-beats contribute their authored screenplay text. Until
    /// every micro-beat is confirmed, the already-decided scene contract is
    /// still rendered as action instead of leaving the Final Draft surface
    /// blank or asking the author to start from a placeholder.
    @MainActor
    static func screenplayDraft(
        for contract: SceneContract,
        project: StoryProject
    ) -> String {
        let headingSource = firstNonempty(
            contract.heading,
            contract.scopeTitle,
            "未定地点"
        )
        let heading = fountainHeading(headingSource, index: contract.sceneIndex)
        let notes = [
            "[[来源：\(stageName(for: contract, project: project)) · 场 \(contract.sceneIndex)]]",
            note("场景职责", firstNonempty(contract.scopePurpose, contract.characterGoal)),
            note("已选方案", contract.selectedSceneOption?.title ?? ""),
            note("执行方式", contract.selectedSceneOption?.approach ?? ""),
            note("进入状态", contract.scopeEntryState),
            note("视点", contract.pointOfView),
            note("目标", contract.characterGoal),
            note("阻碍", contract.obstacle),
            note("转折", contract.turn),
            note("结果", firstNonempty(contract.outcome, contract.scopeExitState)),
            note("下一场压力", contract.nextPressure)
        ]
        .compactMap { $0 }

        let orderedBeats = contract.microBeats.sorted()
        var body = orderedBeats.compactMap(\.selectedOption)
            .map(\.screenplayText)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let missingBeatActions = orderedBeats
            .filter { $0.selectedOption == nil }
            .map(\.purpose)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { sentence("局面继续推进：\($0)") }

        if body.isEmpty {
            body = sceneActionDraft(for: contract)
        } else {
            body.append(contentsOf: missingBeatActions)
        }

        let sections = [notes.joined(separator: "\n"), body.joined(separator: "\n\n")]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        return "\(heading)\n\n\(sections)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    static func issues(for project: StoryProject) -> [SceneCompilationIssue] {
        let contracts = project.sceneContracts.sorted { $0.sceneIndex < $1.sceneIndex }
        guard !contracts.isEmpty else {
            return [
                SceneCompilationIssue(
                    id: "no-scenes",
                    severity: .blocker,
                    sceneIndex: nil,
                    title: "还没有可执行场景",
                    detail: "先在第 2 层确认大节拍，再在第 3 层逐场确认四选一方案。"
                )
            ]
        }

        var result: [SceneCompilationIssue] = []
        for contract in contracts {
            let missing = missingFields(contract)
            if !missing.isEmpty {
                result.append(
                    SceneCompilationIssue(
                        id: "missing-\(contract.id)",
                        severity: .blocker,
                        sceneIndex: contract.sceneIndex,
                        title: "场 \(contract.sceneIndex) 缺少 \(missing.joined(separator: "、"))",
                        detail: "正文执行前必须明确这一场如何改变局面。"
                    )
                )
            }

            if contract.heading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(
                    SceneCompilationIssue(
                        id: "heading-\(contract.id)",
                        severity: .warning,
                        sceneIndex: contract.sceneIndex,
                        title: "场 \(contract.sceneIndex) 没有场景标题",
                        detail: "至少写明地点与时间，方便拍摄和连续性检查。"
                    )
                )
            }
        }

        for index in contracts.indices.dropFirst() {
            let previous = contracts[index - 1]
            let current = contracts[index]
            if previous.nextPressure.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || current.characterGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }
            if normalized(previous.nextPressure) == normalized(current.characterGoal) {
                continue
            }
            result.append(
                SceneCompilationIssue(
                    id: "chain-\(previous.id)-\(current.id)",
                    severity: .note,
                    sceneIndex: current.sceneIndex,
                    title: "确认场 \(previous.sceneIndex) → 场 \(current.sceneIndex) 的因果",
                    detail: "上一场压力与下一场目标不是同一句话；请确认这是有意的推进，而不是断裂。"
                )
            )
        }
        return result
    }

    @MainActor
    static func isComplete(_ contract: SceneContract) -> Bool {
        missingFields(contract).isEmpty
    }

    @MainActor
    static func completion(for project: StoryProject) -> Double {
        guard !project.sceneContracts.isEmpty else { return 0 }
        let complete = project.sceneContracts.count(where: isComplete)
        return Double(complete) / Double(project.sceneContracts.count)
    }

    @MainActor
    private static func missingFields(_ contract: SceneContract) -> [String] {
        [
            ("目标", contract.characterGoal),
            ("阻碍", contract.obstacle),
            ("转折", contract.turn),
            ("结果", contract.outcome),
            ("下一场压力", contract.nextPressure)
        ]
        .compactMap { name, value in
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? name : nil
        }
    }

    @MainActor
    private static func stageName(
        for contract: SceneContract,
        project: StoryProject
    ) -> String {
        guard let index = contract.structureStageIndex,
              project.structureTemplate.stages.indices.contains(index) else {
            return "未关联"
        }
        return project.structureTemplate.stages[index].name
    }

    private static func normalizedHeading(_ value: String, index: Int) -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "内. 未定地点 - 日" : clean
    }

    private static func fountainHeading(_ value: String, index: Int) -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "内. 未定地点 - 日" }
        let upper = clean.uppercased()
        if upper.hasPrefix("INT.")
            || upper.hasPrefix("EXT.")
            || clean.hasPrefix("内.")
            || clean.hasPrefix("外.")
            || clean.hasPrefix("内景")
            || clean.hasPrefix("外景") {
            return clean
        }
        return "内. \(clean) - 日"
    }

    private static func value(_ string: String) -> String {
        let clean = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "待作者确认" : clean
    }

    private static func sceneActionDraft(
        for contract: SceneContract
    ) -> [String] {
        let actor = firstNonempty(contract.pointOfView, "场中人物")
        let goal = firstNonempty(
            contract.characterGoal,
            contract.scopePurpose,
            contract.scopeTitle,
            "既定目标"
        )
        let obstacle = firstNonempty(
            contract.obstacle,
            contract.scopeEntryState
        )
        let turn = firstNonempty(contract.turn, contract.scopeExitState)
        let outcome = firstNonempty(contract.outcome, contract.scopeExitState)
        let approach = contract.selectedSceneOption?.approach
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return [
            approach.isEmpty ? nil : sentence(approach),
            sentence("\(actor)开始推进：\(goal)"),
            obstacle.isEmpty ? nil : sentence("阻力显现：\(obstacle)"),
            turn.isEmpty ? nil : sentence("行动迫使局面转向：\(turn)"),
            outcome.isEmpty ? nil : sentence("场景结束时：\(outcome)"),
            contract.nextPressure.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : sentence("新的压力随之形成：\(contract.nextPressure)")
        ]
        .compactMap { $0 }
    }

    private static func note(_ label: String, _ value: String) -> String? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : "[[\(label)：\(clean)]]"
    }

    private static func firstNonempty(_ values: String...) -> String {
        values.first {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func sentence(_ value: String) -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = clean.last else { return clean }
        return "。！？!?".contains(last) ? clean : clean + "。"
    }

    private static func normalized(_ string: String) -> String {
        string
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }

    @MainActor
    private static func fillIfEmpty(_ target: inout String, with value: String) {
        if target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            target = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
