import Foundation
import FoundationModels

@Generable
nonisolated struct ScreenplayReviewFindingDraft {
    @Guide(description: "只能是：阻塞、警告、提示")
    var severity: String
    var title: String
    var detail: String
    var location: String
}

@Generable
nonisolated struct ScreenplayReviewResultDraft {
    var summary: String
    var findings: [ScreenplayReviewFindingDraft]
}

@MainActor
enum TypedScreenplayReviewExecutor {
    static func review(
        kind: ScreenplayReviewKind,
        project: StoryProject,
        configuration: AIConfiguration
    ) async throws -> ScreenplayReviewRound {
        let session = StoryLanguageRuntime.session(
            configuration: configuration,
            instructions: """
            你是可靠的剧本检查执行器，不是创意作者。作者拥有全部创意主权。
            你的任务是找出可以定位、可以验证的执行问题；不得提出新剧情、替代主题、
            新人物或“更有创意”的方向。没有证据就不要报问题。严重级别只能是：
            阻塞（造成因果或事实矛盾、无法交付）、警告（值得作者确认）、提示（非错误）。
            返回 Foundation Models 强类型结果。
            """
        )
        let sceneTree = project.sceneContracts
            .sorted { $0.sceneIndex < $1.sceneIndex }
            .map { scene in
                let microBeats = scene.microBeats
                    .sorted()
                    .compactMap(\.selectedOption)
                    .map { "\($0.title)：\($0.outcome)" }
                    .joined(separator: " → ")
                return "场 \(scene.sceneIndex) \(scene.heading)：目标=\(scene.characterGoal)；阻碍=\(scene.obstacle)；转折=\(scene.turn)；结果=\(scene.outcome)；小节拍=\(microBeats.isEmpty ? "尚未确认" : microBeats)"
            }
            .joined(separator: "\n")
        let response = try await session.respond(
            to: """
            【本轮】
            \(kind.rawValue)
            \(kind.purpose)

            【固定结构】
            \(project.lockedStructureSnapshot)
            \(project.structureText)

            【项目事实】
            \(project.storyBibleDigest)

            【场景与场内小节拍】
            \(sceneTree)

            【当前剧本】
            \(project.screenplayText)

            只检查“\(kind.rawValue)”。每个问题必须给出具体位置和文本证据，
            不要写泛泛建议，不要重写正文。没有问题时 findings 返回空数组。
            """,
            generating: ScreenplayReviewResultDraft.self,
            options: GenerationOptions(
                temperature: 0.1,
                maximumResponseTokens: 3_500
            )
        )

        let findings = response.content.findings.map { draft in
            ScreenplayReviewFinding(
                severity: severity(from: draft.severity),
                title: draft.title,
                detail: draft.detail,
                location: draft.location
            )
        }
        return ScreenplayReviewRound(
            kind: kind,
            screenplayFingerprint: ScreenplayReviewEngine.fingerprint(project.screenplayText),
            summary: response.content.summary,
            findings: findings
        )
    }

    private static func severity(from value: String) -> ScreenplayReviewSeverity {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.contains("阻塞") { return .blocker }
        if clean.contains("提示") { return .note }
        return .warning
    }
}
