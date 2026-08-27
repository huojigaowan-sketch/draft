import SwiftData
import SwiftUI

struct ProjectWorkbenchView: View {
    private enum ModuleFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case active = "待审阅"
        case integrated = "已入稿"

        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var modelContext
    @Bindable var project: StoryProject
    let onNavigate: (WorkspaceSection) -> Void

    @State private var selectedModuleID: UUID?
    @State private var filter = ModuleFilter.all
    @State private var errorMessage = ""
    @State private var showingError = false

    private var modules: [ProjectArtifact] {
        project.artifacts.sorted {
            if $0.sortIndex == $1.sortIndex {
                return $0.createdAt < $1.createdAt
            }
            return $0.sortIndex < $1.sortIndex
        }
    }

    private var visibleModules: [ProjectArtifact] {
        switch filter {
        case .all:
            modules
        case .active:
            modules.filter { $0.status != .integrated }
        case .integrated:
            modules.filter { $0.status == .integrated }
        }
    }

    private var selectedModule: ProjectArtifact? {
        guard let selectedModuleID else { return visibleModules.first ?? modules.first }
        return modules.first { $0.id == selectedModuleID }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HSplitView {
                moduleBrowser
                    .frame(minWidth: 230, idealWidth: 270, maxWidth: 330)

                if let selectedModule {
                    ProjectArtifactEditorView(
                        project: project,
                        module: selectedModule,
                        onNavigate: onNavigate,
                        onDelete: { delete(selectedModule) }
                    )
                    .frame(minWidth: 480)
                } else {
                    emptyState
                        .frame(minWidth: 480)
                }
            }
        }
        .background(StudioCanvas())
        .navigationSplitViewColumnWidth(min: 680, ideal: 920)
        .task {
            bootstrapIfNeeded()
            if selectedModuleID == nil {
                selectedModuleID = modules.first?.id
            }
        }
        .alert("项目暂时无法保存", isPresented: $showingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var header: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                EyebrowLabel(text: "Project Writing Room", color: StudioTheme.mint)
                Text(project.title)
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                HStack(spacing: 9) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(StudioTheme.warm)
                    TextField(
                        "写下整个项目的创作方向，例如：克制、荒诞、拒绝英雄叙事、重视普通人的具体生活……",
                        text: $project.creativeDirectionText,
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .onChange(of: project.creativeDirectionText) { _, _ in
                        project.creativeIdeasContextUpdatedAt = .now
                        project.touch()
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(StudioTheme.warm.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: 720)
            }

            Spacer()

            metric(
                value: "\(modules.filter { $0.status == .integrated }.count)",
                label: "已确认",
                icon: "checkmark.seal.fill",
                tint: StudioTheme.mint
            )
            metric(
                value: "\(modules.filter { $0.status != .integrated }.count)",
                label: "待审阅",
                icon: "pencil.and.outline",
                tint: StudioTheme.warm
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial)
    }

    private func metric(
        value: String,
        label: String,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline.monospacedDigit())
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private var moduleBrowser: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("项目内容")
                            .font(.headline)
                        Text("像 Ulysses 一样逐张整理")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        ForEach(ProjectModuleKind.allCases) { kind in
                            Button(kind.rawValue, systemImage: kind.systemImage) {
                                addModule(kind)
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 30, height: 30)
                            .background(StudioTheme.accent, in: Circle())
                            .foregroundStyle(.white)
                    }
                    .menuStyle(.borderlessButton)
                }

                Picker("筛选", selection: $filter) {
                    ForEach(ModuleFilter.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(14)

            Divider()

            List(visibleModules, selection: $selectedModuleID) { module in
                moduleRow(module)
                    .tag(module.id)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(.ultraThinMaterial)
        .onChange(of: filter) { _, _ in
            if let selectedModuleID,
               !visibleModules.contains(where: { $0.id == selectedModuleID }) {
                self.selectedModuleID = visibleModules.first?.id
            }
        }
    }

    private func moduleRow(_ module: ProjectArtifact) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: module.kind.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint(for: module.kind))
                .frame(width: 28, height: 28)
                .background(tint(for: module.kind).opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(module.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(module.kind.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Label(module.status.rawValue, systemImage: module.status.systemImage)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(
                        module.status == .integrated
                            ? StudioTheme.mint
                            : StudioTheme.warm
                    )
            }
        }
        .padding(.vertical, 5)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("项目还没有创作卡", systemImage: "leaf")
        } description: {
            Text("从人物、新闻、经典、世界或一个模糊想法开始。")
        } actions: {
            Button("添加第一张灵感卡") {
                addModule(.inspiration)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func addModule(_ kind: ProjectModuleKind) {
        let module = ProjectArtifact(
            title: kind.defaultTitle,
            kind: kind,
            sortIndex: modules.count,
            project: project
        )
        modelContext.insert(module)
        project.artifacts.append(module)
        project.touch()
        selectedModuleID = module.id
        filter = .all
        save()
    }

    private func delete(_ module: ProjectArtifact) {
        if module.status == .integrated {
            module.withdrawFromFormalContent()
        }
        project.artifacts.removeAll { $0.id == module.id }
        modelContext.delete(module)
        selectedModuleID = modules.first { $0.id != module.id }?.id
        project.touch()
        save()
    }

    private func bootstrapIfNeeded() {
        guard project.artifacts.isEmpty else { return }
        var nextIndex = 0

        func insert(
            title: String,
            kind: ProjectModuleKind,
            origin: String,
            humanInput: String,
            accepted: String
        ) {
            let module = ProjectArtifact(
                title: title,
                kind: kind,
                status: accepted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? .seed
                    : .integrated,
                originLabel: origin,
                humanInput: humanInput,
                workingText: accepted,
                acceptedText: accepted,
                sortIndex: nextIndex,
                project: project
            )
            if !accepted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                module.integratedSnapshot = accepted
            }
            nextIndex += 1
            modelContext.insert(module)
            project.artifacts.append(module)
        }

        if !project.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            insert(
                title: project.sourceTitle.isEmpty ? "原始素材" : project.sourceTitle,
                kind: .source,
                origin: "现实 / 文档",
                humanInput: project.sourceText,
                accepted: project.sourceFacts
            )
        }
        if !project.logline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !project.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            insert(
                title: "故事核心",
                kind: .inspiration,
                origin: "用户已有内容",
                humanInput: project.logline,
                accepted: project.notes.isEmpty ? project.logline : project.notes
            )
        }
        if !project.storyPathText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            insert(
                title: "已经确认的故事路径",
                kind: .storyPath,
                origin: "互动选择",
                humanInput: "",
                accepted: project.storyPathText
            )
        }
        if !project.worldText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            insert(title: "世界设定", kind: .world, origin: "已有项目", humanInput: "", accepted: project.worldText)
        }
        if !project.themeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            insert(title: "主题命题", kind: .theme, origin: "已有项目", humanInput: "", accepted: project.themeText)
        }
        if !project.structureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            insert(title: "结构路线", kind: .structure, origin: "已有项目", humanInput: "", accepted: project.structureText)
        }
        if !project.scenesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            insert(title: "场景卡", kind: .scene, origin: "已有项目", humanInput: "", accepted: project.scenesText)
        }
        if !project.screenplayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            insert(title: "正式剧本", kind: .screenplay, origin: "已有项目", humanInput: "", accepted: project.screenplayText)
        }
        if project.artifacts.isEmpty {
            insert(title: "第一颗种子", kind: .inspiration, origin: "用户灵感", humanInput: "", accepted: "")
        }
        project.touch()
        save()
    }

    private func save() {
        do {
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func tint(for kind: ProjectModuleKind) -> Color {
        switch kind {
        case .inspiration, .source: StudioTheme.mint
        case .research, .world: StudioTheme.sky
        case .character, .relationship: StudioTheme.warm
        case .theme, .storyPath, .structure: StudioTheme.accent
        case .scene, .blueprint, .screenplay: StudioTheme.mint
        }
    }
}

private struct ProjectArtifactEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AISettingsStore.self) private var settings

    @Bindable var project: StoryProject
    @Bindable var module: ProjectArtifact
    let onNavigate: (WorkspaceSection) -> Void
    let onDelete: () -> Void

    @State private var isGenerating = false
    @State private var isRefining = false
    @State private var showingResearch = false
    @State private var errorMessage = ""
    @State private var showingError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                editorHeader
                humanIdeaCard
                aiOptionsCard

                if !module.workingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    collaborationLoopCard
                    reviewCard
                }

                if !module.revisions.isEmpty {
                    revisionCard
                }
            }
            .padding(22)
            .frame(maxWidth: 1_080)
            .frame(maxWidth: .infinity)
        }
        .background(StudioCanvas())
        .alert("这张创作卡暂停了", isPresented: $showingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingResearch) {
            ProjectModuleResearchSheet(
                project: project,
                module: module,
                onUseResearch: {
                    showingResearch = false
                    module.aiInstruction = """
                    请优先使用刚完成的专项资料包，为当前模块重新设计4个更真实、具体、立体的方向。
                    每个方向必须指出使用了哪类现实细节，并继续遵守用户历次审阅形成的偏好。
                    """
                    generateOptions()
                }
            )
        }
    }

    private var editorHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: module.kind.systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(StudioTheme.accent)
                .frame(width: 48, height: 48)
                .background(StudioTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 7) {
                TextField("创作卡名称", text: $module.title)
                    .textFieldStyle(.plain)
                    .font(.system(.title, design: .serif, weight: .semibold))
                HStack(spacing: 8) {
                    Picker("模块", selection: $module.kindRawValue) {
                        ForEach(ProjectModuleKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind.rawValue)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    PhaseBadge(text: module.status.rawValue)
                    Text(module.originLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("调查", systemImage: "globe.desk.fill") {
                showingResearch = true
            }
            .buttonStyle(.bordered)
            .help("围绕当前模块全网调查资料")

            Menu {
                Button("打开对应正式模块", systemImage: module.kind.systemImage) {
                    onNavigate(module.kind.workspaceSection)
                }
                Divider()
                Button("删除创作卡", systemImage: "trash", role: .destructive) {
                    onDelete()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .menuStyle(.borderlessButton)
        }
    }

    private var humanIdeaCard: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label("你的原始灵感", systemImage: "person.fill")
                        .font(.headline)
                        .foregroundStyle(StudioTheme.mint)
                    Spacer()
                    Text("AI不会覆盖这里")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                TextEditor(text: $module.humanInput)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 105)
                    .padding(9)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
                    .overlay(alignment: .topLeading) {
                        if module.humanInput.isEmpty {
                            Text("写下一个画面、人物、新闻、历史细节、语气或任何你不想丢掉的想法……")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(15)
                                .allowsHitTesting(false)
                        }
                    }

                DisclosureGroup("不可改动的决定") {
                    TextEditor(text: $module.lockedIdeas)
                        .font(.callout)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 72)
                        .padding(8)
                        .background(StudioTheme.warm.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .topLeading) {
                            if module.lockedIdeas.isEmpty {
                                Text("例如：保留真实年代；主角不能死亡；不要改变这段关系……")
                                    .font(.callout)
                                    .foregroundStyle(.tertiary)
                                    .padding(14)
                                    .allowsHitTesting(false)
                            }
                        }
                        .padding(.top, 8)
                }
                .font(.callout.weight(.semibold))
            }
        }
    }

    private var aiOptionsCard: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("让 AI 提供道路", systemImage: "sparkles")
                            .font(.headline)
                            .foregroundStyle(StudioTheme.accent)
                        Text("DeepSeek会结合项目已确认内容、结构规则、经典案例和本地编剧书库。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        generateOptions()
                    } label: {
                        if isGenerating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label(module.options.isEmpty ? "生成四个方向" : "换四个方向", systemImage: "square.grid.2x2")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        isGenerating
                            || module.humanInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }

                if !module.aiSummary.isEmpty {
                    Text(module.aiSummary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .background(StudioTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }

                if let result = module.researchResult {
                    HStack(spacing: 9) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(StudioTheme.sky)
                        Text("已接入 \(result.sources.count) 条专项资料，生成时会自动使用")
                            .font(.caption.weight(.medium))
                        Spacer()
                        Button("查看资料") {
                            showingResearch = true
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(10)
                    .background(StudioTheme.sky.opacity(0.065), in: RoundedRectangle(cornerRadius: 10))
                }

                if !module.options.isEmpty {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ],
                        spacing: 12
                    ) {
                        ForEach(module.options) { option in
                            optionCard(option)
                        }
                    }
                }
            }
        }
    }

    private func optionCard(_ option: ProjectModuleOption) -> some View {
        let selected = module.selectedOptionID == option.id
        return Button {
            module.select(option)
            save()
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(option.title)
                        .font(.system(.headline, design: .serif))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(
                            selected
                                ? StudioTheme.mint
                                : Color.secondary.opacity(0.38)
                        )
                }
                Text(option.oneLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Label(option.storyEffect, systemImage: "arrow.triangle.branch")
                    .font(.caption2)
                    .foregroundStyle(StudioTheme.accent)
                    .fixedSize(horizontal: false, vertical: true)
                Label(option.tradeoff, systemImage: "scalemass")
                    .font(.caption2)
                    .foregroundStyle(StudioTheme.warm)
                    .fixedSize(horizontal: false, vertical: true)
                if !option.responseToFeedback.isEmpty {
                    Label(option.responseToFeedback, systemImage: "quote.bubble.fill")
                        .font(.caption2)
                        .foregroundStyle(StudioTheme.mint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .padding(14)
            .background(
                selected
                    ? StudioTheme.mint.opacity(0.10)
                    : Color.primary.opacity(0.025),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        selected ? StudioTheme.mint.opacity(0.45) : Color.primary.opacity(0.05),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private var collaborationLoopCard: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        EyebrowLabel(text: "Human Direction Loop", color: StudioTheme.mint)
                        Text("告诉 AI 哪里还不像你的作品")
                            .font(.system(.title2, design: .serif, weight: .semibold))
                        Text("意见会先被整理成创作约束，再生成四个新的解决方案。每一轮都会积累成这个项目独有的作者偏好。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !module.reviewRounds.isEmpty {
                        PhaseBadge(text: "已审阅 \(module.reviewRounds.count) 轮")
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ProjectReviewOperation.allCases) { operation in
                            Button {
                                module.reviewOperation = operation
                            } label: {
                                Label(operation.rawValue, systemImage: operation.systemImage)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .foregroundStyle(
                                        module.reviewOperation == operation
                                            ? Color.white
                                            : Color.secondary
                                    )
                                    .background(
                                        module.reviewOperation == operation
                                            ? StudioTheme.accent
                                            : Color.primary.opacity(0.04),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Label("修改范围", systemImage: "viewfinder")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField(
                        "例如：主角的职业欲望、母女关系、第二幕中点、这场戏的结尾……",
                        text: $module.reviewScope
                    )
                    .textFieldStyle(.roundedBorder)
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $module.reviewFeedback)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 105)
                        .padding(9)
                        .background(
                            Color(nsColor: .textBackgroundColor).opacity(0.72),
                            in: RoundedRectangle(cornerRadius: 11)
                        )
                    if module.reviewFeedback.isEmpty {
                        Text("例如：这个主角还是太正确了。我希望他有一种令人喜欢、但最终会伤害别人的幽默感；不要增加童年创伤……")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(15)
                            .allowsHitTesting(false)
                    }
                }

                HStack {
                    if !module.authorGuidanceText.isEmpty {
                        DisclosureGroup("查看 AI 已学会的作者偏好") {
                            Text(module.authorGuidanceText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .padding(.top, 8)
                        }
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: 360)
                    }
                    Spacer()
                    Button {
                        regenerateFromReview()
                    } label: {
                        if isGenerating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("提交意见，重新生成四个方向", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        isGenerating
                            || module.reviewFeedback
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                    )
                }
            }
        }
    }

    private var reviewCard: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("人类审阅稿", systemImage: "pencil.and.outline")
                            .font(.headline)
                            .foregroundStyle(StudioTheme.warm)
                        Text("这里可以任意改写。正式内容不会变化，直到你确认。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if module.status == .integrated {
                        Label("当前版本已入稿", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(StudioTheme.mint)
                    }
                }

                TextEditor(text: $module.workingText)
                    .font(.system(.body, design: .serif))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 250)
                    .padding(12)
                    .background(
                        Color(nsColor: .textBackgroundColor).opacity(0.78),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.06))
                    }

                VStack(alignment: .leading, spacing: 8) {
                    EyebrowLabel(text: "只做这一个微调", color: StudioTheme.sky)
                    TextField(
                        "例如：不改变事件，只让关系更暧昧；缩短20%；保留结尾但加强动作……",
                        text: $module.aiInstruction
                    )
                    .textFieldStyle(.roundedBorder)
                    HStack {
                        Button {
                            refine()
                        } label: {
                            if isRefining {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("按命令微调", systemImage: "wand.and.rays")
                            }
                        }
                        .disabled(
                            isRefining
                                || module.aiInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )

                        Spacer()

                        if module.status == .integrated {
                            Button("继续审阅", systemImage: "pencil") {
                                module.reopenForReview()
                                save()
                            }
                            Button("从正式内容撤回", systemImage: "arrow.uturn.backward") {
                                module.withdrawFromFormalContent()
                                save()
                            }
                        }

                        Button("确认并加入正式内容", systemImage: "checkmark.seal.fill") {
                            module.confirmAndIntegrate()
                            save()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(12)
                .background(StudioTheme.sky.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var revisionCard: some View {
        StudioCard {
            DisclosureGroup("历史版本 · \(module.revisions.count)") {
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(module.revisions) { revision in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(revision.note)
                                    .font(.caption.weight(.semibold))
                                Text(revision.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text(revision.text)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                            Spacer()
                            Button("恢复") {
                                module.recordRevision(note: "恢复历史版本前")
                                module.workingText = revision.text
                                module.status = .reviewing
                                module.updatedAt = .now
                                save()
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .padding(.top, 12)
            }
        }
    }

    private func generateOptions(fromReview: Bool = false) {
        guard !isGenerating else { return }
        Task {
            isGenerating = true
            defer { isGenerating = false }
            do {
                let outcome = try await ProjectModuleEngine(settings: settings)
                    .generateOptions(for: module, in: project)
                module.options = outcome.result.options
                module.aiSummary = outcome.result.guidance
                module.selectedOptionID = nil
                module.status = .optionsReady
                if fromReview {
                    module.reviewFeedback = ""
                    module.reviewScope = ""
                }
                module.aiInstruction = ""
                module.updatedAt = .now
                project.touch()
                try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            } catch {
                present(error)
            }
        }
    }

    private func regenerateFromReview() {
        guard module.captureReview() != nil else { return }
        save()
        generateOptions(fromReview: true)
    }

    private func refine() {
        guard !isRefining else { return }
        Task {
            isRefining = true
            defer { isRefining = false }
            do {
                let outcome = try await ProjectModuleEngine(settings: settings)
                    .refine(module, in: project)
                module.recordRevision(note: "AI微调前")
                module.workingText = outcome.result.revisedText
                module.aiSummary = outcome.result.changeSummary
                module.status = .reviewing
                module.updatedAt = .now
                project.touch()
                try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            } catch {
                present(error)
            }
        }
    }

    private func save() {
        do {
            module.updatedAt = .now
            project.touch()
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
    }
}

private struct ProjectModuleResearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let project: StoryProject
    let module: ProjectArtifact
    let onUseResearch: () -> Void

    @State private var query = ""
    @State private var depth = ResearchDepth.deep
    @State private var isResearching = false
    @State private var errorMessage = ""
    @State private var showingError = false
    @FocusState private var queryFocused: Bool

    private var result: RealityResearchResult? {
        module.researchResult
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "globe.desk.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(StudioTheme.sky)
                    .frame(width: 46, height: 46)
                    .background(StudioTheme.sky.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    EyebrowLabel(text: "Context Research", color: StudioTheme.sky)
                    Text("为“\(module.title)”专项调查")
                        .font(.system(.title2, design: .serif, weight: .semibold))
                    Text("资料只进入这张项目卡，并自动成为下一轮四个方向的现实底座。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    StudioCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("调查问题", systemImage: "magnifyingglass")
                                .font(.headline)
                            TextField(
                                "输入要核实的人物、职业、制度、年代、地点、物件或真实流程",
                                text: $query,
                                axis: .vertical
                            )
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...5)
                            .focused($queryFocused)

                            HStack {
                                Picker("深度", selection: $depth) {
                                    ForEach(ResearchDepth.allCases) { item in
                                        Text(item.rawValue).tag(item)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 430)

                                Spacer()

                                Button {
                                    runResearch()
                                } label: {
                                    if isResearching {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Label("开始全网调查", systemImage: "network")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .keyboardShortcut(.return, modifiers: [.command])
                                .disabled(
                                    isResearching
                                        || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                )
                            }
                        }
                    }

                    if let result {
                        StudioCard {
                            VStack(alignment: .leading, spacing: 11) {
                                HStack {
                                    Label("调查摘要", systemImage: "checkmark.seal.fill")
                                        .font(.headline)
                                        .foregroundStyle(StudioTheme.mint)
                                    Spacer()
                                    PhaseBadge(text: "\(result.sources.count) 个来源")
                                }
                                Text(result.summary)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(result.providers.joined(separator: " · "))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !result.dramaticPressures.isEmpty {
                            StudioCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Label("资料揭示的戏剧压力", systemImage: "bolt.heart.fill")
                                        .font(.headline)
                                        .foregroundStyle(StudioTheme.warm)
                                    ForEach(result.dramaticPressures) { pressure in
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(pressure.title)
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(StudioTheme.warm)
                                            Text(pressure.question)
                                                .font(.callout)
                                        }
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            StudioTheme.warm.opacity(0.06),
                                            in: RoundedRectangle(cornerRadius: 10)
                                        )
                                    }
                                }
                            }
                        }

                        StudioCard {
                            DisclosureGroup("事实与来源 · \(result.sources.count)") {
                                VStack(alignment: .leading, spacing: 11) {
                                    ForEach(Array(result.sources.prefix(20).enumerated()), id: \.element.id) { index, source in
                                        HStack(alignment: .top, spacing: 10) {
                                            Text("S\(index + 1)")
                                                .font(.caption2.monospaced().weight(.bold))
                                                .foregroundStyle(StudioTheme.sky)
                                                .frame(width: 28, alignment: .leading)
                                            VStack(alignment: .leading, spacing: 3) {
                                                if let url = URL(string: source.url), !source.url.isEmpty {
                                                    Link(source.title, destination: url)
                                                        .font(.callout.weight(.semibold))
                                                } else {
                                                    Text(source.title)
                                                        .font(.callout.weight(.semibold))
                                                }
                                                Text(
                                                    [source.publisher, source.publishedAt, source.provider]
                                                        .filter { !$0.isEmpty }
                                                        .joined(separator: " · ")
                                                )
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                if !source.snippet.isEmpty {
                                                    Text(source.snippet)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(3)
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.top, 12)
                            }
                        }

                        HStack {
                            Spacer()
                            Button("用这份资料重新生成四个方向", systemImage: "sparkles") {
                                onUseResearch()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .keyboardShortcut(.defaultAction)
                        }
                    } else if !isResearching {
                        StudioCard {
                            HStack(spacing: 15) {
                                Image(systemName: "books.vertical.fill")
                                    .font(.title)
                                    .foregroundStyle(StudioTheme.sky)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("调查结果属于当前项目")
                                        .font(.headline)
                                    Text("系统会检索新闻、百科、知识实体、学术研究与开放档案；如已配置 Firecrawl，也会进行更深网页抓取。")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .background(StudioCanvas())
        }
        .frame(minWidth: 820, minHeight: 760)
        .task {
            if query.isEmpty {
                query = module.researchQuery.isEmpty
                    ? suggestedQuery
                    : module.researchQuery
            }
            queryFocused = true
        }
        .alert("资料调查暂停了", isPresented: $showingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var suggestedQuery: String {
        let scope = module.reviewScope.trimmingCharacters(in: .whitespacesAndNewlines)
        let core = module.workingText.isEmpty ? module.humanInput : module.workingText
        return [
            project.genre.rawValue,
            module.kind.rawValue,
            scope,
            String(core.prefix(180))
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    private func runResearch() {
        guard !isResearching else { return }
        Task {
            isResearching = true
            defer { isResearching = false }
            do {
                let firecrawlKey = (try? ResearchCredentialStore.readFirecrawlKey()) ?? ""
                let projectMaterial = """
                【项目创作方向】
                \(project.creativeContext())

                【当前模块原始灵感】
                \(module.humanInput)

                【当前审阅稿】
                \(module.workingText)

                【不可改动决定】
                \(module.lockedIdeas)

                【作者历次意见】
                \(module.authorGuidanceText)
                """
                let research = try await RealityResearchEngine().research(
                    RealityResearchRequest(
                        title: "\(project.title) · \(module.title)",
                        query: query.trimmingCharacters(in: .whitespacesAndNewlines),
                        sourceURL: "",
                        sourceText: String(projectMaterial.prefix(8_000)),
                        authorIntent: "只为当前\(module.kind.rawValue)提供真实资料、关系、制度、历史与物质细节，不代替作者作故事决定。",
                        depth: depth.rawValue,
                        maxSources: depth.sourceLimit,
                        firecrawlAPIKey: firecrawlKey
                    )
                )
                module.researchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
                module.researchResult = research
                module.updatedAt = .now
                project.touch()
                try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}
