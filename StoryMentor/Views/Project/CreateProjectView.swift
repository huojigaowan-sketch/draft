import SwiftUI
import UniformTypeIdentifiers

struct NewProjectDraft {
    var title: String
    var genre: StoryGenre
    var logline: String
    var sourceTitle: String
    var sourceMethod: String
    var sourceType: StorySourceType
    var sourceURL: String
    var sourceText: String
    var authorIntent: String
    var dramatization: DramatizationResult?
    var selectedDirection: AdaptationDirection?
    var preparationNote: String
    var usage: TokenUsage
}

private enum ProjectSourceMethod: String, CaseIterable, Identifiable {
    case newsURL
    case novelMarkdown
    case researchMarkdown
    case plainText
    case referenceScreenplay
    case quickIdea

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newsURL: "网页新闻"
        case .novelMarkdown: "小说 Markdown"
        case .researchMarkdown: "资料 Markdown"
        case .plainText: "TXT 资料"
        case .referenceScreenplay: "爆款剧本 Markdown"
        case .quickIdea: "临时想法"
        }
    }

    var subtitle: String {
        switch self {
        case .newsURL: "粘贴新闻或事件网页地址"
        case .novelMarkdown: "从小说原文寻找可影视化主线"
        case .researchMarkdown: "把采访、田野与背景资料变成戏"
        case .plainText: "导入任意 UTF-8 纯文本"
        case .referenceScreenplay: "拆解功能，不复制具体表达"
        case .quickIdea: "从一句刚出现的念头开始"
        }
    }

    var icon: String {
        switch self {
        case .newsURL: "link.badge.plus"
        case .novelMarkdown: "text.book.closed.fill"
        case .researchMarkdown: "doc.text.magnifyingglass"
        case .plainText: "doc.plaintext.fill"
        case .referenceScreenplay: "film.stack.fill"
        case .quickIdea: "lightbulb.max.fill"
        }
    }

    var sourceType: StorySourceType {
        switch self {
        case .newsURL: .newsURL
        case .novelMarkdown: .novelMarkdown
        case .researchMarkdown: .researchMarkdown
        case .plainText: .plainText
        case .referenceScreenplay: .referenceScreenplay
        case .quickIdea: .freeIdea
        }
    }

    var requiresFile: Bool {
        switch self {
        case .novelMarkdown, .researchMarkdown, .plainText, .referenceScreenplay: true
        case .newsURL, .quickIdea: false
        }
    }

    var editorPlaceholder: String {
        switch self {
        case .newsURL:
            "读取网页后，正文会出现在这里。你可以先删除广告、导航或与故事无关的部分。"
        case .novelMarkdown:
            "导入小说 Markdown 后，可以只保留本次想改编的章节。"
        case .researchMarkdown:
            "导入采访、人物档案、历史背景或调查资料。"
        case .plainText:
            "导入 TXT，或直接把纯文字粘贴在这里。"
        case .referenceScreenplay:
            "导入参考剧本。系统只提取结构功能、冲突机制和观看体验，不复制情节与对白。"
        case .quickIdea:
            "例如：一个替陌生人保管记忆的人，发现最后一份记忆属于未来的自己。"
        }
    }
}

private enum CreateProjectStep: Int, CaseIterable, Identifiable {
    case source
    case material
    case direction

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .source: "选择起点"
        case .material: "整理素材"
        case .direction: "锁定故事"
        }
    }
}

struct CreateProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AISettingsStore.self) private var settings

    @State private var step = CreateProjectStep.source
    @State private var method: ProjectSourceMethod?
    @State private var sourceTitle = ""
    @State private var sourceURL = ""
    @State private var sourceText = ""
    @State private var authorIntent = ""
    @State private var result: DramatizationResult?
    @State private var preparationNote = ""
    @State private var usage = TokenUsage.zero
    @State private var isImportingFile = false
    @State private var isWorking = false
    @State private var progressMessage = ""
    @State private var analysisProgress = 0.0
    @State private var analysisElapsedSeconds = 0
    @State private var errorMessage = ""
    @State private var showingError = false

    let onCreate: (NewProjectDraft) -> Void

    private let methodColumns = [
        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 14)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ZStack {
                StudioCanvas()
                Group {
                    switch step {
                    case .source:
                        sourceStep
                    case .material:
                        materialStep
                    case .direction:
                        directionStep
                    }
                }
            }

            Divider()
            footer
        }
        .frame(width: 940, height: 760)
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: false,
            onCompletion: importFile
        )
        .alert("新建项目没有完成", isPresented: $showingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var header: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                EyebrowLabel(text: "NEW SCREENPLAY PROJECT", color: StudioTheme.mint)
                Text("从素材到一部完整剧本")
                    .font(.system(.title2, design: .serif, weight: .semibold))
            }

            Spacer()

            HStack(spacing: 8) {
                ForEach(CreateProjectStep.allCases) { item in
                    HStack(spacing: 7) {
                        ZStack {
                            Circle()
                                .fill(
                                    item.rawValue <= step.rawValue
                                        ? StudioTheme.mint
                                        : Color.primary.opacity(0.08)
                                )
                            if item.rawValue < step.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                            } else {
                                Text("\(item.rawValue + 1)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(
                                        item.rawValue <= step.rawValue ? .white : .secondary
                                    )
                            }
                        }
                        .frame(width: 24, height: 24)

                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                item.rawValue <= step.rawValue ? .primary : .tertiary
                            )
                    }

                    if item != CreateProjectStep.allCases.last {
                        Rectangle()
                            .fill(Color.primary.opacity(0.10))
                            .frame(width: 28, height: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 17)
        .background(.ultraThinMaterial)
    }

    private var sourceStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("这个项目从哪里开始？")
                        .font(.system(size: 32, weight: .semibold, design: .serif))
                    Text("六种入口最终都会汇入同一条流程：本机整理 → DeepSeek 戏剧化 → 选择固定结构 → 逐阶段四选一。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: methodColumns, spacing: 14) {
                    ForEach(ProjectSourceMethod.allCases) { item in
                        methodCard(item)
                    }
                }

                StudioCard(padding: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .font(.title2)
                            .foregroundStyle(StudioTheme.mint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("每个项目独立自动保存")
                                .font(.callout.weight(.semibold))
                            Text("原始资料、选择历史、人物、世界、主题、场景和剧本都跟随当前项目保存在这台 Mac。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
    }

    private func methodCard(_ item: ProjectSourceMethod) -> some View {
        let isSelected = method == item
        return Button {
            method = item
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: item.icon)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : StudioTheme.mint)
                        .frame(width: 43, height: 43)
                        .background(
                            isSelected ? StudioTheme.mint : StudioTheme.mint.opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(
                            isSelected ? StudioTheme.mint : Color.secondary.opacity(0.45)
                        )
                }
                Text(item.title)
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(17)
            .frame(maxWidth: .infinity, minHeight: 155, alignment: .topLeading)
            .background(
                isSelected ? StudioTheme.mint.opacity(0.10) : Color.primary.opacity(0.025),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        isSelected ? StudioTheme.mint.opacity(0.65) : Color.primary.opacity(0.06),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private var materialStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        EyebrowLabel(text: method?.title ?? "素材")
                        Text("把原始材料交给故事引擎")
                            .font(.system(size: 30, weight: .semibold, design: .serif))
                        Text("先保留事实与作者意图，再寻找欲望、阻碍、代价、关系压力和可持续的核心冲突。")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if AppleTextService.availability.isAvailable {
                        Label("Apple 智能本地整理", systemImage: "apple.intelligence")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(StudioTheme.mint)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(StudioTheme.mint.opacity(0.10), in: Capsule())
                    }
                }

                StudioCard {
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("素材名称（可选）", text: $sourceTitle)
                            .textFieldStyle(.roundedBorder)

                        if method == .newsURL {
                            HStack(spacing: 10) {
                                TextField("https://…", text: $sourceURL)
                                    .textFieldStyle(.roundedBorder)
                                Button("读取网页", systemImage: "arrow.down.doc") {
                                    loadURLOnly()
                                }
                                .disabled(
                                    sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || isWorking
                                )
                            }
                        } else if method?.requiresFile == true {
                            HStack {
                                Button("选择 \(method?.title ?? "文件")", systemImage: "doc.badge.plus") {
                                    isImportingFile = true
                                }
                                .buttonStyle(.borderedProminent)
                                if !sourceTitle.isEmpty {
                                    Text(sourceTitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text("支持 UTF-8 Markdown / TXT")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        ZStack(alignment: .topLeading) {
                            if sourceText.isEmpty {
                                Text(method?.editorPlaceholder ?? "在这里粘贴文字。")
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 10)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $sourceText)
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 260)
                        }
                        .padding(10)
                        .background(
                            Color.primary.opacity(0.035),
                            in: RoundedRectangle(cornerRadius: 13)
                        )

                        TextField("我特别想探索……（可选）", text: $authorIntent)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                if isWorking {
                    StudioCard(padding: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Text(progressMessage)
                                    .font(.callout.weight(.semibold))
                                Spacer()
                                Text("\(Int(analysisProgress * 100))%")
                                    .font(.system(.callout, design: .monospaced, weight: .bold))
                                    .foregroundStyle(StudioTheme.mint)
                            }
                            ProgressView(value: analysisProgress, total: 1)
                                .progressViewStyle(.linear)
                                .tint(StudioTheme.mint)
                            Text(progressFootnote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !settings.hasAPIKey {
                    StudioCard(padding: 16) {
                        HStack {
                            Label("需要 DeepSeek API Key 才能进行戏剧化分析", systemImage: "key.fill")
                                .font(.callout)
                            Spacer()
                            SettingsLink {
                                Text("打开 AI 设置")
                            }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
    }

    private var directionStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        EyebrowLabel(text: "DRAMATIZATION COMPLETE", color: StudioTheme.mint)
                        Text("选择最想继续看的故事")
                            .font(.system(size: 31, weight: .semibold, design: .serif))
                        Text("选中后会创建独立项目，并直接进入全球经典结构库。结构锁定后，后续每一阶段仍会生成四个具体选项。")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("本次 \(usage.totalTokens) tokens", systemImage: "gauge.with.dots.needle.33percent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let result {
                    HStack(alignment: .top, spacing: 14) {
                        analysisSummary(
                            title: "事实层",
                            text: result.factualSummary,
                            tint: StudioTheme.sky
                        )
                        analysisSummary(
                            title: "戏剧核心",
                            text: result.dramaticCore,
                            tint: StudioTheme.warm
                        )
                    }

                    ForEach(Array(result.directions.enumerated()), id: \.element.id) { index, direction in
                        directionCard(direction, number: index + 1)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
    }

    private func analysisSummary(title: String, text: String, tint: Color) -> some View {
        StudioCard(padding: 17) {
            VStack(alignment: .leading, spacing: 8) {
                EyebrowLabel(text: title, color: tint)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func directionCard(_ direction: AdaptationDirection, number: Int) -> some View {
        StudioCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    Text(String(format: "%02d", number))
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                        .foregroundStyle(StudioTheme.mint)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(direction.title)
                                .font(.system(.title2, design: .serif, weight: .semibold))
                            PhaseBadge(text: direction.genre)
                        }
                        Text(direction.logline)
                            .font(.body.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button("以此建立项目", systemImage: "arrow.right.circle.fill") {
                        createProject(with: direction)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Divider()

                HStack(alignment: .top, spacing: 18) {
                    directionFact("主人公", direction.protagonist)
                    directionFact("对抗力量", direction.antagonistForce)
                    directionFact("失败代价", direction.stakes)
                }
            }
        }
    }

    private func directionFact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            EyebrowLabel(text: title)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var footer: some View {
        HStack {
            Button("取消") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            switch step {
            case .source:
                Button("继续整理素材", systemImage: "arrow.right") {
                    step = .material
                }
                .buttonStyle(.borderedProminent)
                .disabled(method == nil)
                .keyboardShortcut(.defaultAction)

            case .material:
                Button("返回") {
                    step = .source
                }
                Button {
                    analyze()
                } label: {
                    Label("让 DeepSeek 发现戏剧性", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAnalyze || isWorking || !settings.hasAPIKey)
                .keyboardShortcut(.defaultAction)

            case .direction:
                Button("重新整理素材") {
                    step = .material
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    private var canAnalyze: Bool {
        guard let method else { return false }
        if method == .newsURL {
            return !sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func analyze() {
        Task {
            guard let method else { return }
            isWorking = true
            analysisProgress = 0.02
            analysisElapsedSeconds = 0
            progressMessage = "阶段 1/5 · 准备分析"
            let clock = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    analysisElapsedSeconds += 1
                }
            }
            defer {
                clock.cancel()
                isWorking = false
            }

            do {
                if method == .newsURL,
                   sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    analysisProgress = 0.04
                    progressMessage = "阶段 1/5 · 正在读取网页正文"
                    try await loadURL()
                }
                let cleanTitle = sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                let outcome = try await DramaSeedEngine(settings: settings).dramatize(
                    title: cleanTitle.isEmpty ? method.title : cleanTitle,
                    sourceType: method.sourceType,
                    sourceText: sourceText,
                    authorIntent: authorIntent,
                    progress: { fraction, message in
                        withAnimation(.easeOut(duration: 0.22)) {
                            analysisProgress = fraction
                        }
                        progressMessage = message
                    }
                )
                result = outcome.result
                preparationNote = outcome.preparationNote
                usage = outcome.usage
                analysisProgress = 1
                progressMessage = "分析完成"
                step = .direction
            } catch {
                present(error)
            }
        }
    }

    private func loadURLOnly() {
        Task {
            isWorking = true
            analysisProgress = 0.12
            analysisElapsedSeconds = 0
            progressMessage = "正在读取网页正文…"
            defer { isWorking = false }
            do {
                try await loadURL()
                progressMessage = "网页已读取"
            } catch {
                present(error)
            }
        }
    }

    private var progressFootnote: String {
        if analysisProgress >= 0.68, analysisProgress < 0.96 {
            return "已用时 \(analysisElapsedSeconds) 秒 · 当前等待 DeepSeek 返回；单次请求超过 120 秒会明确报错。"
        }
        return "已用时 \(analysisElapsedSeconds) 秒 · 进度按实际处理阶段更新，不再使用循环动画。"
    }

    private func loadURL() async throws {
        let loaded = try await URLSourceLoader.load(sourceURL)
        if sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sourceTitle = loaded.title
        }
        sourceText = loaded.text
    }

    private func importFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            sourceText = try String(contentsOf: url, encoding: .utf8)
            if sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sourceTitle = url.deletingPathExtension().lastPathComponent
            }
        } catch {
            present(error)
        }
    }

    private func createProject(with direction: AdaptationDirection) {
        guard let method else { return }
        let genre = StoryGenre.allCases.first {
            $0 != .unselected && direction.genre.localizedCaseInsensitiveContains($0.rawValue)
        } ?? .drama
        onCreate(
            NewProjectDraft(
                title: direction.title,
                genre: genre,
                logline: direction.logline,
                sourceTitle: sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? method.title
                    : sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceMethod: method.title,
                sourceType: method.sourceType,
                sourceURL: sourceURL.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceText: sourceText.trimmingCharacters(in: .whitespacesAndNewlines),
                authorIntent: authorIntent.trimmingCharacters(in: .whitespacesAndNewlines),
                dramatization: result,
                selectedDirection: direction,
                preparationNote: preparationNote,
                usage: usage
            )
        )
        dismiss()
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
    }
}
