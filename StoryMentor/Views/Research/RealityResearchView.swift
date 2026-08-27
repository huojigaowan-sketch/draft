import SwiftData
import SwiftUI

struct RealityResearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AISettingsStore.self) private var settings
    @Query(sort: \ResearchDossier.updatedAt, order: .reverse)
    private var dossiers: [ResearchDossier]
    @Query private var seeds: [StorySeed]

    let onOpenSeed: (StorySeed) -> Void

    @State private var selectedDossierID: UUID?
    @State private var title = ""
    @State private var query = ""
    @State private var sourceURL = ""
    @State private var sourceText = ""
    @State private var authorIntent = ""
    @State private var depth = ResearchDepth.deep
    @State private var firecrawlAPIKey = ""
    @State private var isResearching = false
    @State private var isGeneratingDirections = false
    @State private var statusMessage = ""
    @State private var errorMessage = ""
    @State private var showingError = false

    private var selectedDossier: ResearchDossier? {
        guard let selectedDossierID else { return nil }
        return dossiers.first { $0.id == selectedDossierID }
    }

    var body: some View {
        ZStack {
            StudioCanvas()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    researchComposer

                    if isResearching {
                        researchProgress
                    }

                    if let dossier = selectedDossier,
                       let result = dossier.result {
                        researchResults(result, dossier: dossier)
                    } else if !isResearching {
                        emptyState
                    }
                }
                .padding(26)
                .frame(maxWidth: 1_080)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationSplitViewColumnWidth(min: 680, ideal: 940)
        .task {
            firecrawlAPIKey = (try? ResearchCredentialStore.readFirecrawlKey()) ?? ""
            if selectedDossierID == nil, let dossier = dossiers.first {
                load(dossier)
            }
        }
        .alert("无法完成研究", isPresented: $showingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                EyebrowLabel(text: "Story Reality Engine", color: StudioTheme.sky)
                Text("深挖现实，再长成故事")
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                Text("同时寻找新闻、人物、制度、历史、学术与开放档案，让故事选择有真实世界的重量。")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button("开始新调查", systemImage: "plus") {
                    newDraft()
                }
                if !dossiers.isEmpty {
                    Divider()
                    ForEach(dossiers.prefix(15)) { dossier in
                        Button(dossier.title) {
                            load(dossier)
                        }
                    }
                }
            } label: {
                Label(
                    dossiers.isEmpty ? "调查记录" : "\(dossiers.count) 份调查",
                    systemImage: "clock.arrow.circlepath"
                )
            }
        }
    }

    private var researchComposer: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 17) {
                HStack(spacing: 12) {
                    TextField("调查标题，例如：被洪水重新露出的旧村庄", text: $title)
                        .textFieldStyle(.roundedBorder)
                    Picker("研究深度", selection: $depth) {
                        ForEach(ResearchDepth.allCases) { item in
                            Label(item.rawValue, systemImage: item.systemImage)
                                .tag(item)
                        }
                    }
                    .frame(width: 170)
                }

                TextField("要查清什么？输入事件、人物、地点或一个具体问题", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.weight(.medium))

                HStack(spacing: 10) {
                    TextField("原始新闻或资料网址（可选）", text: $sourceURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("我最想探索的方向（可选）", text: $authorIntent)
                        .textFieldStyle(.roundedBorder)
                }

                ZStack(alignment: .topLeading) {
                    if sourceText.isEmpty {
                        Text("可粘贴已有新闻、历史记录或零散线索。研究引擎会把它视为原始证据，而不是唯一答案。")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 9)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $sourceText)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 150)
                }
                .padding(10)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))

                HStack(alignment: .center, spacing: 12) {
                    Label(depth.subtitle, systemImage: depth.systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    DisclosureGroup("增强开放网页覆盖") {
                        VStack(alignment: .leading, spacing: 6) {
                            SecureField("Firecrawl API Key（可选）", text: $firecrawlAPIKey)
                                .textFieldStyle(.roundedBorder)
                            Text("不填写也能使用新闻、百科、学术与开放档案；填写后增加普通网页和动态网站。Key 只保存在钥匙串。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
                    }
                    .frame(width: 300)

                    Button {
                        runResearch()
                    } label: {
                        if isResearching {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 108)
                        } else {
                            Label("开始深挖", systemImage: "point.3.connected.trianglepath.dotted")
                                .frame(width: 108)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResearching)
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(StudioTheme.mint)
                }
            }
        }
    }

    private var researchProgress: some View {
        StudioCard(padding: 18) {
            HStack(spacing: 16) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 4) {
                    Text("调查员正在并行工作")
                        .font(.headline)
                    Text("跨语言新闻、知识实体、学术资料和历史档案正在清洗、去重并合并为证据图谱。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("不会把整页网页发送给 DeepSeek")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(StudioTheme.sky)
            }
        }
    }

    private func researchResults(
        _ result: RealityResearchResult,
        dossier: ResearchDossier
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            resultHero(result, dossier: dossier)
            coverageGrid(result.coverage)

            HStack(alignment: .top, spacing: 16) {
                evidenceCard(result)
                    .frame(maxWidth: .infinity)
                pressureCard(result)
                    .frame(maxWidth: .infinity)
            }

            if !result.timeline.isEmpty || !result.entities.isEmpty {
                HStack(alignment: .top, spacing: 16) {
                    timelineCard(result)
                        .frame(maxWidth: .infinity)
                    entityCard(result)
                        .frame(maxWidth: .infinity)
                }
            }

            sourceLibrary(result)
        }
    }

    private func resultHero(
        _ result: RealityResearchResult,
        dossier: ResearchDossier
    ) -> some View {
        StudioCard {
            HStack(alignment: .center, spacing: 22) {
                ProgressRing(
                    value: result.averageCoverage,
                    lineWidth: 7,
                    diameter: 76
                )

                VStack(alignment: .leading, spacing: 7) {
                    EyebrowLabel(text: "Reality Pack Ready", color: StudioTheme.mint)
                    Text(result.summary)
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        PhaseBadge(text: "\(result.sources.count) 个来源")
                        PhaseBadge(text: "\(result.providers.count) 类渠道")
                        Text(result.backendNote)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 9) {
                    Button {
                        generateStoryDirections(from: dossier)
                    } label: {
                        if isGeneratingDirections {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 170)
                        } else {
                            Label("生成四条故事路线", systemImage: "sparkles")
                                .frame(width: 170)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGeneratingDirections || !settings.hasAPIKey)

                    Button("只保存为创作素材", systemImage: "tray.and.arrow.down") {
                        do {
                            let seed = try prepareSeed(from: dossier)
                            onOpenSeed(seed)
                        } catch {
                            present(error)
                        }
                    }
                    .buttonStyle(.bordered)

                    if !settings.hasAPIKey {
                        Text("生成路线前请先保存 DeepSeek Key")
                            .font(.caption2)
                            .foregroundStyle(StudioTheme.warm)
                    }
                }
            }
        }
    }

    private func coverageGrid(
        _ coverage: [ResearchCoverageDimension]
    ) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: 10)],
            spacing: 10
        ) {
            ForEach(coverage) { item in
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text(item.label)
                            .font(.callout.weight(.semibold))
                        Spacer()
                        Text(item.score, format: .percent.precision(.fractionLength(0)))
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(coverageColor(item.score))
                    }
                    ProgressView(value: item.score)
                        .tint(coverageColor(item.score))
                    Text(item.note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(13)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.primary.opacity(0.05))
                }
            }
        }
    }

    private func evidenceCard(_ result: RealityResearchResult) -> some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 13) {
                Label("可追溯证据", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(StudioTheme.sky)
                ForEach(result.claims.prefix(8)) { claim in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(claim.dimension)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(StudioTheme.sky)
                            Spacer()
                            Text("\(claim.sourceIDs.count) 个依据")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(claim.text)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if claim.id != result.claims.prefix(8).last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private func pressureCard(_ result: RealityResearchResult) -> some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 13) {
                Label("现实中的戏剧压力", systemImage: "bolt.heart.fill")
                    .font(.headline)
                    .foregroundStyle(StudioTheme.warm)
                ForEach(result.dramaticPressures) { pressure in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            EyebrowLabel(text: pressure.angle, color: StudioTheme.warm)
                            Spacer()
                            Text(pressure.title)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(pressure.question)
                            .font(.callout.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(
                        StudioTheme.warm.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }

                if !result.openQuestions.isEmpty {
                    Divider()
                    ForEach(result.openQuestions, id: \.self) {
                        LocalCheckRow(text: $0, state: .neutral)
                    }
                }
            }
        }
    }

    private func timelineCard(_ result: RealityResearchResult) -> some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("时间线", systemImage: "timeline.selection")
                    .font(.headline)
                ForEach(result.timeline.prefix(8)) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Text(item.date)
                            .font(.caption2.monospaced())
                            .foregroundStyle(StudioTheme.mint)
                            .frame(width: 88, alignment: .leading)
                        Text(item.event)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func entityCard(_ result: RealityResearchResult) -> some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("人物、组织与地点", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                ForEach(result.entities.prefix(8)) { entity in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entity.name)
                            .font(.callout.weight(.semibold))
                        Text(entity.detail.isEmpty ? entity.kind : entity.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private func sourceLibrary(_ result: RealityResearchResult) -> some View {
        StudioCard {
            DisclosureGroup {
                VStack(spacing: 0) {
                    ForEach(Array(result.sources.prefix(24).enumerated()), id: \.element.id) { index, source in
                        HStack(alignment: .top, spacing: 12) {
                            Text("S\(index + 1)")
                                .font(.caption2.monospaced().weight(.bold))
                                .foregroundStyle(StudioTheme.sky)
                                .frame(width: 30, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                if let url = URL(string: source.url), !source.url.isEmpty {
                                    Link(source.title, destination: url)
                                        .font(.callout.weight(.medium))
                                } else {
                                    Text(source.title)
                                        .font(.callout.weight(.medium))
                                }
                                Text([source.publisher, source.publishedAt, source.provider]
                                    .filter { !$0.isEmpty }
                                    .joined(separator: " · "))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if !source.snippet.isEmpty {
                                    Text(source.snippet)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 9)
                        if index < min(result.sources.count, 24) - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.top, 10)
            } label: {
                HStack {
                    Label("打开完整来源账本", systemImage: "books.vertical.fill")
                        .font(.headline)
                    Spacer()
                    Text("\(result.sources.count) 条")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var emptyState: some View {
        StudioCard {
            HStack(spacing: 18) {
                Image(systemName: "globe.desk.fill")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(StudioTheme.sky)
                VStack(alignment: .leading, spacing: 5) {
                    Text("让资料成为故事的根")
                        .font(.system(.title3, design: .serif, weight: .semibold))
                    Text("先输入一个具体问题。研究完成后，你会得到资料覆盖度、证据、人物关系、历史回声和四个不同的戏剧入口。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private func runResearch() {
        Task {
            isResearching = true
            statusMessage = ""
            defer { isResearching = false }
            do {
                if firecrawlAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    try? ResearchCredentialStore.removeFirecrawlKey()
                } else {
                    try ResearchCredentialStore.saveFirecrawlKey(firecrawlAPIKey)
                }

                let dossier = try saveDossier()
                dossier.beginResearch()
                try ProjectPersistenceStore.savePendingChanges(in: modelContext)

                let result = try await RealityResearchEngine().research(
                    RealityResearchRequest(
                        title: dossier.title,
                        query: dossier.query,
                        sourceURL: dossier.sourceURL,
                        sourceText: dossier.sourceText,
                        authorIntent: dossier.authorIntent,
                        depth: dossier.depth.rawValue,
                        maxSources: dossier.depth.sourceLimit,
                        firecrawlAPIKey: firecrawlAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                )
                dossier.apply(result)
                try ProjectPersistenceStore.savePendingChanges(in: modelContext)
                statusMessage = "已汇集 \(result.sources.count) 个来源，Reality Pack 可以进入故事推演"
            } catch {
                selectedDossier?.fail(error)
                do {
                    try ProjectPersistenceStore.savePendingChanges(in: modelContext)
                } catch {
                    present(error)
                    return
                }
                present(error)
            }
        }
    }

    private func generateStoryDirections(from dossier: ResearchDossier) {
        Task {
            isGeneratingDirections = true
            statusMessage = ""
            defer { isGeneratingDirections = false }
            do {
                let seed = try prepareSeed(from: dossier)
                let outcome = try await DramaSeedEngine(settings: settings).dramatize(
                    title: seed.title,
                    sourceType: seed.sourceType,
                    sourceText: seed.sourceText,
                    authorIntent: seed.authorIntent
                )
                seed.apply(
                    outcome.result,
                    preparationNote: "\(outcome.preparationNote) · 来自 \(dossier.result?.sources.count ?? 0) 个现实来源",
                    usage: outcome.usage
                )
                try ProjectPersistenceStore.savePendingChanges(in: modelContext)
                statusMessage = "四条有现实依据的故事路线已经生成"
                onOpenSeed(seed)
            } catch {
                present(error)
            }
        }
    }

    private func prepareSeed(from dossier: ResearchDossier) throws -> StorySeed {
        guard let result = dossier.result else {
            throw RealityResearchError.noSources
        }
        let seed: StorySeed
        if let linkedSeedID = dossier.linkedSeedID,
           let existing = seeds.first(where: { $0.id == linkedSeedID }) {
            seed = existing
        } else {
            seed = StorySeed()
            modelContext.insert(seed)
            dossier.linkedSeedID = seed.id
        }
        seed.title = dossier.title
        seed.sourceType = dossier.depth == .archive ? .history : .news
        seed.sourceURL = dossier.sourceURL
        seed.sourceText = result.promptContext
        seed.authorIntent = dossier.authorIntent
        seed.factualSummary = result.summary
        seed.preparationNote = "\(result.backendNote) · \(result.sources.count) 个来源"
        seed.updatedAt = .now
        try ProjectPersistenceStore.saveEnsuringProject(
            seed: seed,
            in: modelContext
        )
        return seed
    }

    private func saveDossier() throws -> ResearchDossier {
        let dossier: ResearchDossier
        if let selectedDossier {
            dossier = selectedDossier
        } else {
            dossier = ResearchDossier()
            modelContext.insert(dossier)
            selectedDossierID = dossier.id
        }
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        dossier.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(cleanQuery.prefix(32))
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        dossier.query = cleanQuery
        dossier.sourceURL = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        dossier.sourceText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        dossier.authorIntent = authorIntent.trimmingCharacters(in: .whitespacesAndNewlines)
        dossier.depth = depth
        dossier.updatedAt = .now
        try ProjectPersistenceStore.savePendingChanges(in: modelContext)
        return dossier
    }

    private func load(_ dossier: ResearchDossier) {
        selectedDossierID = dossier.id
        title = dossier.title
        query = dossier.query
        sourceURL = dossier.sourceURL
        sourceText = dossier.sourceText
        authorIntent = dossier.authorIntent
        depth = dossier.depth
        statusMessage = ""
    }

    private func newDraft() {
        selectedDossierID = nil
        title = ""
        query = ""
        sourceURL = ""
        sourceText = ""
        authorIntent = ""
        depth = .deep
        statusMessage = ""
    }

    private func coverageColor(_ score: Double) -> Color {
        if score >= 0.72 { return StudioTheme.mint }
        if score >= 0.45 { return StudioTheme.warm }
        return StudioTheme.sky
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
    }
}
