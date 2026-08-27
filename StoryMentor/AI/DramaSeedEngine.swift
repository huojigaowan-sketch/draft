import Foundation

struct DramaSeedOutcome {
    let result: DramatizationResult
    let usage: TokenUsage
    let preparationNote: String
    let evidence: [TheoryEvidence]
}

@MainActor
struct DramaSeedEngine {
    let settings: AISettingsStore

    func dramatize(
        title: String,
        sourceType: StorySourceType,
        sourceText: String,
        authorIntent: String,
        progress: ((Double, String) -> Void)? = nil
    ) async throws -> DramaSeedOutcome {
        progress?(0.06, "阶段 1/5 · 检查素材")
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DramaSeedError.emptyMaterial
        }

        progress?(0.16, "阶段 2/5 · 在本机整理素材")
        let prepared: ApplePreparation
        if trimmed.contains("【现实资料包】") {
            prepared = ApplePreparation(
                text: String(trimmed.prefix(9_000)),
                note: "研究引擎已在本地清洗、去重并压缩 Reality Pack"
            )
        } else {
            prepared = await AppleTextService.prepareForAnalysis(
                trimmed,
                enabled: settings.useApplePreprocessing
            )
        }
        progress?(0.34, "阶段 2/5 · 本机整理完成")

        progress?(0.40, "阶段 3/5 · 匹配编剧理论")
        let route = TheoryRouting.route(for: .overview)
        let evidence: [TheoryEvidence]
        if settings.useKnowledgeBase {
            evidence = (try? await TheoryIndexStore.shared.search(
                query: "\(title)\n\(String(trimmed.prefix(2_400)))",
                route: route,
                maximumMatches: 6,
                maximumCharacters: 3_200
            )) ?? []
        } else {
            evidence = []
        }

        progress?(0.54, "阶段 3/5 · 匹配经典叙事功能")
        let storyCases = StoryDNAService.shared.matches(
            query: "\(title)\n\(trimmed)\n\(authorIntent)",
            genre: StoryGenre.unselected.rawValue,
            limit: 4
        )
        let context = DramatizationContext(
            sourceType: sourceType.rawValue,
            title: title,
            sourceMaterial: prepared.text,
            authorIntent: authorIntent,
            theoryContext: evidence.map(\.promptBlock).joined(separator: "\n\n"),
            storyDNAContext: storyCases.map(\.promptBlock).joined(separator: "\n\n")
        )
        progress?(0.68, "阶段 4/5 · DeepSeek 正在生成四条故事路线")
        let completion = try await DeepSeekClient(
            configuration: settings.configuration()
        ).dramatize(context, progress: progress)

        progress?(0.96, "阶段 5/5 · 整理分析结果")
        let tokenEstimate = evidence.reduce(0) { $0 + $1.estimatedTokens }
        return DramaSeedOutcome(
            result: completion.result,
            usage: completion.usage,
            preparationNote: "\(prepared.note) · 调用理论 \(evidence.count) 条，约 \(tokenEstimate) tokens",
            evidence: evidence
        )
    }
}

enum DramaSeedError: LocalizedError {
    case emptyMaterial

    var errorDescription: String? {
        "请粘贴一则新闻、历史资料、事件记录或任意灵感。"
    }
}
