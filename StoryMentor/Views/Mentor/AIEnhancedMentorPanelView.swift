import SwiftData
import SwiftUI

struct MentorPanelView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AISettingsStore.self) private var settings
    @Query private var knowledgeChunks: [KnowledgeChunk]
    @Query private var favoriteFragments: [StoryFragment]

    let project: StoryProject
    let section: WorkspaceSection

    @State private var isAnalyzing = false
    @State private var progressMessage = ""
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var indexStatistics: TheoryIndexStatistics?

    private var indexedDocumentCount: Int {
        indexStatistics?.documentCount ?? Set(knowledgeChunks.compactMap { $0.document?.id }).count
    }

    private var indexedChunkCount: Int {
        indexStatistics?.chunkCount ?? knowledgeChunks.count
    }

    private var activeCharacter: StoryCharacter? {
        project.characters.max { $0.updatedAt < $1.updatedAt }
    }

    private var analysisKind: AnalysisKind? {
        switch section {
        case .home, .seeds, .classics, .fragments: nil
        case .compiler, .overview, .ideas: .story
        case .templates: .structure
        case .journey: .story
        case .characters, .relationships: .character
        case .world: .world
        case .theme: .theme
        case .structure: .structure
        case .scenes: .scene
        case .screenplay, .versions, .delivery: .screenplay
        case .knowledge: nil
        }
    }

    private var latestReport: AnalysisReport? {
        guard let analysisKind else { return nil }
        return project.reports
            .filter {
                $0.kindRawValue == analysisKind.rawValue
                    && (analysisKind != .character || $0.subjectID == activeCharacter?.id)
            }
            .max { $0.createdAt < $1.createdAt }
    }

    private var sourceIsEmpty: Bool {
        StoryInputBuilder.sourceText(
            project: project,
            section: section,
            character: activeCharacter
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty
    }

    var body: some View {
        ZStack {
            StudioCanvas()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if section == .knowledge {
                        knowledgeSummary
                    } else {
                        analysisAction

                        if let latestReport {
                            reportView(latestReport)
                        } else {
                            firstRunCard
                        }
                    }

                    engineStatus
                }
                .padding(18)
            }
        }
        .navigationSplitViewColumnWidth(min: 310, ideal: 360, max: 430)
        .task {
            indexStatistics = try? await TheoryIndexStore.shared.statistics()
        }
        .alert("诊断失败", isPresented: $showingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(StudioTheme.accent)
                Text("导师台")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                Spacer()
                PhaseBadge(text: settings.hasAPIKey ? "ONLINE" : "SETUP")
            }
            Text(section == .knowledge ? "私人资料只在本机解析与检索。" : "诊断、比较、提问，然后给你下一道命题。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var analysisAction: some View {
        StudioCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ProgressRing(
                        value: project.completionFraction,
                        lineWidth: 7,
                        diameter: 62
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(latestReport == nil ? "准备发起诊断" : "最近诊断")
                            .font(.headline)
                        Text(latestReport?.createdAt.formatted(date: .abbreviated, time: .shortened) ?? "圆环只表示字段完成度，不评价故事质量")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if isAnalyzing {
                    HStack(spacing: 9) {
                        ProgressView()
                            .controlSize(.small)
                        Text(progressMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !settings.hasAPIKey {
                    SettingsLink {
                        Label("配置 DeepSeek API Key", systemImage: "key")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        runAnalysis()
                    } label: {
                        Label(latestReport == nil ? "开始 AI 诊断" : "重新诊断", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(sourceIsEmpty)

                    if sourceIsEmpty {
                        Text("当前模块没有文字，先写下一点素材。")
                            .font(.caption)
                            .foregroundStyle(StudioTheme.warm)
                    }
                }
            }
        }
    }

    private func reportView(_ report: AnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            StudioCard(padding: 16) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        EyebrowLabel(text: "核心判断")
                        Spacer()
                        Button {
                            toggleReportFavorite(report)
                        } label: {
                            Image(systemName: isReportFavorite(report) ? "heart.fill" : "heart")
                                .foregroundStyle(isReportFavorite(report) ? StudioTheme.warm : .secondary)
                        }
                        .buttonStyle(.borderless)
                        .help(isReportFavorite(report) ? "从灵感碎片移除" : "收藏这份诊断")
                    }
                    Text(report.summary)
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("L0–L5 分类诊断 · 不计算总故事分")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !report.strengths.isEmpty {
                reportList(title: "已经成立", color: StudioTheme.mint, items: report.strengths, state: .present)
            }
            if !report.gaps.isEmpty {
                reportList(title: "优先缺口", color: StudioTheme.warm, items: report.gaps, state: .missing)
            }
            if !report.recommendations.isEmpty {
                reportList(title: "改进方向", color: StudioTheme.sky, items: report.recommendations, state: .neutral)
            }

            if !report.antagonistSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                antagonistCard(report)
            }

            if !report.nextTaskPrompt.isEmpty {
                taskCard(report)
            }

            if !report.commercialPatterns.isEmpty || !report.theoryBasis.isEmpty || !report.evidenceText.isEmpty {
                evidenceCard(report)
            }

            if !report.questions.isEmpty {
                reportList(title: "值得继续追问", color: StudioTheme.accent, items: report.questions, state: .neutral)
            }

            Text("\(report.providerName) · 输入 \(report.promptTokens) tokens · 输出 \(report.completionTokens) tokens\n\(report.localPreparationNote)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reportList(
        title: String,
        color: Color,
        items: [String],
        state: LocalCheckRow.State
    ) -> some View {
        StudioCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                EyebrowLabel(text: title, color: color)
                ForEach(items, id: \.self) {
                    LocalCheckRow(text: $0, state: state)
                }
            }
        }
    }

    private func isReportFavorite(_ report: AnalysisReport) -> Bool {
        StoryFragmentCollector.contains(
            sourceID: "analysis-\(report.id.uuidString)",
            in: favoriteFragments
        )
    }

    private func toggleReportFavorite(_ report: AnalysisReport) {
        let content = """
        【核心判断】\(report.summary)
        【已经成立】
        \(report.strengths.joined(separator: "\n"))
        【优先缺口】
        \(report.gaps.joined(separator: "\n"))
        【改进方向】
        \(report.recommendations.joined(separator: "\n"))
        【反派功能】\(report.antagonistSuggestion)
        【下一道命题】\(report.nextTaskTitle)
        \(report.nextTaskPrompt)
        """
        do {
            try StoryFragmentCollector.toggle(
                sourceID: "analysis-\(report.id.uuidString)",
                title: "\(project.title) · \(section.rawValue)诊断",
                content: content,
                kind: .analysis,
                projectID: project.id,
                projectTitle: project.title,
                fragments: favoriteFragments,
                modelContext: modelContext
            )
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func antagonistCard(_ report: AnalysisReport) -> some View {
        StudioCard(padding: 16) {
            VStack(alignment: .leading, spacing: 11) {
                EyebrowLabel(text: "反派功能", color: .red)
                Text(report.antagonistSuggestion)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                if !project.characters.contains(where: { $0.role == .antagonist }) {
                    Button("创建为反派草稿", systemImage: "person.crop.circle.badge.plus") {
                        createAntagonist(from: report)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func taskCard(_ report: AnalysisReport) -> some View {
        StudioCard(padding: 16) {
            VStack(alignment: .leading, spacing: 9) {
                EyebrowLabel(text: "下一道命题", color: StudioTheme.sky)
                Text(report.nextTaskTitle)
                    .font(.system(.title3, design: .serif, weight: .semibold))
                Text(report.nextTaskPrompt)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func evidenceCard(_ report: AnalysisReport) -> some View {
        StudioCard(padding: 16) {
            DisclosureGroup("案例模式与本次理论依据") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(report.commercialPatterns, id: \.self) {
                        LocalCheckRow(text: $0, state: .neutral)
                    }
                    ForEach(report.theoryBasis, id: \.self) {
                        LocalCheckRow(text: $0, state: .present)
                    }
                    if !report.evidenceText.isEmpty {
                        Divider()
                        Text("本次检索引用")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(report.evidenceText.components(separatedBy: "\n").filter { !$0.isEmpty }, id: \.self) {
                            Label($0, systemImage: "book.closed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 10)
            }
            .font(.callout.weight(.semibold))
        }
    }

    private var firstRunCard: some View {
        StudioCard(padding: 16) {
            VStack(alignment: .leading, spacing: 11) {
                EyebrowLabel(text: "诊断会返回")
                LocalCheckRow(text: "已有优势与最优先缺口", state: .present)
                LocalCheckRow(text: "Story DNA 功能模式比较", state: .neutral)
                LocalCheckRow(text: "私人知识库理论依据", state: .neutral)
                LocalCheckRow(text: "反派功能与下一道命题", state: .neutral)
            }
        }
    }

    private var knowledgeSummary: some View {
        StudioCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label("本地检索已就绪", systemImage: "checkmark.shield.fill")
                    .font(.headline)
                    .foregroundStyle(StudioTheme.mint)
                Text("\(indexedDocumentCount) 份资料，\(indexedChunkCount) 个片段")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text("进入人物、世界、主题或结构模块发起诊断时，系统会自动选择最相关的片段。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var engineStatus: some View {
        StudioCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                EyebrowLabel(text: "引擎状态")
                LocalCheckRow(
                    text: settings.hasAPIKey ? "DeepSeek：\(settings.model)" : "DeepSeek：等待 API Key",
                    state: settings.hasAPIKey ? .present : .missing
                )
                LocalCheckRow(
                    text: "Apple：\(AppleTextService.availability.label)",
                    state: AppleTextService.availability.isAvailable ? .present : .neutral
                )
                LocalCheckRow(
                    text: "Story DNA：\(StoryDNAService.shared.cases.count) 个结构化案例",
                    state: .present
                )
                LocalCheckRow(
                    text: "本地理论索引：\(indexedChunkCount) 个片段",
                    state: indexedChunkCount == 0 ? .neutral : .present
                )
            }
        }
    }

    private func runAnalysis() {
        Task {
            isAnalyzing = true
            progressMessage = settings.useApplePreprocessing
                ? "本地整理材料，然后请求 DeepSeek…"
                : "正在请求 DeepSeek…"
            defer {
                isAnalyzing = false
                progressMessage = ""
            }

            do {
                guard let analysisKind else { return }
                let outcome = try await StoryAnalysisEngine(settings: settings).analyze(
                    project: project,
                    section: section,
                    character: activeCharacter
                )
                let result = outcome.result
                let report = AnalysisReport(
                    kind: analysisKind,
                    subjectID: analysisKind == .character ? activeCharacter?.id : nil,
                    score: 0,
                    summary: result.summary,
                    strengthsText: result.strengths.joined(separator: "\n"),
                    gapsText: result.gaps.joined(separator: "\n"),
                    recommendationText: result.recommendations.joined(separator: "\n"),
                    evidenceText: outcome.evidence.map(\.sourceLabel).joined(separator: "\n"),
                    providerName: settings.model,
                    commercialPatternsText: result.commercialPatterns.joined(separator: "\n"),
                    theoryBasisText: result.theoryBasis.joined(separator: "\n"),
                    antagonistSuggestion: result.antagonistSuggestion,
                    nextTaskTitle: result.nextTaskTitle,
                    nextTaskPrompt: result.nextTaskPrompt,
                    questionsText: result.questions.joined(separator: "\n"),
                    localPreparationNote: outcome.localPreparationNote,
                    promptTokens: outcome.usage.promptTokens,
                    completionTokens: outcome.usage.completionTokens
                )
                modelContext.insert(report)
                project.reports.append(report)

                if !result.nextTaskPrompt.isEmpty {
                    let task = CreativeTask(
                        title: result.nextTaskTitle,
                        prompt: result.nextTaskPrompt,
                        rationale: result.summary,
                        difficulty: settings.thinkingEnabled ? 2 : 1,
                        status: .active,
                        subjectID: activeCharacter?.id
                    )
                    modelContext.insert(task)
                    project.tasks.append(task)
                }
                project.touch()
                try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func createAntagonist(from report: AnalysisReport) {
        let antagonist = StoryCharacter(
            name: "反派草稿",
            role: .antagonist,
            seedText: report.antagonistSuggestion
        )
        modelContext.insert(antagonist)
        project.characters.append(antagonist)
        project.touch()
        do {
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
