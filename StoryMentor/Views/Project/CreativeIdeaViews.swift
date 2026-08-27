import SwiftData
import SwiftUI

private struct LegacyCreativeInjectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var project: StoryProject
    let defaultScope: CreativeIdeaScope
    var onSaved: (() -> Void)?

    @State private var text = ""
    @State private var scope: CreativeIdeaScope
    @State private var showingSaveError = false
    @State private var saveError = ""
    @FocusState private var isEditorFocused: Bool

    init(
        project: StoryProject,
        defaultScope: CreativeIdeaScope = .project,
        onSaved: (() -> Void)? = nil
    ) {
        self.project = project
        self.defaultScope = defaultScope
        self.onSaved = onSaved
        _scope = State(initialValue: defaultScope)
    }

    private var activeStageIndex: Int? {
        project.nextStructureStageIndex
    }

    private var availableScopes: [CreativeIdeaScope] {
        activeStageIndex == nil
            ? [.project, .inbox]
            : CreativeIdeaScope.allCases
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "lightbulb.max.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(StudioTheme.warm)
                    .frame(width: 44, height: 44)
                    .background(StudioTheme.warm.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 3) {
                    Text("注入一个新想法")
                        .font(.system(.title2, design: .serif, weight: .semibold))
                    Text("不用离开当前工作，也不用等到下一个流程。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(22)

            Divider()

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("你的想法")
                        .font(.headline)

                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $text)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .focused($isEditorFocused)
                            .padding(8)

                        if text.isEmpty {
                            Text("例如：我突然想到，妹妹其实一直知道真相；不要增加新事件，只让这段关系变得更危险……")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(minHeight: 130)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.07))
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("影响范围")
                        .font(.headline)

                    Picker("影响范围", selection: $scope) {
                        ForEach(availableScopes) { item in
                            Label(item.rawValue, systemImage: item.systemImage)
                                .tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Label(scopeExplanation, systemImage: scope.systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Label(
                    "已确认的结构选择不会被悄悄改写；这个想法只影响之后主动触发的 AI 生成。",
                    systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StudioTheme.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(22)

            Divider()

            HStack {
                Button("取消", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(scope == .inbox ? "保存灵感" : "注入创作", systemImage: "arrow.down.to.line.compact") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(18)
        }
        .frame(width: 610)
        .background(StudioTheme.canvas)
        .onAppear {
            if scope == .stage, activeStageIndex == nil {
                scope = .project
            }
            isEditorFocused = true
        }
        .alert("无法保存这个想法", isPresented: $showingSaveError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(saveError)
        }
    }

    private var scopeExplanation: String {
        if scope == .stage,
           let activeStageIndex,
           project.structureTemplate.stages.indices.contains(activeStageIndex) {
            return "只用于第 \(activeStageIndex + 1) 个大节拍“\(project.structureTemplate.stages[activeStageIndex].name)”。"
        }
        return scope.explanation
    }

    private func save() {
        let previousIdeasData = project.creativeIdeasData
        let previousUpdatedAt = project.updatedAt
        let previousContextUpdatedAt = project.creativeIdeasContextUpdatedAt

        _ = project.addCreativeIdea(
            text: text,
            scope: scope,
            stageIndex: activeStageIndex
        )
        do {
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            onSaved?()
            dismiss()
        } catch {
            project.creativeIdeasData = previousIdeasData
            project.updatedAt = previousUpdatedAt
            project.creativeIdeasContextUpdatedAt = previousContextUpdatedAt
            saveError = error.localizedDescription
            showingSaveError = true
        }
    }
}

struct CreativeInjectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AISettingsStore.self) private var aiSettings

    @Bindable var project: StoryProject
    let defaultScope: CreativeIdeaScope
    var onSaved: (() -> Void)?

    @State private var text = ""
    @State private var scope: CreativeIdeaScope
    @State private var savedIdea: AuthorIdeaRecord?
    @State private var impact: IdeaImpactAnalysis?
    @State private var isAnalyzing = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @FocusState private var isEditorFocused: Bool

    init(
        project: StoryProject,
        defaultScope: CreativeIdeaScope = .project,
        onSaved: (() -> Void)? = nil
    ) {
        self.project = project
        self.defaultScope = defaultScope
        self.onSaved = onSaved
        _scope = State(initialValue: defaultScope)
    }

    private var activeStageIndex: Int? { project.nextStructureStageIndex }

    private var availableScopes: [CreativeIdeaScope] {
        activeStageIndex == nil ? [.project, .inbox] : CreativeIdeaScope.allCases
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                Group {
                    if savedIdea == nil {
                        captureForm
                    } else {
                        impactReview
                    }
                }
                .padding(22)
            }

            Divider()
            actionBar
        }
        .frame(width: 700, height: savedIdea == nil ? 590 : 680)
        .background(StudioTheme.canvas)
        .onAppear {
            if scope == .stage, activeStageIndex == nil {
                scope = .project
            }
            isEditorFocused = true
        }
        .alert("无法完成操作", isPresented: $showingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(
                systemName: savedIdea == nil
                    ? "lightbulb.max.fill"
                    : "point.3.filled.connected.trianglepath.dotted"
            )
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(StudioTheme.warm)
            .frame(width: 44, height: 44)
            .background(StudioTheme.warm.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 3) {
                Text(savedIdea == nil ? "捕捉作者创意" : "确认影响后再纳入")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                Text(
                    savedIdea == nil
                        ? "先完整保存你的原话，再让 AI 做影响分析。"
                        : "AI 只报告影响；没有你的确认，项目不会改变。"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(22)
    }

    private var captureForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("你的原始想法")
                    .font(.headline)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .focused($isEditorFocused)
                        .padding(8)

                    if text.isEmpty {
                        Text("例如：妹妹其实一直知道真相；不要增加新事件，只让这段关系变得更危险……")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 150)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.07))
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("你允许它影响哪里")
                    .font(.headline)
                Picker("影响范围", selection: $scope) {
                    ForEach(availableScopes) { item in
                        Label(item.rawValue, systemImage: item.systemImage)
                            .tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Label(scopeExplanation, systemImage: scope.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Label(
                "保存不等于应用。已锁定结构、人物事实和剧本文字都不会被悄悄改写。",
                systemImage: "lock.shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StudioTheme.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private var impactReview: some View {
        if let savedIdea {
            VStack(alignment: .leading, spacing: 8) {
                Label("作者原文 · 已安全保存", systemImage: "quote.opening")
                    .font(.headline)
                    .foregroundStyle(StudioTheme.warm)
                Text(savedIdea.originalText)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
            }

            if isAnalyzing {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("DeepSeek 正在检查人物、关系、结构、主题和连续性影响…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("它无权修改项目。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 34)
            } else if let impact {
                VStack(alignment: .leading, spacing: 15) {
                    reviewSection(
                        title: "影响结论",
                        icon: "waveform.path.ecg",
                        items: [impact.summary],
                        color: StudioTheme.accent
                    )
                    reviewSection(
                        title: "必须保护的创新核心",
                        icon: "lock.fill",
                        items: [impact.protectedCore],
                        color: StudioTheme.warm
                    )
                    HStack(alignment: .top, spacing: 12) {
                        reviewSection(
                            title: "会受影响",
                            icon: "scope",
                            items: impact.affectedAreas,
                            color: StudioTheme.accent
                        )
                        reviewSection(
                            title: "保持不动",
                            icon: "shield.checkered",
                            items: impact.preservedElements,
                            color: StudioTheme.mint
                        )
                    }
                    HStack(alignment: .top, spacing: 12) {
                        reviewSection(
                            title: "需要检查",
                            icon: "exclamationmark.triangle",
                            items: impact.risks,
                            color: StudioTheme.warm
                        )
                        reviewSection(
                            title: "AI 可接手",
                            icon: "gearshape.2",
                            items: impact.proposedActions,
                            color: StudioTheme.mint
                        )
                    }
                }
            } else {
                ContentUnavailableView(
                    "想法已保存，影响分析尚未完成",
                    systemImage: "externaldrive.badge.checkmark",
                    description: Text(
                        errorMessage.isEmpty
                            ? "可以稍后重新分析，或仅保存在项目中。"
                            : errorMessage
                    )
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
        }
    }

    private func reviewSection(
        title: String,
        icon: String,
        items: [String],
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            ForEach(
                Array(items.filter { !$0.isBlank }.prefix(6).enumerated()),
                id: \.offset
            ) { _, item in
                Text(item)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(color.opacity(0.065), in: RoundedRectangle(cornerRadius: 11))
    }

    @ViewBuilder
    private var actionBar: some View {
        HStack {
            if savedIdea == nil {
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("仅保存，暂不应用") { keepForLater() }
                    .keyboardShortcut(.cancelAction)
            }

            Spacer()

            if savedIdea == nil {
                Button(
                    scope == .inbox ? "保存到灵感盒" : "保存并分析影响",
                    systemImage: scope == .inbox
                        ? "tray.and.arrow.down"
                        : "point.3.filled.connected.trianglepath.dotted"
                ) {
                    saveAndAnalyze()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else if impact != nil {
                Button("确认纳入项目", systemImage: "checkmark.shield.fill") {
                    applyIdea()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else if !isAnalyzing {
                Button("重新分析", systemImage: "arrow.clockwise") {
                    analyzeSavedIdea()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
    }

    private var scopeExplanation: String {
        if scope == .stage,
           let activeStageIndex,
           project.structureTemplate.stages.indices.contains(activeStageIndex) {
            return "只用于第 \(activeStageIndex + 1) 个大节拍“\(project.structureTemplate.stages[activeStageIndex].name)”。"
        }
        return scope.explanation
    }

    private func saveAndAnalyze() {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let record = AuthorIdeaRecord(
            originalText: String(clean.prefix(8_000)),
            scope: scope,
            status: scope == .inbox ? .inbox : .analyzing,
            targetStageIndex: scope == .stage ? activeStageIndex : nil
        )
        record.project = project
        modelContext.insert(record)
        do {
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            savedIdea = record
            if scope == .inbox {
                onSaved?()
                dismiss()
            } else {
                analyzeSavedIdea()
            }
        } catch {
            modelContext.delete(record)
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func analyzeSavedIdea() {
        guard let savedIdea else { return }
        guard aiSettings.hasAPIKey else {
            savedIdea.status = .proposed
            savedIdea.updatedAt = .now
            do {
                try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
                return
            }
            errorMessage = "尚未配置 DeepSeek API Key。原始想法已经保存，没有进入执行上下文。"
            return
        }

        let requestID = UUID()
        let requestedText = savedIdea.originalText
        let requestedScope = savedIdea.scope
        let requestedStageIndex = savedIdea.targetStageIndex
        let projectRevision = project.updatedAt

        savedIdea.impactAnalysisRequestToken = requestID
        isAnalyzing = true
        impact = nil
        errorMessage = ""
        savedIdea.status = .analyzing
        savedIdea.updatedAt = .now
        do {
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
        } catch {
            savedIdea.impactAnalysisRequestToken = nil
            isAnalyzing = false
            errorMessage = error.localizedDescription
            showingError = true
            return
        }

        Task {
            defer {
                if savedIdea.impactAnalysisRequestToken == requestID {
                    savedIdea.impactAnalysisRequestToken = nil
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
                guard savedIdea.impactAnalysisRequestToken == requestID,
                      savedIdea.originalText == requestedText,
                      savedIdea.scope == requestedScope,
                      savedIdea.targetStageIndex == requestedStageIndex,
                      project.updatedAt == projectRevision else {
                    if savedIdea.impactAnalysisRequestToken == requestID {
                        savedIdea.status = .proposed
                        savedIdea.updatedAt = .now
                        try ProjectPersistenceStore.savePendingChanges(in: modelContext)
                        errorMessage = "分析期间项目或创意已经更新；旧分析结果已丢弃。"
                    }
                    return
                }

                impact = result
                savedIdea.protectedCore = result.protectedCore
                savedIdea.impactSummary = result.summary
                savedIdea.affectedAreas = result.affectedAreas
                savedIdea.preservedElements = result.preservedElements
                savedIdea.risks = result.risks
                savedIdea.proposedActions = result.proposedActions
                savedIdea.status = .proposed
                savedIdea.updatedAt = .now
                try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            } catch {
                guard savedIdea.impactAnalysisRequestToken == requestID else { return }
                savedIdea.status = .proposed
                savedIdea.updatedAt = .now
                errorMessage = error.localizedDescription
                do {
                    try ProjectPersistenceStore.savePendingChanges(in: modelContext)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func applyIdea() {
        guard let savedIdea, let impact else { return }
        do {
            try ProjectPersistenceStore.transaction(in: modelContext) {
                StoryCompiler.insertSnapshot(
                    project: project,
                    title: "应用创意前",
                    reason: savedIdea.originalText,
                    in: modelContext
                )
            savedIdea.executionIdeaID = project.addCreativeIdea(
                text: savedIdea.originalText,
                scope: savedIdea.scope,
                stageIndex: savedIdea.targetStageIndex
            )
            savedIdea.status = .active
            savedIdea.appliedAt = .now
            savedIdea.updatedAt = .now

            let changeSet = StoryChangeSet(
                title: "纳入作者创意",
                summary: impact.summary,
                affectedAreas: impact.affectedAreas,
                preservedElements: impact.preservedElements,
                authorIdeaID: savedIdea.id,
                status: .applied
            )
            changeSet.appliedAt = .now
            changeSet.project = project
            modelContext.insert(changeSet)
                StoryCompiler.updateFindings(project: project, in: modelContext)
            }
            onSaved?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func keepForLater() {
        savedIdea?.status = .proposed
        savedIdea?.updatedAt = .now
        do {
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            onSaved?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

struct CreativeIdeaListView: View {
    @Bindable var project: StoryProject
    let limit: Int
    let compact: Bool
    let onCapture: (() -> Void)?

    @State private var showingAllIdeas = false

    private var allIdeas: [CreativeIdea] {
        project.creativeIdeas.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var visibleIdeas: [CreativeIdea] {
        showingAllIdeas ? allIdeas : Array(allIdeas.prefix(limit))
    }

    private var hiddenIdeaCount: Int {
        max(allIdeas.count - limit, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("创意脉冲", systemImage: "lightbulb.max.fill")
                    .font(.headline)
                    .foregroundStyle(StudioTheme.warm)
                Spacer()
                if let onCapture {
                    Button("注入", systemImage: "plus") {
                        onCapture()
                    }
                    .buttonStyle(.borderless)
                }
            }

            if allIdeas.isEmpty {
                if let onCapture {
                    Button(action: onCapture) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(StudioTheme.warm)
                            Text("灵感出现时，随手放进来")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("尚无已纳入的创意")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Label(
                    "AI 生成时只优先读取当前范围内最近 10 条已启用创意；其余创意仍会保留。",
                    systemImage: "brain.head.profile"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)

                ForEach(visibleIdeas) { idea in
                    ideaRow(idea)
                }

                if hiddenIdeaCount > 0 || showingAllIdeas {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingAllIdeas.toggle()
                        }
                    } label: {
                        Label(
                            showingAllIdeas
                                ? "收起创意列表"
                                : "查看并管理全部创意（另有 \(hiddenIdeaCount) 条）",
                            systemImage: showingAllIdeas ? "chevron.up" : "list.bullet"
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func ideaRow(_ idea: CreativeIdea) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Button {
                project.setCreativeIdeaActive(idea.id, active: !idea.isActive)
            } label: {
                Image(systemName: idea.isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(
                        idea.isActive
                            ? AnyShapeStyle(StudioTheme.mint)
                            : AnyShapeStyle(.tertiary)
                    )
            }
            .buttonStyle(.plain)
            .help(idea.isActive ? "暂停影响 AI" : "让它重新影响 AI")

            VStack(alignment: .leading, spacing: 4) {
                Text(idea.text)
                    .font(.callout)
                    .lineLimit(showingAllIdeas ? nil : (compact ? 2 : 4))
                    .foregroundStyle(idea.isActive ? .primary : .secondary)
                HStack(spacing: 6) {
                    Label(idea.scope.rawValue, systemImage: idea.scope.systemImage)
                    Text("·")
                    Text(idea.updatedAt, format: .relative(presentation: .named))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            Menu {
                Button(idea.isActive ? "暂停影响 AI" : "启用并影响 AI") {
                    project.setCreativeIdeaActive(idea.id, active: !idea.isActive)
                }
                Button("移除", systemImage: "trash", role: .destructive) {
                    project.removeCreativeIdea(idea.id)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.vertical, 4)
    }
}

struct ProjectContextInspectorView: View {
    @Bindable var project: StoryProject
    let onNavigate: (WorkspaceSection) -> Void
    let onCaptureIdea: () -> Void

    private var templateStageCount: Int {
        project.isStructureLocked ? project.structureTemplate.stages.count : 0
    }

    private var storyProgress: Double {
        guard templateStageCount > 0 else { return project.completionFraction }
        return Double(project.resolvedDecisionCount) / Double(templateStageCount)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        EyebrowLabel(text: "STORY AT A GLANCE", color: StudioTheme.mint)
                        Text("故事全景")
                            .font(.system(.title2, design: .serif, weight: .semibold))
                    }
                    Spacer()
                    ProgressRing(value: storyProgress, lineWidth: 5, diameter: 48)
                }

                Button {
                    onNavigate(.overview)
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(project.logline.isBlank ? "一句话故事尚未确定" : project.logline)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(4)
                        Label("打开完整驾驶舱", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.caption)
                            .foregroundStyle(StudioTheme.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                inspectorSection("当前生长", icon: "point.3.connected.trianglepath.dotted") {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text(project.workflowLabel)
                                .font(.callout.weight(.semibold))
                            Spacer()
                            if templateStageCount > 0 {
                                Text("\(project.resolvedDecisionCount)/\(templateStageCount)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if templateStageCount > 0 {
                            ProgressView(
                                value: Double(project.resolvedDecisionCount),
                                total: Double(templateStageCount)
                            )
                            .tint(StudioTheme.mint)
                        }
                    }
                }

                inspectorSection("故事罗盘", icon: "safari") {
                    snapshotRow(
                        "主题",
                        project.themeText.firstUsefulLine(or: project.themeBibleText),
                        icon: "scope",
                        tint: StudioTheme.warm
                    )
                    snapshotRow(
                        "核心冲突",
                        project.coreConflictText.firstUsefulLine(or: project.dramaticPromise),
                        icon: "arrow.left.arrow.right",
                        tint: StudioTheme.accent
                    )
                    snapshotRow(
                        "世界规则",
                        project.worldText.firstUsefulLine(or: project.worldBibleText),
                        icon: "globe.asia.australia",
                        tint: StudioTheme.sky
                    )
                }

                inspectorSection("人物与关系", icon: "person.2.fill") {
                    if project.characters.isEmpty {
                        Text("人物会在结构选择中自动生长，也可以由你先创建。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(project.characters.sorted { $0.roleSort < $1.roleSort }.prefix(6)) { character in
                            HStack(spacing: 9) {
                                Text(character.name.prefix(1))
                                    .font(.caption.weight(.bold))
                                    .frame(width: 26, height: 26)
                                    .background(StudioTheme.sky.opacity(0.11), in: Circle())
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(character.name)
                                        .font(.callout.weight(.semibold))
                                    Text(character.role.rawValue)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        Text("\(project.characters.count) 人物 · \(project.characterRelationships.count) 条关系")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Divider()

                CreativeIdeaListView(
                    project: project,
                    limit: 5,
                    compact: true,
                    onCapture: onCaptureIdea
                )
            }
            .padding(18)
        }
        .background(.ultraThinMaterial)
    }

    private func inspectorSection<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func snapshotRow(
        _ title: String,
        _ text: String,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(text.isBlank ? "尚待确认" : text)
                    .font(.caption)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
    }
}

private extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func firstUsefulLine(or fallback: String) -> String {
        let primary = split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("【") }
        if let primary { return primary }
        return fallback
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("【") }
            ?? ""
    }
}

private extension StoryCharacter {
    var roleSort: Int {
        switch role {
        case .protagonist: 0
        case .antagonist: 1
        case .loveInterest: 2
        case .ally: 3
        case .mentor: 4
        case .mirror: 5
        case .supporting: 6
        }
    }
}
