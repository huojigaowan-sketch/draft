import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct DramaSeedLabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AISettingsStore.self) private var settings
    @Query(sort: \StorySeed.updatedAt, order: .reverse)
    private var seeds: [StorySeed]
    @Query private var favoriteFragments: [StoryFragment]

    let initialSeedID: UUID?
    let onCreateProject: (StorySeed, AdaptationDirection) -> Void

    @State private var selectedSeedID: UUID?
    @State private var title = ""
    @State private var sourceTypeRawValue = StorySourceType.news.rawValue
    @State private var sourceURL = ""
    @State private var sourceText = ""
    @State private var authorIntent = ""
    @State private var isAnalyzing = false
    @State private var isLoadingURL = false
    @State private var isImportingFile = false
    @State private var statusMessage = ""
    @State private var errorMessage = ""
    @State private var showingError = false

    private var selectedSeed: StorySeed? {
        guard let selectedSeedID else { return nil }
        return seeds.first { $0.id == selectedSeedID }
    }

    init(
        initialSeedID: UUID? = nil,
        onCreateProject: @escaping (StorySeed, AdaptationDirection) -> Void
    ) {
        self.initialSeedID = initialSeedID
        self.onCreateProject = onCreateProject
    }

    var body: some View {
        ZStack {
            StudioCanvas()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    sourceEditor

                    if isAnalyzing {
                        analysisProgress
                    }

                    if let selectedSeed,
                       !selectedSeed.factualSummary.isEmpty || !selectedSeed.directions.isEmpty {
                        results(for: selectedSeed)
                    } else {
                        emptyResult
                    }
                }
                .padding(26)
                .frame(maxWidth: 1_020)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationSplitViewColumnWidth(min: 620, ideal: 900)
        .task {
            if let initialSeedID,
               let requestedSeed = seeds.first(where: { $0.id == initialSeedID }) {
                load(requestedSeed)
            } else if selectedSeedID == nil, let seed = seeds.first {
                load(seed)
            }
        }
        .onChange(of: selectedSeedID) { _, newValue in
            guard let newValue,
                  let seed = seeds.first(where: { $0.id == newValue }) else { return }
            load(seed)
        }
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: false,
            onCompletion: importFile
        )
        .alert("无法完成", isPresented: $showingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                EyebrowLabel(text: "Drama Seed Lab", color: StudioTheme.mint)
                Text("把现实变成故事")
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                Text("粘贴新闻、历史、事件、资讯或生活观察。先发现戏剧性，再决定真正想写什么。")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button("新素材", systemImage: "plus") {
                    newDraft()
                }
                Divider()
                ForEach(seeds.prefix(12)) { seed in
                    Button(seed.title) {
                        selectedSeedID = seed.id
                    }
                }
            } label: {
                Label(seeds.isEmpty ? "素材记录" : "\(seeds.count) 份素材", systemImage: "clock.arrow.circlepath")
            }
        }
    }

    private var sourceEditor: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 12) {
                    TextField("素材标题，例如：水库退水后露出的旧村庄", text: $title)
                        .textFieldStyle(.roundedBorder)

                    Picker("类型", selection: $sourceTypeRawValue) {
                        ForEach(StorySourceType.allCases) { type in
                            Label(type.rawValue, systemImage: type.systemImage)
                                .tag(type.rawValue)
                        }
                    }
                    .frame(width: 150)
                }

                HStack(spacing: 10) {
                    TextField("新闻或资料网页地址（可选）", text: $sourceURL)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            guard !sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                  !isLoadingURL else { return }
                            importURL()
                        }
                    Button {
                        importURL()
                    } label: {
                        if isLoadingURL {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("读取网页", systemImage: "link")
                        }
                    }
                    .disabled(sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoadingURL)
                    Button("导入 Markdown", systemImage: "doc.badge.plus") {
                        isImportingFile = true
                    }
                }

                ZStack(alignment: .topLeading) {
                    if sourceText.isEmpty {
                        Text("把原始材料放在这里。它可以很平淡，也不需要先整理；戏剧性往往藏在人物没有说出口的欲望、代价和关系里。")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 9)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $sourceText)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 250)
                }
                .padding(10)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))

                HStack {
                    TextField("我特别想探索……（可选）", text: $authorIntent)
                        .textFieldStyle(.roundedBorder)
                    LocalPolishButton(text: $sourceText)
                    Button("保存素材") {
                        saveOnly()
                    }
                    Button {
                        runDramatization()
                    } label: {
                        Label("发现戏剧性", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAnalyzing)
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(StudioTheme.mint)
                }
            }
        }
    }

    private var analysisProgress: some View {
        StudioCard(padding: 16) {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 3) {
                    Text("正在寻找戏剧发动机")
                        .font(.callout.weight(.semibold))
                    Text("本地整理材料、检索相关理论，然后让 DeepSeek 提出四种不同改编道路。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func results(for seed: StorySeed) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                StudioCard {
                    VStack(alignment: .leading, spacing: 11) {
                        EyebrowLabel(text: "事实层", color: StudioTheme.sky)
                        Text("材料明确告诉我们的事")
                            .font(.headline)
                        Text(seed.factualSummary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity)

                StudioCard {
                    VStack(alignment: .leading, spacing: 11) {
                        EyebrowLabel(text: "戏剧核心", color: StudioTheme.warm)
                        Text("最值得追问的矛盾")
                            .font(.headline)
                        Text(seed.dramaticCore)
                            .font(.system(.title3, design: .serif, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            StudioCard {
                VStack(alignment: .leading, spacing: 14) {
                    Label("戏剧性雷达", systemImage: "scope")
                        .font(.headline)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 230), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(seed.dramaticElements) { element in
                            VStack(alignment: .leading, spacing: 6) {
                                EyebrowLabel(text: element.label)
                                Text(element.finding)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
                            .padding(13)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        EyebrowLabel(text: "四条生长路线", color: StudioTheme.mint)
                        Text("选择你真正想写的版本")
                            .font(.system(.title2, design: .serif, weight: .semibold))
                    }
                    Spacer()
                    Text("选择会创建正式项目，不会覆盖原始素材")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(seed.directions.enumerated()), id: \.element.id) { index, direction in
                    directionCard(index: index, direction: direction, seed: seed)
                }
            }

            if !seed.questions.isEmpty {
                StudioCard {
                    VStack(alignment: .leading, spacing: 11) {
                        Label("值得核实与决定", systemImage: "questionmark.bubble")
                            .font(.headline)
                        ForEach(seed.questions, id: \.self) {
                            LocalCheckRow(text: $0, state: .neutral)
                        }
                    }
                }
            }

            Text("\(seed.preparationNote) · 本次 DeepSeek 输入 \(seed.promptTokens) tokens，输出 \(seed.completionTokens) tokens")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func directionCard(
        index: Int,
        direction: AdaptationDirection,
        seed: StorySeed
    ) -> some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top) {
                    Text(String(format: "%02d", index + 1))
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                        .foregroundStyle(StudioTheme.mint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(direction.title)
                            .font(.system(.title2, design: .serif, weight: .semibold))
                        HStack(spacing: 8) {
                            PhaseBadge(text: direction.genre)
                            Text(direction.dramaticQuestion)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button {
                        toggleFavorite(direction, seed: seed)
                    } label: {
                        Image(systemName: isFavorite(direction, seed: seed) ? "heart.fill" : "heart")
                            .foregroundStyle(isFavorite(direction, seed: seed) ? StudioTheme.warm : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(isFavorite(direction, seed: seed) ? "从灵感碎片移除" : "收藏到灵感碎片")
                    Button("让它长成故事", systemImage: "leaf.arrow.triangle.circlepath") {
                        onCreateProject(seed, direction)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Text(direction.logline)
                    .font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)

                if direction.sourceCount > 0 || !direction.evidenceBasis.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(
                                "\(direction.sourceCount) 个现实来源",
                                systemImage: "checkmark.seal.fill"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(StudioTheme.sky)
                            Spacer()
                            if !direction.realityTexture.isEmpty {
                                Text(direction.realityTexture)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        ForEach(direction.evidenceBasis, id: \.self) { evidence in
                            Text("• \(evidence)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .background(
                        StudioTheme.sky.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }

                Divider()

                HStack(alignment: .top, spacing: 18) {
                    directionFact("主人公", direction.protagonist)
                    directionFact("对抗力量", direction.antagonistForce)
                    directionFact("失败代价", direction.stakes)
                }

                DisclosureGroup("事实与虚构边界") {
                    Text(direction.fictionalizationNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
            }
        }
    }

    private func directionFact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            EyebrowLabel(text: label)
            Text(value)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func directionSourceID(_ direction: AdaptationDirection, seed: StorySeed) -> String {
        "adaptation-\(seed.id.uuidString)-\(direction.id.uuidString)"
    }

    private func isFavorite(_ direction: AdaptationDirection, seed: StorySeed) -> Bool {
        StoryFragmentCollector.contains(
            sourceID: directionSourceID(direction, seed: seed),
            in: favoriteFragments
        )
    }

    private func toggleFavorite(_ direction: AdaptationDirection, seed: StorySeed) {
        let content = """
        【类型】\(direction.genre)
        【一句话故事】\(direction.logline)
        【主人公】\(direction.protagonist)
        【欲望】\(direction.desire)
        【对抗力量】\(direction.antagonistForce)
        【失败代价】\(direction.stakes)
        【戏剧问题】\(direction.dramaticQuestion)
        【现实质感】\(direction.realityTexture)
        【事实依据】\(direction.evidenceBasis.joined(separator: "；"))
        【事实与虚构边界】\(direction.fictionalizationNote)
        【下一步】\(direction.nextTaskTitle)：\(direction.nextTaskPrompt)
        """
        do {
            try StoryFragmentCollector.toggle(
                sourceID: directionSourceID(direction, seed: seed),
                title: direction.title,
                content: content,
                kind: .adaptationDirection,
                fragments: favoriteFragments,
                modelContext: modelContext
            )
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private var emptyResult: some View {
        StudioCard {
            HStack(spacing: 18) {
                Image(systemName: "leaf.circle")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(StudioTheme.mint)
                VStack(alignment: .leading, spacing: 5) {
                    Text("素材不需要先显得精彩")
                        .font(.headline)
                    Text("系统会先保留事实，再寻找欲望、阻碍、代价、秘密、关系压力与反转可能。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func newDraft() {
        selectedSeedID = nil
        title = ""
        sourceTypeRawValue = StorySourceType.news.rawValue
        sourceURL = ""
        sourceText = ""
        authorIntent = ""
        statusMessage = ""
    }

    private func load(_ seed: StorySeed) {
        selectedSeedID = seed.id
        title = seed.title
        sourceTypeRawValue = seed.sourceTypeRawValue
        sourceURL = seed.sourceURL
        sourceText = seed.sourceText
        authorIntent = seed.authorIntent
    }

    private func saveDraft() throws -> StorySeed {
        let seed: StorySeed
        if let selectedSeed {
            seed = selectedSeed
        } else {
            seed = StorySeed()
            modelContext.insert(seed)
            selectedSeedID = seed.id
        }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        seed.title = cleanTitle.isEmpty ? String(sourceText.prefix(28)) : cleanTitle
        seed.sourceTypeRawValue = sourceTypeRawValue
        seed.sourceURL = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        seed.sourceText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        seed.authorIntent = authorIntent.trimmingCharacters(in: .whitespacesAndNewlines)
        seed.updatedAt = .now
        try ProjectPersistenceStore.saveEnsuringProject(
            seed: seed,
            in: modelContext
        )
        return seed
    }

    private func saveOnly() {
        do {
            _ = try saveDraft()
            statusMessage = "素材已保存在本机"
        } catch {
            present(error)
        }
    }

    private func runDramatization() {
        Task {
            isAnalyzing = true
            statusMessage = ""
            defer { isAnalyzing = false }
            do {
                let seed = try saveDraft()
                let outcome = try await DramaSeedEngine(settings: settings).dramatize(
                    title: seed.title,
                    sourceType: seed.sourceType,
                    sourceText: seed.sourceText,
                    authorIntent: seed.authorIntent
                )
                seed.apply(
                    outcome.result,
                    preparationNote: outcome.preparationNote,
                    usage: outcome.usage
                )
                try ProjectPersistenceStore.savePendingChanges(in: modelContext)
                statusMessage = "已找到 \(seed.directions.count) 条故事生长路线"
            } catch {
                present(error)
            }
        }
    }

    private func importURL() {
        Task {
            isLoadingURL = true
            defer { isLoadingURL = false }
            do {
                let loaded = try await URLSourceLoader.load(sourceURL)
                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    title = loaded.title
                }
                sourceText = loaded.text
                sourceTypeRawValue = StorySourceType.news.rawValue
                statusMessage = "网页正文已读取，请检查后分析"
            } catch {
                present(error)
            }
        }
    }

    private func importFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            sourceText = try String(contentsOf: url, encoding: .utf8)
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                title = url.deletingPathExtension().lastPathComponent
            }
            sourceTypeRawValue = StorySourceType.document.rawValue
            statusMessage = "Markdown 已导入"
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
    }
}
