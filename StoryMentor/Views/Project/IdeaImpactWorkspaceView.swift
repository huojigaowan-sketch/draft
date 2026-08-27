import SwiftData
import SwiftUI

private enum IdeaWorkspaceFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case pending = "待确认"
    case active = "已纳入"
    case inbox = "灵感盒"

    var id: String { rawValue }
}

struct IdeaImpactWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AISettingsStore.self) private var aiSettings

    @Bindable var project: StoryProject
    let onNavigate: (WorkspaceSection) -> Void

    @State private var selectedIdeaID: UUID?
    @State private var filter: IdeaWorkspaceFilter = .all
    @State private var showingCapture = false
    @State private var draftText = ""
    @State private var draftScope: CreativeIdeaScope = .project
    @State private var isAnalyzing = false
    @State private var errorMessage = ""
    @State private var showingError = false
    @FocusState private var isDraftFocused: Bool

    private var allIdeas: [AuthorIdeaRecord] {
        project.authorIdeas.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var visibleIdeas: [AuthorIdeaRecord] {
        allIdeas.filter { idea in
            switch filter {
            case .all: true
            case .pending: idea.status == .proposed || idea.status == .analyzing
            case .active: idea.status == .active || idea.status == .paused
            case .inbox: idea.status == .inbox
            }
        }
    }

    private var selectedIdea: AuthorIdeaRecord? {
        visibleIdeas.first { $0.id == selectedIdeaID } ?? visibleIdeas.first
    }

    private var activeStageIndex: Int? {
        project.nextStructureStageIndex
    }

    private var analysisScopes: [CreativeIdeaScope] {
        activeStageIndex == nil ? [.project] : [.project, .stage]
    }

    private var cleanDraft: String {
        draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var draftScopeExplanation: String {
        if draftScope == .stage,
           let activeStageIndex,
           project.structureTemplate.stages.indices.contains(activeStageIndex) {
            return "只检查第 \(activeStageIndex + 1) 个大节拍“\(project.structureTemplate.stages[activeStageIndex].name)”及其连锁影响。"
        }
        return "对照整部故事的人物、关系、主题、固定结构和连续性进行检查。"
    }

    var body: some View {
        ZStack {
            StudioCanvas()

            VStack(spacing: 0) {
                workspaceHeader
                Divider().opacity(0.45)

                if allIdeas.isEmpty || showingCapture {
                    ideaComposer
                } else {
                    HSplitView {
                        ideaLibrary
                            .frame(minWidth: 250, idealWidth: 285, maxWidth: 340)
                        ideaDetail
                            .frame(minWidth: 520)
                        projectGuardrails
                            .frame(minWidth: 270, idealWidth: 310, maxWidth: 370)
                    }
                }
            }
        }
        .onAppear {
            selectedIdeaID = selectedIdeaID ?? allIdeas.first?.id
            showingCapture = allIdeas.isEmpty
        }
        .onChange(of: project.authorIdeas.count) {
            if selectedIdeaID == nil || selectedIdea == nil {
                selectedIdeaID = allIdeas.first?.id
            }
        }
        .alert("新想法工作区", isPresented: $showingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var workspaceHeader: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                EyebrowLabel(text: "AUTHOR IDEAS", color: StudioTheme.warm)
                Text("新想法与影响分析")
                    .font(.system(size: 26, weight: .semibold, design: .serif))
            }

            Spacer()

            CoreWorkspaceSwitcher(selection: .ideas, onSelect: onNavigate)

            if !allIdeas.isEmpty {
                Button(
                    showingCapture ? "返回影响分析" : "写下新想法",
                    systemImage: showingCapture ? "arrow.left" : "square.and.pencil"
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingCapture.toggle()
                    }
                    if showingCapture {
                        isDraftFocused = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(StudioTheme.warm)
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }

    private var ideaComposer: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    EyebrowLabel(text: "CREATIVE INPUT", color: StudioTheme.warm)
                    Text(allIdeas.isEmpty ? "从你的新意开始" : "继续注入一个新变量")
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                    Text("不要迎合结构，也不用先把想法解释完整。先原样写下来；AI 只负责计算它会改变什么。")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 18)

                Divider()

                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Label("你的原始想法", systemImage: "quote.opening")
                                .font(.headline)
                            Spacer()
                            Text("\(draftText.count) / 8000")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }

                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $draftText)
                                .font(.system(size: 17, design: .serif))
                                .scrollContentBackground(.hidden)
                                .focused($isDraftFocused)
                                .padding(12)
                                .onChange(of: draftText) {
                                    if draftText.count > 8_000 {
                                        draftText = String(draftText.prefix(8_000))
                                    }
                                }

                            if draftText.isEmpty {
                                Text("例如：她不是突然背叛。她从第一场戏起就在保护一个连自己都不愿承认的人……")
                                    .font(.system(size: 17, design: .serif))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 20)
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(minHeight: 220)
                        .background(
                            Color.primary.opacity(0.026),
                            in: RoundedRectangle(cornerRadius: 15)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 15)
                                .stroke(
                                    isDraftFocused
                                        ? StudioTheme.warm.opacity(0.55)
                                        : Color.primary.opacity(0.08),
                                    lineWidth: isDraftFocused ? 1.5 : 1
                                )
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("让 AI 检查多大范围")
                            .font(.headline)

                        Picker("影响范围", selection: $draftScope) {
                            ForEach(analysisScopes) { scope in
                                Label(scope.rawValue, systemImage: scope.systemImage)
                                    .tag(scope)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Label(draftScopeExplanation, systemImage: draftScope.systemImage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    HStack(spacing: 16) {
                        Label(
                            "保存不等于采用。分析不修改结构、人物、场景或剧本文字。",
                            systemImage: "lock.shield.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Spacer()

                        Button("先存灵感盒", systemImage: "tray.and.arrow.down") {
                            saveDraft(scope: .inbox, analyzeAfterSaving: false)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(cleanDraft.isEmpty)

                        Button("保存并分析影响", systemImage: "waveform.path.ecg") {
                            saveDraft(scope: draftScope, analyzeAfterSaving: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(StudioTheme.warm)
                        .keyboardShortcut(.defaultAction)
                        .disabled(cleanDraft.isEmpty)
                    }
                }
                .padding(24)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.primary.opacity(0.07))
            }
            .shadow(color: .black.opacity(0.055), radius: 24, y: 8)
            .frame(maxWidth: .infinity)
            .padding(18)
        }
        .onAppear {
            if !analysisScopes.contains(draftScope) {
                draftScope = .project
            }
            DispatchQueue.main.async {
                isDraftFocused = true
            }
        }
    }

    private var ideaLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("筛选", selection: $filter) {
                ForEach(IdeaWorkspaceFilter.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Text("作者原文")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(visibleIdeas.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            if visibleIdeas.isEmpty {
                ContentUnavailableView {
                    Label("这里还没有想法", systemImage: "lightbulb")
                } description: {
                    Text("灵感先保存，再决定是否让它影响项目。")
                } actions: {
                    Button("捕捉想法") { showingCapture = true }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(visibleIdeas) { idea in
                            ideaRow(idea)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.018))
    }

    private func ideaRow(_ idea: AuthorIdeaRecord) -> some View {
        let selected = selectedIdea?.id == idea.id
        return Button {
            selectedIdeaID = idea.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: statusIcon(idea.status))
                        .foregroundStyle(statusColor(idea.status))
                    Text(idea.status.rawValue)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(statusColor(idea.status))
                    Spacer()
                    Text(idea.updatedAt, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(idea.originalText)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                Label(idea.scope.rawValue, systemImage: idea.scope.systemImage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? StudioTheme.warm.opacity(0.10) : Color.primary.opacity(0.025),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        selected ? StudioTheme.warm.opacity(0.45) : Color.primary.opacity(0.04)
                    )
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var ideaDetail: some View {
        if let idea = selectedIdea {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Label("作者原始输入", systemImage: "quote.opening")
                                .font(.headline)
                            Spacer()
                            PhaseBadge(text: idea.status.rawValue)
                        }
                        Text(idea.originalText)
                            .font(.system(.title3, design: .serif, weight: .medium))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .background(StudioTheme.warm.opacity(0.065), in: RoundedRectangle(cornerRadius: 15))

                    if isAnalyzing && idea.id == selectedIdeaID {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("只分析影响，不修改项目")
                                .font(.callout.weight(.semibold))
                            Text("DeepSeek 正在对照结构、人物、关系、主题和连续性。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)
                    } else if idea.impactSummary.isBlank {
                        ContentUnavailableView {
                            Label("尚未分析影响", systemImage: "scope")
                        } description: {
                            Text("原始想法已经安全保存。分析只会生成变更提案。")
                        } actions: {
                            Button("分析影响", systemImage: "waveform.path.ecg") {
                                analyze(idea)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(minHeight: 230)
                    } else {
                        impactSummary(idea)
                        impactGrid(idea)
                    }
                }
                .padding(22)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label("这个筛选下没有想法", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.title3.weight(.semibold))
                Text("换回“全部”即可继续查看和处理已有想法。")
                    .foregroundStyle(.secondary)
                Button("显示全部") {
                    filter = .all
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(34)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func impactSummary(_ idea: AuthorIdeaRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("影响结论", systemImage: "waveform.path.ecg")
                .font(.headline)
                .foregroundStyle(StudioTheme.accent)
            Text(idea.impactSummary)
                .font(.body)
                .textSelection(.enabled)
            Divider()
            Label("不可稀释的创新核心", systemImage: "lock.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(StudioTheme.warm)
            Text(idea.protectedCore)
                .font(.callout)
                .textSelection(.enabled)
        }
        .padding(16)
        .background(Color.primary.opacity(0.028), in: RoundedRectangle(cornerRadius: 14))
    }

    private func impactGrid(_ idea: AuthorIdeaRecord) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 240), spacing: 12)],
            spacing: 12
        ) {
            impactCard(
                "会受影响",
                icon: "scope",
                items: idea.affectedAreas,
                color: StudioTheme.accent
            )
            impactCard(
                "必须保持",
                icon: "shield.checkered",
                items: idea.preservedElements,
                color: StudioTheme.mint
            )
            impactCard(
                "连续性风险",
                icon: "exclamationmark.triangle.fill",
                items: idea.risks,
                color: StudioTheme.warm
            )
            impactCard(
                "AI 执行清单",
                icon: "gearshape.2.fill",
                items: idea.proposedActions,
                color: StudioTheme.sky
            )
        }
    }

    private func impactCard(
        _ title: String,
        icon: String,
        items: [String],
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            if items.isEmpty {
                Text("无")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(items.prefix(8).enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 7) {
                        Circle()
                            .fill(color)
                            .frame(width: 5, height: 5)
                            .padding(.top, 5)
                        Text(item)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        .background(color.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
    }

    private var projectGuardrails: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    EyebrowLabel(text: "PROJECT GUARDRAILS", color: StudioTheme.mint)
                    Text("作者决定")
                        .font(.title3.weight(.semibold))
                    Text("AI 只呈交影响。是否纳入，始终由你决定。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let idea = selectedIdea {
                    actionPanel(idea)
                }

                Divider()

                Text("项目边界")
                    .font(.headline)

                guardrail(
                    "固定结构",
                    value: project.isStructureLocked
                        ? project.structureTemplate.name
                        : "尚未锁定",
                    icon: project.isStructureLocked ? "lock.fill" : "lock.open"
                )
                guardrail(
                    "已确认大节拍",
                    value: "\(project.resolvedDecisionCount) / \(project.isStructureLocked ? project.structureTemplate.stages.count : 0)",
                    icon: "checkmark.circle"
                )
                guardrail(
                    "人物与关系",
                    value: "\(project.characters.count) 人 · \(project.characterRelationships.count) 条关系",
                    icon: "person.2.fill"
                )
                guardrail(
                    "版本安全",
                    value: "\(project.revisionSnapshots.count) 个项目快照",
                    icon: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                )
            }
            .padding(18)
        }
        .background(.thinMaterial)
    }

    private func guardrail(_ title: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(StudioTheme.mint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 11))
    }

    @ViewBuilder
    private func actionPanel(_ idea: AuthorIdeaRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("作者决定")
                .font(.headline)

            if !idea.impactSummary.isBlank {
                Button("重新分析影响", systemImage: "arrow.clockwise") {
                    analyze(idea)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .disabled(isAnalyzing)
            }

            switch idea.status {
            case .inbox, .proposed:
                Button("确认纳入项目", systemImage: "checkmark.shield.fill") {
                    apply(idea)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(idea.impactSummary.isBlank || isAnalyzing)

                Button("不采用", systemImage: "xmark") {
                    idea.status = .rejected
                    idea.updatedAt = .now
                    savePendingChanges()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

            case .active:
                Button("暂停影响 AI", systemImage: "pause.circle") {
                    setExecution(idea, active: false)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

            case .paused:
                Button("重新纳入执行", systemImage: "play.circle") {
                    setExecution(idea, active: true)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

            case .rejected:
                Button("重新放回待确认", systemImage: "arrow.uturn.backward") {
                    idea.status = .proposed
                    idea.updatedAt = .now
                    savePendingChanges()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

            case .analyzing:
                ProgressView()
                    .frame(maxWidth: .infinity)
            }

            Label(
                "所有应用操作都会先建立项目快照。",
                systemImage: "clock.badge.checkmark"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func saveDraft(
        scope: CreativeIdeaScope,
        analyzeAfterSaving: Bool
    ) {
        guard !cleanDraft.isEmpty else { return }

        let record = AuthorIdeaRecord(
            originalText: String(cleanDraft.prefix(8_000)),
            scope: scope,
            status: scope == .inbox ? .inbox : .proposed,
            targetStageIndex: scope == .stage ? activeStageIndex : nil
        )
        record.project = project
        modelContext.insert(record)

        do {
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            selectedIdeaID = record.id
            draftText = ""
            showingCapture = false

            if analyzeAfterSaving {
                analyze(record)
            }
        } catch {
            modelContext.delete(record)
            present(error.localizedDescription)
        }
    }

    private func analyze(_ idea: AuthorIdeaRecord) {
        guard aiSettings.hasAPIKey else {
            present("请先在设置中保存 DeepSeek API Key。")
            return
        }

        let previousStatus = idea.status
        let requestID = UUID()
        let requestedText = idea.originalText
        let requestedScope = idea.scope
        let requestedStageIndex = idea.targetStageIndex
        let projectRevision = project.updatedAt

        idea.impactAnalysisRequestToken = requestID
        isAnalyzing = true
        idea.status = .analyzing
        idea.updatedAt = .now
        do {
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
        } catch {
            idea.impactAnalysisRequestToken = nil
            isAnalyzing = false
            present(error.localizedDescription)
            return
        }

        Task {
            defer {
                if idea.impactAnalysisRequestToken == requestID {
                    idea.impactAnalysisRequestToken = nil
                    isAnalyzing = false
                }
            }
            do {
                let result = try await StoryImpactAnalyzer.analyze(
                    idea: requestedText,
                    scope: requestedScope,
                    stageIndex: requestedStageIndex,
                    project: project,
                    configuration: try aiSettings.configuration()
                )
                guard idea.impactAnalysisRequestToken == requestID,
                      idea.originalText == requestedText,
                      idea.scope == requestedScope,
                      idea.targetStageIndex == requestedStageIndex,
                      project.updatedAt == projectRevision else {
                    if idea.impactAnalysisRequestToken == requestID {
                        idea.status = previousStatus
                        idea.updatedAt = .now
                        try ProjectPersistenceStore.savePendingChanges(in: modelContext)
                        present("分析期间项目或创意已经更新；旧分析结果已丢弃。")
                    }
                    return
                }

                idea.protectedCore = result.protectedCore
                idea.impactSummary = result.summary
                idea.affectedAreas = result.affectedAreas
                idea.preservedElements = result.preservedElements
                idea.risks = result.risks
                idea.proposedActions = result.proposedActions
                idea.status = previousStatus == .active || previousStatus == .paused
                    ? previousStatus
                    : .proposed
                idea.updatedAt = .now
                try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            } catch {
                guard idea.impactAnalysisRequestToken == requestID else { return }
                idea.status = previousStatus
                idea.updatedAt = .now
                do {
                    try ProjectPersistenceStore.savePendingChanges(in: modelContext)
                } catch {
                    present(error.localizedDescription)
                    return
                }
                present(error.localizedDescription)
            }
        }
    }

    private func apply(_ idea: AuthorIdeaRecord) {
        do {
            try ProjectPersistenceStore.transaction(in: modelContext) {
                StoryCompiler.insertSnapshot(
                    project: project,
                    title: "应用创意前",
                    reason: idea.originalText,
                    in: modelContext
                )
            if idea.scope == .inbox {
                idea.scope = .project
                idea.targetStageIndex = nil
            }
            idea.executionIdeaID = project.addCreativeIdea(
                text: idea.originalText,
                scope: idea.scope,
                stageIndex: idea.targetStageIndex
            )
            idea.status = .active
            idea.appliedAt = .now
            idea.updatedAt = .now

            let changeSet = StoryChangeSet(
                title: "纳入作者创意",
                summary: idea.impactSummary,
                affectedAreas: idea.affectedAreas,
                preservedElements: idea.preservedElements,
                authorIdeaID: idea.id,
                status: .applied
            )
            changeSet.appliedAt = .now
            changeSet.project = project
            modelContext.insert(changeSet)
                StoryCompiler.updateFindings(project: project, in: modelContext)
            }
        } catch {
            present(error.localizedDescription)
        }
    }

    private func setExecution(_ idea: AuthorIdeaRecord, active: Bool) {
        if let executionID = idea.executionIdeaID {
            project.setCreativeIdeaActive(executionID, active: active)
        }
        idea.status = active ? .active : .paused
        idea.updatedAt = .now
        savePendingChanges()
    }

    private func present(_ message: String) {
        errorMessage = message
        showingError = true
    }

    private func savePendingChanges() {
        do {
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
        } catch {
            present(error.localizedDescription)
        }
    }

    private func statusIcon(_ status: AuthorIdeaStatus) -> String {
        switch status {
        case .inbox: "tray.full.fill"
        case .analyzing: "waveform.path.ecg"
        case .proposed: "questionmark.diamond.fill"
        case .active: "checkmark.shield.fill"
        case .paused: "pause.circle.fill"
        case .rejected: "xmark.circle.fill"
        }
    }

    private func statusColor(_ status: AuthorIdeaStatus) -> Color {
        switch status {
        case .active: StudioTheme.mint
        case .analyzing, .proposed: StudioTheme.accent
        case .inbox, .paused: StudioTheme.warm
        case .rejected: .secondary
        }
    }
}

private extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
