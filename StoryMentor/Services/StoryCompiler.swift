import Foundation
import SwiftData

@MainActor
enum StoryCompiler {
    struct Finding {
        let code: String
        let severity: StoryCompilerIssueSeverity
        let title: String
        let detail: String
        let location: String
    }

    static func refresh(project: StoryProject, in context: ModelContext) throws {
        try ProjectPersistenceStore.transaction(in: context) {
            updateFindings(project: project, in: context)
        }
    }

    static func updateFindings(project: StoryProject, in context: ModelContext) {
        let findings = findings(for: project)
        let activeCodes = Set(findings.map(\.code))

        for issue in project.compilerIssues {
            let shouldResolve = !activeCodes.contains(issue.code)
            if issue.isResolved != shouldResolve {
                issue.isResolved = shouldResolve
                issue.updatedAt = .now
            }
        }

        for finding in findings {
            if let existing = project.compilerIssues.first(where: { $0.code == finding.code }) {
                let hasChanged = existing.severity != finding.severity
                    || existing.title != finding.title
                    || existing.detail != finding.detail
                    || existing.location != finding.location
                    || existing.isResolved
                guard hasChanged else { continue }
                existing.severity = finding.severity
                existing.title = finding.title
                existing.detail = finding.detail
                existing.location = finding.location
                existing.isResolved = false
                existing.updatedAt = .now
            } else {
                let issue = StoryCompilerIssue(
                    code: finding.code,
                    severity: finding.severity,
                    title: finding.title,
                    detail: finding.detail,
                    location: finding.location
                )
                issue.project = project
                context.insert(issue)
            }
        }
    }

    static func findings(for project: StoryProject) -> [Finding] {
        var findings: [Finding] = []

        if !project.isStructureLocked {
            findings.append(
                Finding(
                    code: "structure.notLocked",
                    severity: .blocker,
                    title: "故事结构尚未锁定",
                    detail: "先选择并锁定一种结构。AI 后续执行必须服从这个骨架。",
                    location: "结构"
                )
            )
        }

        if project.characters.isEmpty {
            findings.append(
                Finding(
                    code: "character.none",
                    severity: .warning,
                    title: "还没有可追踪的人物",
                    detail: "至少需要一位承受事件后果的人物，才能检查目标、选择与代价。",
                    location: "人物"
                )
            )
        } else {
            let charactersMissingGoal = project.characters
                .filter { $0.externalGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map(\.name)
            if !charactersMissingGoal.isEmpty {
                findings.append(
                    Finding(
                        code: "character.goalMissing",
                        severity: .warning,
                        title: "人物缺少可行动目标",
                        detail: charactersMissingGoal.prefix(6).joined(separator: "、"),
                        location: "人物"
                    )
                )
            }

            let charactersMissingNeed = project.characters
                .filter { $0.internalNeed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map(\.name)
            if !charactersMissingNeed.isEmpty {
                findings.append(
                    Finding(
                        code: "character.needMissing",
                        severity: .note,
                        title: "人物内在需求尚未定义",
                        detail: charactersMissingNeed.prefix(6).joined(separator: "、"),
                        location: "人物"
                    )
                )
            }
        }

        if project.coreConflictText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            findings.append(
                Finding(
                    code: "conflict.missing",
                    severity: .warning,
                    title: "核心冲突尚未形成可检查陈述",
                    detail: "需要明确谁要什么、谁或什么阻止，以及失败会失去什么。",
                    location: "故事全景"
                )
            )
        }

        if project.isStructureLocked,
           let nextIndex = project.nextStructureStageIndex {
            let stage = project.structureTemplate.stages[nextIndex]
            findings.append(
                Finding(
                    code: "structure.nextStage",
                    severity: .note,
                    title: "下一个待完成大节拍：\(stage.name)",
                    detail: stage.purpose,
                    location: "结构"
                )
            )
        }

        let pendingIdeas = project.authorIdeas.filter {
            $0.status == .proposed || $0.status == .analyzing
        }
        if !pendingIdeas.isEmpty {
            findings.append(
                Finding(
                    code: "idea.pending",
                    severity: .note,
                    title: "\(pendingIdeas.count) 条作者创意等待确认",
                    detail: "这些想法已安全保存，但尚未进入 AI 的执行上下文。",
                    location: "作者创意"
                )
            )
        }

        if !project.scenesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && project.sceneContracts.isEmpty {
            findings.append(
                Finding(
                    code: "scene.contractsMissing",
                    severity: .warning,
                    title: "已有场景文本，但没有场景契约",
                    detail: "为每场补齐目标、阻碍、转折、结果与下一场压力，才能稳定检查因果链。",
                    location: "场景"
                )
            )
        }

        let screenplayExists = !project.screenplayText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
        let currentUpdates = project.dramaticUpdates.filter { $0.status != .stale }
        let staleUpdates = project.dramaticUpdates.filter { $0.status == .stale }

        if screenplayExists && currentUpdates.isEmpty {
            findings.append(
                Finding(
                    code: "semantic.notAnalyzed",
                    severity: .note,
                    title: "正文尚未建立情境更新状态链",
                    detail: "在正文工作台打开“情境透镜”逐场分析后，节奏、人物、关系、世界、主题、冲突和大节拍才会获得正文实证。",
                    location: "剧本正文"
                )
            )
        }

        if !staleUpdates.isEmpty {
            let staleScenes = Set(staleUpdates.compactMap(\.sceneRecordID)).count
            findings.append(
                Finding(
                    code: "semantic.stale",
                    severity: .warning,
                    title: "\(staleScenes) 个场景的语义证据已经过期",
                    detail: "正文改动后旧更新已自动退出节奏与向上归纳。重新分析这些场景，才能恢复可信投影。",
                    location: "情境透镜"
                )
            )
        }

        let ineffective = currentUpdates.filter { !$0.isEffective }
        if !ineffective.isEmpty {
            findings.append(
                Finding(
                    code: "semantic.noDelta",
                    severity: .warning,
                    title: "存在没有状态差异的候选更新",
                    detail: "\(ineffective.count) 项没有形成可说明的 before → after 差异，不能计入节奏。",
                    location: "情境更新"
                )
            )
        }

        let reduction = DramaticStateReducer.reduce(currentUpdates)
        for conflict in reduction.conflicts.prefix(12) {
            findings.append(
                Finding(
                    code: "semantic.conflict.\(conflict.id)",
                    severity: .warning,
                    title: "状态链前后矛盾",
                    detail: conflict.detail,
                    location: "情境状态 · \(conflict.stateKey)"
                )
            )
        }

        let confirmedWithoutStateContract = project.sceneContracts.filter {
            $0.selectedSceneOptionID != nil && $0.stateContract.requiredChanges.isEmpty
        }
        if !confirmedWithoutStateContract.isEmpty {
            findings.append(
                Finding(
                    code: "semantic.contractMissing",
                    severity: .note,
                    title: "旧场景尚未结构化为状态契约",
                    detail: confirmedWithoutStateContract.prefix(8)
                        .map { "场 \($0.sceneIndex)" }
                        .joined(separator: "、"),
                    location: "场景"
                )
            )
        }

        let gaps = project.narrativeProjections.filter {
            $0.scope == .scene
                && $0.status != .stale
                && !$0.realizationGap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        for gap in gaps.prefix(12) {
            findings.append(
                Finding(
                    code: "semantic.gap.\(gap.scopeKey)",
                    severity: .warning,
                    title: "场景计划与正文实现不一致",
                    detail: gap.realizationGap,
                    location: gap.title
                )
            )
        }

        return findings
    }

    static func snapshot(
        project: StoryProject,
        title: String,
        reason: String,
        in context: ModelContext
    ) throws {
        try ProjectPersistenceStore.transaction(in: context) {
            insertSnapshot(
                project: project,
                title: title,
                reason: reason,
                in: context
            )
        }
    }

    static func insertSnapshot(
        project: StoryProject,
        title: String,
        reason: String,
        in context: ModelContext
    ) {
        let digest = """
        片名：\(project.title)
        一句话：\(project.logline)
        主题：\(project.themeText)
        核心冲突：\(project.coreConflictText)
        结构：\(project.structureTemplateName)
        结构进度：\(project.resolvedDecisionCount)/\(project.isStructureLocked ? project.structureTemplate.stages.count : 0)
        人物数：\(project.characters.count)
        作者创意数：\(project.authorIdeas.count)
        """
        let snapshot = StoryRevisionSnapshot(
            title: title,
            reason: reason,
            projectDigest: digest,
            screenplayText: project.screenplayText
        )
        snapshot.project = project
        context.insert(snapshot)
    }
}
