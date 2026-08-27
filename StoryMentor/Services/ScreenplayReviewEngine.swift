import Foundation

enum ScreenplayReviewEngine {
    @MainActor
    static func deterministicFindings(
        kind: ScreenplayReviewKind,
        project: StoryProject
    ) -> [ScreenplayReviewFinding] {
        let text = project.screenplayText
        let report = ScreenplayReportBuilder.build(from: text)
        switch kind {
        case .structure:
            return structureFindings(project: project, report: report)
        case .continuity:
            return continuityFindings(project: project, report: report)
        case .dialogue:
            return dialogueFindings(report: report)
        case .format:
            return formatFindings(text: text, report: report)
        }
    }

    static func fingerprint(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    @MainActor
    static func isCurrent(
        _ round: ScreenplayReviewRound?,
        project: StoryProject
    ) -> Bool {
        round?.screenplayFingerprint == fingerprint(project.screenplayText)
    }

    @MainActor
    static func isReady(
        state: ScreenplayWorkspaceState?,
        project: StoryProject
    ) -> Bool {
        guard let state else { return false }
        return ScreenplayReviewKind.allCases.allSatisfy { kind in
            guard let round = state.latestReview(for: kind),
                  isCurrent(round, project: project) else {
                return false
            }
            return !round.findings.contains { $0.severity == .blocker }
        }
    }

    @MainActor
    static func nextRequiredKind(
        state: ScreenplayWorkspaceState?,
        project: StoryProject
    ) -> ScreenplayReviewKind {
        ScreenplayReviewKind.allCases.first { kind in
            guard let round = state?.latestReview(for: kind) else { return true }
            return !isCurrent(round, project: project)
                || round.findings.contains { $0.severity == .blocker }
        } ?? .format
    }

    @MainActor
    private static func structureFindings(
        project: StoryProject,
        report: ScreenplayReport
    ) -> [ScreenplayReviewFinding] {
        var findings: [ScreenplayReviewFinding] = []
        if report.scenes.isEmpty {
            findings.append(
                finding(.blocker, "没有可识别场景", "剧本必须至少包含一个标准场景标题。", "全本")
            )
        }
        let contracts = project.sceneContracts
        let standalone = ScreenplayProductionContextBuilder
            .isStandaloneScreenplay(project)
        if !standalone, !project.isStructureLocked {
            findings.append(
                finding(
                    .blocker,
                    "全本结构尚未锁定",
                    "场景已进入正文流程，但全本结构规则仍可变。请先确认三幕剧、英雄之旅、起承转合或当前选用的结构。",
                    "结构选择"
                )
            )
        }
        if !standalone, contracts.isEmpty {
            findings.append(
                finding(
                    .blocker,
                    "全本结构尚未映射为场景",
                    "请先把锁定结构的各阶段拆成场景契约，再编译完整正文。",
                    "场景工作台"
                )
            )
        }
        if !contracts.isEmpty, contracts.count != report.scenes.count {
            findings.append(
                finding(
                    .blocker,
                    "场景数量与已确认场景不一致",
                    "场景工作台有 \(contracts.count) 场，正文识别到 \(report.scenes.count) 场。请确认是否误删、合并或新增。",
                    "全本"
                )
            )
        }
        for issue in SceneCompilationEngine.issues(for: project)
        where issue.severity == .blocker {
            findings.append(
                finding(
                    .blocker,
                    issue.title,
                    issue.detail,
                    issue.sceneIndex.map { "场 \($0)" } ?? "场景工作台"
                )
            )
        }
        if !contracts.isEmpty {
            let missingAnchors = contracts.filter {
                ScreenplayProductionContextBuilder.anchor(
                    for: $0,
                    in: project
                ) == nil
            }
            if !missingAnchors.isEmpty {
                findings.append(
                    finding(
                        .blocker,
                        "\(missingAnchors.count) 场没有结构锚点",
                        "每场正文都必须能追溯到全本结构中的具体功能。",
                        "全本结构"
                    )
                )
            }
            let inferred = contracts.count {
                ScreenplayProductionContextBuilder.anchor(
                    for: $0,
                    in: project
                )?.isInferred == true
            }
            if inferred > 0 {
                findings.append(
                    finding(
                        .warning,
                        "\(inferred) 场使用顺序推定的结构锚点",
                        "这些旧场景未保存显式阶段编号，生成器已按全片位置稳定映射。交付前建议在场景工作台复核。",
                        "全本结构"
                    )
                )
            }
        }
        return findings
    }

    @MainActor
    private static func continuityFindings(
        project: StoryProject,
        report: ScreenplayReport
    ) -> [ScreenplayReviewFinding] {
        let declared = Set(
            project.characters
                .map(\.name)
                .map(normalizedName)
                .filter { !$0.isEmpty }
        )
        guard !declared.isEmpty else {
            return [
                finding(
                    .warning,
                    "人物圣经尚未登记人物",
                    "无法自动核对正文人物与项目人物表的一致性。",
                    "人物圣经"
                )
            ]
        }
        return report.characters.compactMap { character in
            let normalized = normalizedName(character.name)
            guard !declared.contains(normalized) else { return nil }
            return finding(
                .warning,
                "“\(character.name)”未在人物圣经中登记",
                "请确认这是有意新增的人物，而不是姓名写法不一致。",
                "\(character.sceneCount) 场出现"
            )
        }
    }

    private static func dialogueFindings(
        report: ScreenplayReport
    ) -> [ScreenplayReviewFinding] {
        report.scenes.compactMap { scene in
            guard scene.characters.isEmpty else { return nil }
            return finding(
                .note,
                "场 \(scene.sceneIndex + 1) 没有可识别对白人物",
                "如果这是纯动作场景可以保留；否则检查人物元素格式。",
                scene.heading
            )
        }
    }

    private static func formatFindings(
        text: String,
        report: ScreenplayReport
    ) -> [ScreenplayReviewFinding] {
        var findings: [ScreenplayReviewFinding] = []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            findings.append(finding(.blocker, "剧本为空", "没有可交付内容。", "全本"))
            return findings
        }
        if report.scenes.isEmpty {
            findings.append(
                finding(.blocker, "没有标准场景标题", "使用“内. 地点 - 日”或“外. 地点 - 夜”。", "全本")
            )
        }
        if text.contains("[[") || text.contains("]]") {
            findings.append(
                finding(
                    .blocker,
                    "仍有结构注释或占位符",
                    "交付前请处理所有 [[…]] 结构提示。",
                    "全本"
                )
            )
        }
        if text.contains("写下一个具体、可见的动作") {
            findings.append(
                finding(
                    .blocker,
                    "仍有正文占位句",
                    "剧本骨架尚未被完整写成可拍摄正文。",
                    "全本"
                )
            )
        }
        for scene in FountainParser.scenes(in: text)
        where SceneCompilationEngine.needsProfessionalDraft(scene) {
            findings.append(
                finding(
                    .blocker,
                    "场 \(scene.index + 1) 仍是结构骨架",
                    "该场仍含结构注释、占位句或执行骨架，请先用“编译完整第一稿”写成可拍正文。",
                    scene.heading
                )
            )
        }
        let unknownHeadings = report.scenes.filter { $0.locationKind == .unknown }
        for scene in unknownHeadings {
            findings.append(
                finding(
                    .warning,
                    "场景标题格式不明确",
                    "请确认内外景、地点与时间。",
                    scene.heading
                )
            )
        }
        return findings
    }

    private static func finding(
        _ severity: ScreenplayReviewSeverity,
        _ title: String,
        _ detail: String,
        _ location: String
    ) -> ScreenplayReviewFinding {
        ScreenplayReviewFinding(
            severity: severity,
            title: title,
            detail: detail,
            location: location
        )
    }

    private static func normalizedName(_ value: String) -> String {
        value
            .trimmingCharacters(in: CharacterSet(charactersIn: "@^ 　"))
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
