import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private enum CompilerWorkspaceMode: String, CaseIterable, Identifiable {
    case proposition = "命题台"
    case transitions = "转移卡"
    case graph = "场景图"
    case screenplay = "剧本文本"
    case comparison = "分支比较"
    case timeline = "时间线"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .proposition: "function"
        case .transitions: "rectangle.stack.fill"
        case .graph: "point.3.connected.trianglepath.dotted"
        case .screenplay: "text.book.closed.fill"
        case .comparison: "square.split.2x1.fill"
        case .timeline: "timeline.selection"
        }
    }
}

private enum NarrativeNavigatorProjection: String, CaseIterable, Identifiable {
    case propositions = "作者命题"
    case characters = "人物"
    case relationships = "关系"
    case scenes = "场景"
    case transitions = "状态转移"
    case causal = "因果图"
    case knowledge = "知识矩阵"
    case motifs = "伏笔与回收"
    case obligations = "未解决义务"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .propositions: "lock.shield.fill"
        case .characters: "person.2.fill"
        case .relationships: "point.3.connected.trianglepath.dotted"
        case .scenes: "rectangle.stack.fill"
        case .transitions: "arrow.trianglehead.2.clockwise.rotate.90"
        case .causal: "arrow.triangle.branch"
        case .knowledge: "tablecells.fill"
        case .motifs: "eye.trianglebadge.exclamationmark.fill"
        case .obligations: "checklist.unchecked"
        }
    }
}

private enum CompilerAuditScope: String, CaseIterable, Identifiable {
    case all = "全部"
    case errors = "错误"
    case decisions = "待决定"

    var id: String { rawValue }
}

struct NarrativeCompilerWorkbenchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AISettingsStore.self) private var aiSettings
    @Bindable var project: StoryProject
    let onNavigate: (WorkspaceSection) -> Void

    @State private var mode: CompilerWorkspaceMode = .proposition
    @State private var projection: NarrativeNavigatorProjection = .propositions
    @State private var propositionKind: CreativePropositionKind = .emotion
    @State private var propositionText = ""
    @State private var isAddingProposition = false
    @State private var selectedCharacterIDs: Set<UUID> = []
    @State private var lockedProposition: Proposition?
    @State private var informationQuestion: InformationGainQuestion?
    @State private var questionAnswer = ""
    @State private var candidates: [CompilerCandidate] = []
    @State private var selectedCandidateID: UUID?
    @State private var selectedTransitionID: UUID?
    @State private var validationReport: ValidationReport?
    @State private var auditScope: CompilerAuditScope = .all
    @State private var isCompiling = false
    @State private var compilationTask: Task<Void, Never>?
    @State private var compilationRequestID: UUID?
    @State private var compilerMessage = ""
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var auditHeight: CGFloat = 170

    private var workspace: CompilerWorkspaceDocument {
        project.nsirWorkspace
    }

    private var selectedCandidate: CompilerCandidate? {
        guard let selectedCandidateID else { return candidates.first }
        return candidates.first { $0.id == selectedCandidateID }
    }

    private var selectedTransition: DramaticTransition? {
        let all = selectedCandidate?.transitions ?? workspace.transitions
        guard let selectedTransitionID else { return all.first }
        return all.first { $0.id == selectedTransitionID }
    }

    private var packageDocument: NSIRProjectPackageDocument {
        NSIRProjectPackageDocument(
            projectTitle: project.title,
            workspace: workspace,
            screenplayText: project.screenplayText
        )
    }

    var body: some View {
        ZStack {
            StudioCanvas()
            CompilerAnimatedBackdrop(active: isCompiling)

            VStack(spacing: 12) {
                compilerTopBar

                HStack(alignment: .top, spacing: 12) {
                    navigator
                        .frame(width: 230)
                        .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 32)

                    VStack(spacing: 10) {
                        modePicker
                            .animatedStoryBubble(tint: StudioTheme.accent, cornerRadius: 24)
                        workspaceContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .animatedStoryBubble(tint: StudioTheme.accent, cornerRadius: 38)
                        auditConsole
                            .frame(minHeight: 120, idealHeight: auditHeight, maxHeight: 270)
                            .animatedStoryBubble(tint: StudioTheme.warm, cornerRadius: 28)
                    }
                    .frame(minWidth: 520)

                    proofInspector
                        .frame(width: 318)
                        .animatedStoryBubble(tint: StudioTheme.sky, cornerRadius: 32)
                }
            }
            .padding(14)
        }
        .navigationSplitViewColumnWidth(min: 820, ideal: 1_140)
        .task(id: project.id) {
            loadWorkspace()
        }
        .onDisappear {
            compilationTask?.cancel()
            compilationTask = nil
            compilationRequestID = nil
        }
        .onChange(of: selectedCandidateID) { _, _ in
            selectedTransitionID = selectedCandidate?.transitions.first?.id
            refreshValidation()
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: packageDocument,
            contentType: .storyProject,
            defaultFilename: safePackageName
        ) { result in
            if case .failure(let error) = result { present(error) }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.storyProject],
            allowsMultipleSelection: false,
            onCompletion: importPackage
        )
        .alert("叙事编译器", isPresented: $showingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var compilerTopBar: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [StudioTheme.accent, StudioTheme.mint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "function")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)
            .shadow(color: StudioTheme.accent.opacity(0.24), radius: 10, y: 5)

            VStack(alignment: .leading, spacing: 2) {
                Text("叙事编译台")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Text("实验结晶 → 作者决定 → 结构候选 → 可追溯变更")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label("DeepSeek 主推理", systemImage: aiSettings.hasAPIKey ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(aiSettings.hasAPIKey ? StudioTheme.mint : StudioTheme.warm)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.045), in: Capsule())

            HStack(spacing: 4) {
                Text("r\(workspace.revision)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .contentTransition(.numericText())
                Text("·")
                Text("\(workspace.transitions.count) 转移")
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(.secondary)

            Menu {
                Button("导出 .storyproject", systemImage: "square.and.arrow.up") {
                    showingExporter = true
                }
                Button("导入 NSIR 包…", systemImage: "square.and.arrow.down") {
                    showingImporter = true
                }
                Divider()
                Button("打开 Final Draft 正文", systemImage: "text.book.closed") {
                    onNavigate(.screenplay)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .help("项目包与编辑器")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .animatedStoryBubble(tint: StudioTheme.accent, cornerRadius: 30)
    }

    private var modePicker: some View {
        HStack(spacing: 6) {
            ForEach(CompilerWorkspaceMode.allCases) { item in
                Button {
                    withAnimation(.snappy(duration: 0.28)) { mode = item }
                } label: {
                    Label(item.rawValue, systemImage: item.symbol)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            mode == item ? StudioTheme.accent.opacity(0.14) : Color.clear,
                            in: Capsule()
                        )
                        .foregroundStyle(mode == item ? StudioTheme.accent : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            if isCompiling {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("DeepSeek 正在生成结构候选")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var workspaceContent: some View {
        switch mode {
        case .proposition: propositionDesk
        case .transitions: transitionCards
        case .graph: transitionGraph
        case .screenplay:
            ScreenplayStudioView(project: project, onNavigate: onNavigate)
        case .comparison: comparisonWorkspace
        case .timeline: projectionTimelineWorkspace
        }
    }

    @ViewBuilder
    private var projectionTimelineWorkspace: some View {
        switch projection {
        case .knowledge: knowledgeMatrixWorkspace
        case .relationships: relationshipVectorWorkspace
        case .obligations: obligationWorkspace
        case .motifs: motifWorkspace
        default: timelineWorkspace
        }
    }

    private var navigator: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    EyebrowLabel(text: "叙事生产")
                    Text("叙事导航器")
                        .font(.headline)
                }
                Spacer()
            }
            .padding(14)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(NarrativeNavigatorProjection.allCases) { item in
                        Button {
                            withAnimation(.snappy(duration: 0.24)) {
                                projection = item
                                routeProjection(item)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.symbol)
                                    .frame(width: 22)
                                Text(item.rawValue)
                                Spacer()
                                Text(projectionCount(item), format: .number)
                                    .font(.caption2.monospacedDigit().weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .font(.callout.weight(projection == item ? .semibold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                projection == item ? StudioTheme.accent.opacity(0.12) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                            .foregroundStyle(projection == item ? StudioTheme.accent : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }

                    Divider().padding(.vertical, 10)
                    navigatorDetail
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private var navigatorDetail: some View {
        switch projection {
        case .propositions:
            ForEach(workspace.propositions.reversed()) { proposition in
                compactNavigatorCard(
                    title: proposition.kind.rawValue,
                    subtitle: proposition.originalText,
                    tint: proposition.status == .locked ? StudioTheme.mint : StudioTheme.warm
                )
            }
        case .characters:
            ForEach(project.characters) { character in
                compactNavigatorCard(title: character.name, subtitle: character.externalGoal, tint: StudioTheme.sky)
            }
        case .relationships:
            ForEach(workspace.state.relationships) { relationship in
                compactNavigatorCard(
                    title: "信任 \(relationship.trust.formatted(.number.precision(.fractionLength(1))))",
                    subtitle: "亲密 \(relationship.intimacy.formatted(.number.precision(.fractionLength(1)))) · 权力 \(relationship.power.formatted(.number.precision(.fractionLength(1))))",
                    tint: StudioTheme.warm
                )
            }
        case .scenes:
            ForEach(workspace.transitions) { transition in
                compactNavigatorCard(
                    title: transition.title,
                    subtitle: transition.intention,
                    tint: StudioTheme.accent
                )
            }
        case .transitions, .causal:
            ForEach(workspace.transitions) { transition in
                Button {
                    selectedTransitionID = transition.id
                    mode = projection == .causal ? .graph : .transitions
                } label: {
                    compactNavigatorCard(title: transition.title, subtitle: transition.effects.map { "\($0.dimension.code): \($0.afterValue)" }.joined(separator: " · "), tint: StudioTheme.mint)
                }
                .buttonStyle(.plain)
            }
        case .knowledge:
            ForEach(workspace.state.beliefs) { belief in
                compactNavigatorCard(title: belief.subject, subtitle: belief.value, tint: StudioTheme.sky)
            }
        case .motifs:
            ForEach(workspace.state.motifStates.keys.sorted(), id: \.self) { key in
                compactNavigatorCard(title: key, subtitle: workspace.state.motifStates[key] ?? "", tint: StudioTheme.warm)
            }
        case .obligations:
            ForEach(workspace.obligations.filter { $0.status == .open }) { obligation in
                compactNavigatorCard(title: obligation.title, subtitle: obligation.detail, tint: StudioTheme.warm)
            }
        }
    }

    private func compactNavigatorCard(title: String, subtitle: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(title).font(.caption.weight(.semibold)).lineLimit(1)
            }
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }

    private var propositionDesk: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    EyebrowLabel(text: "实验接力命题", color: StudioTheme.warm)
                    Text("从已经确认的实验结果继续")
                        .font(.system(.title, design: .serif, weight: .semibold))
                    Text("实验室里的不可两全、人物洞察和作者选择已经成为生产底稿；这里继续锁定下一条创作决定。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let lockedProposition, !isAddingProposition {
                    activePropositionCard(lockedProposition)
                }

                if lockedProposition == nil || isAddingProposition {
                    propositionKindGrid

                    StudioCard(padding: 18) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label(propositionKind.rawValue, systemImage: propositionKind.symbol)
                                    .font(.headline)
                                    .foregroundStyle(StudioTheme.accent)
                                Spacer()
                                Text("作者锁定决定")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(StudioTheme.mint)
                            }
                            TextEditor(text: $propositionText)
                                .font(.system(.body, design: .serif))
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 92)
                                .padding(10)
                                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(alignment: .topLeading) {
                                    if propositionText.isEmpty {
                                        Text(propositionKind.prompt)
                                            .font(.callout)
                                            .foregroundStyle(.tertiary)
                                            .padding(15)
                                            .allowsHitTesting(false)
                                    }
                                }

                            if !project.characters.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("涉及人物（可多选）").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    FlowLayout(spacing: 7) {
                                        ForEach(project.characters) { character in
                                            Button {
                                                if selectedCharacterIDs.contains(character.id) {
                                                    selectedCharacterIDs.remove(character.id)
                                                } else {
                                                    selectedCharacterIDs.insert(character.id)
                                                }
                                            } label: {
                                                Label(character.name, systemImage: selectedCharacterIDs.contains(character.id) ? "checkmark.circle.fill" : "circle")
                                                    .font(.caption.weight(.semibold))
                                                    .padding(.horizontal, 9)
                                                    .padding(.vertical, 6)
                                                    .background(Color.primary.opacity(0.045), in: Capsule())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }

                            HStack {
                                Text("确认后写入权威叙事模型；AI 无权修改这条决定。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if lockedProposition != nil {
                                    Button("取消新增") {
                                        isAddingProposition = false
                                        propositionText = ""
                                    }
                                    .buttonStyle(.bordered)
                                }
                                Button("确认并锁定", systemImage: "lock.fill", action: lockCurrentProposition)
                                    .buttonStyle(.borderedProminent)
                                    .keyboardShortcut(.defaultAction)
                                    .disabled(propositionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }
                }

                if let lockedProposition, let informationQuestion {
                    informationGainCard(proposition: lockedProposition, question: informationQuestion)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if !candidates.isEmpty {
                    candidateStrip
                        .transition(.scale(scale: 0.98).combined(with: .opacity))
                }

                if !compilerMessage.isEmpty {
                    Label(compilerMessage, systemImage: "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(22)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var propositionKindGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 9)], spacing: 9) {
            ForEach(CreativePropositionKind.allCases) { kind in
                Button {
                    withAnimation(.snappy(duration: 0.24)) {
                        propositionKind = kind
                        lockedProposition = nil
                        informationQuestion = nil
                        candidates = []
                        selectedCandidateID = nil
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: kind.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(propositionKind == kind ? Color.white : StudioTheme.accent)
                            .frame(width: 26, height: 26)
                            .background(propositionKind == kind ? Color.white.opacity(0.18) : StudioTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        Text(kind.rawValue)
                            .font(.caption.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(propositionKind == kind ? StudioTheme.accent : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(propositionKind == kind ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func activePropositionCard(_ proposition: Proposition) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("实验室已经锁定", systemImage: "lock.shield.fill")
                    .font(.headline)
                    .foregroundStyle(StudioTheme.mint)
                Spacer()
                Text(proposition.kind.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(StudioTheme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(StudioTheme.accent.opacity(0.1), in: Capsule())
            }

            Text(proposition.originalText)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)

            if !proposition.targetCharacterIDs.isEmpty {
                FlowLayout(spacing: 7) {
                    ForEach(proposition.targetCharacterIDs, id: \.self) { id in
                        Label(characterName(id), systemImage: "person.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.045), in: Capsule())
                    }
                }
            }

            HStack {
                Text("这条决定已经进入生产模型，下面直接回答最高信息增益问题即可继续推演。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("新增一条作者决定", systemImage: "plus.circle.fill") {
                    withAnimation(.snappy(duration: 0.26)) {
                        propositionText = ""
                        isAddingProposition = true
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 38, isSelected: true)
    }

    private func informationGainCard(
        proposition: Proposition,
        question: InformationGainQuestion
    ) -> some View {
        StudioCard(padding: 18) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label("下一条最高信息增益问题", systemImage: "arrow.down.right.and.arrow.up.left")
                        .font(.headline)
                    Spacer()
                    Text(question.expectedInformationGain, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(StudioTheme.warm)
                }
                Text(question.prompt)
                    .font(.system(.title3, design: .serif, weight: .semibold))
                Text(question.rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 7) {
                    ForEach(question.options, id: \.self) { option in
                        Button(option) {
                            withAnimation(.snappy(duration: 0.2)) { questionAnswer = option }
                        }
                        .buttonStyle(.bordered)
                        .tint(questionAnswer == option ? StudioTheme.accent : .secondary)
                    }
                }
                TextField("也可以输入自己的回答", text: $questionAnswer)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Label("只发送当前命题、回答、相关人物与规则卡", systemImage: "shield.lefthalf.filled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(
                        aiSettings.hasAPIKey ? "让 DeepSeek 生成 3 条路线" : "使用本地规划器生成 3 条路线",
                        systemImage: "wand.and.stars",
                        action: compileCandidates
                    )
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isCompiling || questionAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var candidateStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pareto 候选")
                        .font(.headline)
                    Text("没有总分；每条路线保留不同交换关系。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("展开分支比较", systemImage: "square.split.2x1") { mode = .comparison }
                    .buttonStyle(.bordered)
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(candidates) { candidate in
                        candidateCard(candidate)
                            .frame(width: 285)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func candidateCard(_ candidate: CompilerCandidate) -> some View {
        let selected = selectedCandidate?.id == candidate.id
        return Button {
            withAnimation(.snappy(duration: 0.24)) {
                selectedCandidateID = candidate.id
                selectedTransitionID = candidate.transitions.first?.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(candidate.title).font(.headline)
                        Text(candidate.thesis).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? StudioTheme.accent : Color.secondary.opacity(0.55))
                }
                Divider()
                ForEach(candidate.objectives.dimensions.prefix(4), id: \.0) { label, value in
                    HStack(spacing: 7) {
                        Text(label).font(.caption2).frame(width: 48, alignment: .leading)
                        ProgressView(value: value).tint(objectiveTint(label))
                        Text(value, format: .percent.precision(.fractionLength(0)))
                            .font(.caption2.monospacedDigit())
                            .frame(width: 30, alignment: .trailing)
                    }
                }
                if let tradeoff = candidate.trace.tradeoffs.first {
                    Label(tradeoff.costs, systemImage: "scalemass.fill")
                        .font(.caption2)
                        .foregroundStyle(StudioTheme.warm)
                        .lineLimit(2)
                }
            }
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(selected ? StudioTheme.accent : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var transitionCards: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                workspaceHeader("状态转移", subtitle: "最小单位是不可再分的情境更新，不是句子、镜头或固定节拍。")
                let transitions = selectedCandidate?.transitions ?? workspace.transitions
                if transitions.isEmpty {
                    emptyWorkspace("尚无转移", "回到命题台锁定命题并生成候选。", "function")
                } else {
                    ForEach(Array(transitions.enumerated()), id: \.element.id) { index, transition in
                        transitionCard(transition, ordinal: index + 1)
                    }
                }
            }
            .padding(20)
        }
    }

    private func transitionCard(_ transition: DramaticTransition, ordinal: Int) -> some View {
        Button {
            selectedTransitionID = transition.id
        } label: {
            StudioCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        Text("τ\(ordinal)")
                            .font(.caption.monospaced().weight(.bold))
                            .foregroundStyle(StudioTheme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(StudioTheme.accent.opacity(0.1), in: Capsule())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(transition.title).font(.headline)
                            Text("\(transition.actorName.isEmpty ? "外部事件" : transition.actorName) · \(transition.tactic.verb) · \(transition.intention)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(transition.confidence.value, format: .percent.precision(.fractionLength(0)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ForEach(transition.effects) { effect in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: effect.dimension.symbol)
                                .foregroundStyle(StudioTheme.mint)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(effect.dimension.rawValue) · \(effect.subject)")
                                    .font(.caption.weight(.semibold))
                                HStack(spacing: 6) {
                                    Text(effect.beforeValue)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(StudioTheme.accent)
                                    Text(effect.afterValue)
                                        .foregroundStyle(.primary)
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(selectedTransitionID == transition.id ? StudioTheme.accent : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }

    private var transitionGraph: some View {
        VStack(alignment: .leading, spacing: 14) {
            workspaceHeader("部分序因果图", subtitle: "只保存必要的先后关系；尚未决定的转移不会被强行分配场次。")
                .padding(.horizontal, 20)
                .padding(.top, 18)
            CompilerTransitionGraph(
                transitions: selectedCandidate?.transitions ?? workspace.transitions,
                selectedID: $selectedTransitionID
            )
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
    }

    private var comparisonWorkspace: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 14) {
                workspaceHeader("分支比较", subtitle: "比较交换关系，不把艺术判断压成一个数字。")
                if candidates.isEmpty {
                    emptyWorkspace("还没有候选", "先在命题台生成三条结构性路线。", "square.split.2x1")
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(candidates) { candidate in
                            branchColumn(candidate).frame(width: 310)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func branchColumn(_ candidate: CompilerCandidate) -> some View {
        StudioCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text(candidate.title).font(.title3.weight(.semibold))
                Text(candidate.thesis).font(.callout).foregroundStyle(.secondary)
                Divider()
                ForEach(candidate.transitions) { transition in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(transition.title).font(.caption.weight(.bold))
                        Text(transition.effects.map { "\($0.dimension.code) \($0.beforeValue) → \($0.afterValue)" }.joined(separator: "\n"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Divider()
                ForEach(candidate.objectives.dimensions, id: \.0) { label, value in
                    HStack { Text(label); Spacer(); Text(value, format: .percent.precision(.fractionLength(0))) }
                        .font(.caption.monospacedDigit())
                }
                Button("选择此分支", systemImage: selectedCandidateID == candidate.id ? "checkmark.circle.fill" : "circle") {
                    selectedCandidateID = candidate.id
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var timelineWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                workspaceHeader("叙事时间线", subtitle: "明确顺序来自因果前置；不是所有事件都需要绝对排序。")
                let transitions = workspace.transitions
                if transitions.isEmpty {
                    emptyWorkspace("时间线为空", "提交一条候选路线后，转移会进入权威时间线。", "timeline.selection")
                } else {
                    ForEach(Array(transitions.enumerated()), id: \.element.id) { index, transition in
                        HStack(alignment: .top, spacing: 14) {
                            VStack(spacing: 0) {
                                Circle().fill(StudioTheme.accent).frame(width: 12, height: 12)
                                if index < transitions.count - 1 {
                                    Rectangle().fill(StudioTheme.accent.opacity(0.24)).frame(width: 2, height: 64)
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(transition.title).font(.headline)
                                Text("前置：\(transition.partialOrderPredecessorIDs.count) · 结果：\(transition.effects.map(\.afterValue).joined(separator: "；"))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
            .padding(22)
        }
    }

    private var knowledgeMatrixWorkspace: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 16) {
                workspaceHeader("知识矩阵", subtitle: "事实、人物信念与观众认知分别保存；未知不会被静默补全。")
                let characters = project.characters
                let subjects = Array(Set(workspace.state.beliefs.map(\.subject))).sorted()
                if characters.isEmpty || subjects.isEmpty {
                    emptyWorkspace("矩阵尚为空", "提交涉及知识变化的转移，或从情境透镜导入正文语义。", "tablecells")
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                        GridRow {
                            Text("命题 / 人物").font(.caption.weight(.bold)).frame(width: 150, alignment: .leading)
                            ForEach(characters) { character in
                                Text(character.name).font(.caption.weight(.bold)).frame(width: 150, alignment: .leading)
                            }
                            Text("观众").font(.caption.weight(.bold)).frame(width: 150, alignment: .leading)
                        }
                        Divider().gridCellUnsizedAxes(.horizontal)
                        ForEach(subjects, id: \.self) { subject in
                            GridRow {
                                Text(subject).font(.caption.weight(.semibold)).frame(width: 150, alignment: .leading)
                                ForEach(characters) { character in
                                    let belief = workspace.state.beliefs.last {
                                        $0.subject == subject && $0.holderID == character.id
                                    }
                                    knowledgeCell(belief?.value ?? "未知", status: belief?.truthStatus ?? .unknown)
                                }
                                knowledgeCell(
                                    workspace.state.audience.knows.contains(where: { $0.contains(subject) }) ? "已知" : "未知",
                                    status: workspace.state.audience.knows.contains(where: { $0.contains(subject) }) ? .fact : .unknown
                                )
                            }
                        }
                    }
                    .padding(14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(20)
        }
    }

    private func knowledgeCell(_ text: String, status: TruthStatus) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(status.rawValue).font(.caption2.weight(.bold)).foregroundStyle(status == .unknown ? Color.secondary : StudioTheme.sky)
            Text(text).font(.caption2).lineLimit(2)
        }
        .padding(8)
        .frame(width: 150, alignment: .leading)
        .frame(minHeight: 48, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }

    private var relationshipVectorWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                workspaceHeader("多维关系向量", subtitle: "亲密上升可以与信任下降同时成立；不再压缩成一个“好感度”。")
                if workspace.state.relationships.isEmpty {
                    emptyWorkspace("尚无关系向量", "原项目关系会在首次打开编译台时迁移；也可从关系命题创建。", "person.2")
                } else {
                    ForEach(workspace.state.relationships) { relationship in
                        StudioCard(padding: 15) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(characterName(relationship.fromID)).font(.headline)
                                    Image(systemName: "arrow.left.arrow.right").foregroundStyle(StudioTheme.accent)
                                    Text(characterName(relationship.toID)).font(.headline)
                                }
                                relationshipMetricGrid(relationship)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func relationshipMetricGrid(_ value: RelationshipState) -> some View {
        let metrics = [
            ("信任", value.trust), ("亲密", value.intimacy),
            ("权力", value.power), ("依赖", value.dependency),
            ("亏欠", value.obligation), ("怨恨", value.resentment),
            ("吸引", value.attraction), ("公开状态", value.publicStatus)
        ]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(metrics, id: \.0) { label, metric in
                HStack(spacing: 8) {
                    Text(label).font(.caption).frame(width: 52, alignment: .leading)
                    ProgressView(value: (metric + 1) / 2)
                        .tint(metric >= 0 ? StudioTheme.mint : StudioTheme.warm)
                    Text(metric, format: .number.precision(.fractionLength(2)))
                        .font(.caption2.monospacedDigit()).frame(width: 34, alignment: .trailing)
                }
            }
        }
    }

    private var obligationWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                workspaceHeader("未解决义务", subtitle: "伏笔、承诺、秘密与选择代价都会留下可追踪的回收责任。")
                if workspace.obligations.isEmpty {
                    emptyWorkspace("没有叙事义务", "接受候选后，新增代价与回收条件会自动进入这里。", "checklist.unchecked")
                } else {
                    ForEach(workspace.obligations) { obligation in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: obligation.status == .open ? "circle.dashed" : "checkmark.circle.fill")
                                .foregroundStyle(obligation.status == .open ? StudioTheme.warm : StudioTheme.mint)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(obligation.title).font(.headline)
                                    Text(obligation.ruleClass.shortLabel).font(.caption2.monospaced().weight(.bold)).foregroundStyle(ruleTint(obligation.ruleClass))
                                }
                                Text(obligation.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(obligation.status.rawValue).font(.caption.weight(.semibold))
                        }
                        .padding(14)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .padding(20)
        }
    }

    private var motifWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                workspaceHeader("伏笔、悬念与意象", subtitle: "每个设置都保存当前解释、替代解释和未来回收义务。")
                if workspace.state.motifStates.isEmpty {
                    emptyWorkspace("尚无伏笔状态", "从“性格伏笔”或“画面或动作”入口建立第一条线索。", "eye.trianglebadge.exclamationmark")
                } else {
                    ForEach(workspace.state.motifStates.keys.sorted(), id: \.self) { key in
                        StudioCard(padding: 14) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(key).font(.headline)
                                Text(workspace.state.motifStates[key] ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private var proofInspector: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    EyebrowLabel(text: "PROOF")
                    Text("证明与约束").font(.headline)
                }
                Spacer()
                if let selectedCandidate {
                    Text(selectedCandidate.trace.ruleClass.shortLabel)
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(StudioTheme.accent)
                }
            }
            .padding(14)
            Divider().opacity(0.5)

            ScrollView {
                if let candidate = selectedCandidate {
                    VStack(alignment: .leading, spacing: 14) {
                        inspectorSection("结论", icon: "checkmark.seal.fill") {
                            Text(candidate.trace.conclusion)
                        }
                        inspectorSection("规则等级", icon: "list.bullet.rectangle.portrait.fill") {
                            ForEach(candidate.trace.appliedRules) { rule in
                                HStack(alignment: .top, spacing: 7) {
                                    Text(rule.ruleClass.shortLabel)
                                        .font(.caption2.monospaced().weight(.bold))
                                        .foregroundStyle(ruleTint(rule.ruleClass))
                                        .frame(width: 22)
                                    Text(rule.title).font(.caption)
                                }
                            }
                        }
                        inspectorSection("已接受前提", icon: "lock.fill") {
                            ForEach(candidate.trace.acceptedPremises) { premise in
                                Label(premise.statement, systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        inspectorSection("隐含假设", icon: "questionmark.bubble.fill") {
                            ForEach(candidate.trace.assumptions) { assumption in
                                Text(assumption.statement).font(.caption).foregroundStyle(StudioTheme.warm)
                            }
                        }
                        inspectorSection("状态差异", icon: "arrow.left.arrow.right") {
                            ForEach(candidate.trace.resultingStateDiff.mutations.prefix(8)) { mutation in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(mutation.dimension.code) · \(mutation.subject)")
                                        .font(.caption2.weight(.bold))
                                    Text("\(mutation.beforeValue) → \(mutation.afterValue)")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        inspectorSection("代价与义务", icon: "scalemass.fill") {
                            ForEach(candidate.trace.tradeoffs) { tradeoff in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("获得：\(tradeoff.gains)").font(.caption)
                                    Text("代价：\(tradeoff.costs)").font(.caption).foregroundStyle(StudioTheme.warm)
                                }
                            }
                        }
                        inspectorSection("不确定性", icon: "waveform.path.ecg") {
                            Text(candidate.trace.uncertainty.confidence, format: .percent.precision(.fractionLength(0)))
                                .font(.title3.monospacedDigit().weight(.bold))
                            ForEach(candidate.trace.uncertainty.modelDependentClaims, id: \.self) {
                                Text($0).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        if let validationReport, !validationReport.valid {
                            inspectorSection("最小代价修复", icon: "wrench.adjustable.fill") {
                                ForEach(NarrativeValidationEngine.minimumRepairs(for: validationReport)) { repair in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(repair.title).font(.caption.weight(.semibold))
                                        Text(repair.difference).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(14)
                } else if let transition = selectedTransition {
                    VStack(alignment: .leading, spacing: 14) {
                        inspectorSection("当前转移", icon: "arrow.trianglehead.2.clockwise.rotate.90") {
                            Text(transition.title).font(.headline)
                            Text(transition.intention).font(.caption).foregroundStyle(.secondary)
                        }
                        inspectorSection("来源", icon: "link") {
                            Text(transition.provenance.source)
                            Text(transition.provenance.model).foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                } else {
                    ContentUnavailableView(
                        "选择一条建议",
                        systemImage: "sidebar.right",
                        description: Text("这里会显示规则等级、依据、假设、状态差异和代价。")
                    )
                }
            }

            if let candidate = selectedCandidate {
                Divider().opacity(0.5)
                VStack(spacing: 8) {
                    Button("暂存 Patch", systemImage: "tray.and.arrow.down.fill") {
                        stageCandidate(candidate)
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                    Button("验证并提交到 NSIR", systemImage: "checkmark.seal.fill") {
                        commitCandidate(candidate)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(validationReport?.valid == false)
                    .frame(maxWidth: .infinity)

                    Text("不会写入或覆盖剧本正文")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
            }
        }
    }

    private func inspectorSection<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(StudioTheme.accent)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(11)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private var auditConsole: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("审计台", systemImage: "exclamationmark.bubble.fill")
                    .font(.caption.weight(.bold))
                Text("\(filteredAuditIssues.count)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
                Picker("审计范围", selection: $auditScope) {
                    ForEach(CompilerAuditScope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
                Spacer()
                if let validationReport {
                    Label(
                        validationReport.valid ? "可提交" : "已阻止提交",
                        systemImage: validationReport.valid ? "checkmark.circle.fill" : "xmark.octagon.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(validationReport.valid ? StudioTheme.mint : .red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider().opacity(0.45)
            if filteredAuditIssues.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(StudioTheme.mint)
                    Text("当前没有符合筛选条件的问题。确定性检查仍可在 AI 完全不可用时运行。")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredAuditIssues) { issue in
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: issueSymbol(issue.severity))
                                    .foregroundStyle(issueTint(issue.severity))
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(issue.title).font(.caption.weight(.semibold))
                                        Text(issue.ruleClass.shortLabel)
                                            .font(.caption2.monospaced().weight(.bold))
                                            .foregroundStyle(ruleTint(issue.ruleClass))
                                    }
                                    Text(issue.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            Divider().padding(.leading, 39).opacity(0.35)
                        }
                    }
                }
            }
        }
        .background(.regularMaterial)
    }

    private var auditIssues: [NarrativeIssue] {
        var values = (validationReport?.issues ?? [])
            + NarrativeValidationEngine.audit(workspace)
        values += workspace.obligations.filter { $0.status == .open }.map { obligation in
            NarrativeIssue(
                id: obligation.id,
                kind: .unresolvedSetup,
                severity: .note,
                title: obligation.title,
                detail: obligation.detail,
                ruleClass: obligation.ruleClass,
                evidence: [],
                transitionID: obligation.createdByTransitionID
            )
        }
        values += project.narrativeProjections.filter {
            !$0.realizationGap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.map { projection in
            NarrativeIssue(
                id: projection.id,
                kind: .semanticDrift,
                severity: .decision,
                title: "语义漂移 · \(projection.title)",
                detail: projection.realizationGap,
                ruleClass: .l1,
                evidence: [],
                transitionID: nil
            )
        }
        return values
    }

    private var filteredAuditIssues: [NarrativeIssue] {
        switch auditScope {
        case .all: auditIssues
        case .errors: auditIssues.filter { $0.severity == .error || $0.severity == .warning }
        case .decisions: auditIssues.filter { $0.severity == .decision }
        }
    }

    private func workspaceHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(.title2, design: .serif, weight: .semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyWorkspace(_ title: String, _ detail: String, _ symbol: String) -> some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(detail))
            .frame(maxWidth: .infinity, minHeight: 280)
    }

    private func loadWorkspace() {
        let original: CompilerWorkspaceDocument
        do {
            original = try project.requireNSIRWorkspace()
        } catch {
            present(error)
            return
        }
        let bridged = NSIRLegacyBridge.bootstrap(project: project, document: original)
        if bridged.updatedAt != original.updatedAt {
            _ = persist(bridged)
        }
        if let active = bridged.propositions.reversed().first(where: { $0.status == .locked }) {
            lockedProposition = active
            propositionKind = active.kind
            informationQuestion = NarrativeCompilerEngine.nextQuestion(for: active)
            selectedCharacterIDs = Set(active.targetCharacterIDs)
            isAddingProposition = false
        }
        if selectedCharacterIDs.isEmpty, let first = project.characters.first {
            selectedCharacterIDs.insert(first.id)
        }
        compilerMessage = lockedProposition == nil
            ? "生产模型已加载；请锁定第一条作者决定。"
            : "实验室命题、人物与生产底稿已接入；可以直接继续结构推演。"
    }

    private func lockCurrentProposition() {
        var current = workspace
        let orderedIDs = project.characters
            .filter { selectedCharacterIDs.contains($0.id) }
            .map(\.id)
        let proposition = NarrativeCompilerEngine.formalize(
            kind: propositionKind,
            text: propositionText,
            characterIDs: orderedIDs,
            revision: current.revision + 1
        )
        current.propositions.append(proposition)
        current.revision += 1
        guard persist(current) else { return }
        withAnimation(.snappy(duration: 0.32)) {
            lockedProposition = proposition
            informationQuestion = NarrativeCompilerEngine.nextQuestion(for: proposition)
            propositionText = ""
            isAddingProposition = false
            questionAnswer = ""
            candidates = []
            selectedCandidateID = nil
            validationReport = nil
            compilerMessage = "作者命题已锁定为 L0；AI 只能在它的约束内提出候选。"
        }
    }

    private func compileCandidates() {
        guard let proposition = lockedProposition else { return }
        compilationTask?.cancel()

        let names = project.characters
            .filter { proposition.targetCharacterIDs.contains($0.id) }
            .map(\.name)
        let sourceDocument = workspace
        let answer = questionAnswer
        let projectContext = "\(project.projectSummary)\n\(project.storyBibleDigest)"
        let usesRemoteModel = aiSettings.hasAPIKey
        let requestID = UUID()

        compilationRequestID = requestID
        isCompiling = true
        compilerMessage = usesRemoteModel
            ? "正在构造最小 Context Slice 并调用 DeepSeek…"
            : "DeepSeek 未配置；正在运行确定性规划器。"

        compilationTask = Task { @MainActor in
            defer {
                if compilationRequestID == requestID {
                    isCompiling = false
                    compilationTask = nil
                }
            }

            let result: [CompilerCandidate]
            let completionMessage: String
            if usesRemoteModel {
                do {
                    result = try await NarrativeCompilerAI.compile(
                        proposition: proposition,
                        answer: answer,
                        characterNames: names,
                        projectContext: projectContext,
                        document: sourceDocument,
                        configuration: try aiSettings.configuration()
                    )
                    completionMessage = "DeepSeek 已返回结构化候选；确定性验证器已独立模拟。"
                } catch is CancellationError {
                    return
                } catch {
                    result = NarrativeCompilerEngine.localCandidates(
                        proposition: proposition,
                        answer: answer,
                        characterNames: names,
                        revision: sourceDocument.revision
                    )
                    completionMessage = "DeepSeek 调用失败，已安全回退确定性规划器：\(error.localizedDescription)"
                }
            } else {
                result = NarrativeCompilerEngine.localCandidates(
                    proposition: proposition,
                    answer: answer,
                    characterNames: names,
                    revision: sourceDocument.revision
                )
                completionMessage = "本地规划完成；所有逻辑验证不依赖 AI。"
            }

            guard !Task.isCancelled,
                  compilationRequestID == requestID else {
                return
            }
            guard project.nsirRevision == sourceDocument.revision else {
                compilerMessage = "生成期间权威叙事模型已更新；这批旧候选已丢弃，请重新生成。"
                return
            }

            compilerMessage = completionMessage
            withAnimation(.snappy(duration: 0.38)) {
                candidates = result
                selectedCandidateID = result.first?.id
                selectedTransitionID = result.first?.transitions.first?.id
                refreshValidation()
            }
        }
    }

    private func refreshValidation() {
        guard let candidate = selectedCandidate else {
            validationReport = nil
            return
        }
        validationReport = NarrativeValidationEngine.validate(
            patch: candidate.patch,
            against: workspace
        )
    }

    private func stageCandidate(_ candidate: CompilerCandidate) {
        let report = NarrativeValidationEngine.validate(patch: candidate.patch, against: workspace)
        validationReport = report
        var current = workspace
        current.stagedPatches.removeAll { $0.id == candidate.patch.id }
        current.stagedPatches.append(candidate.patch)
        current.validationHistory.append(report)
        guard persist(current) else { return }
        compilerMessage = report.valid
            ? "Patch 已暂存并通过模拟；仍需作者提交。"
            : "Patch 已暂存，但确定性错误阻止提交。"
    }

    private func commitCandidate(_ candidate: CompilerCandidate) {
        let report = NarrativeValidationEngine.validate(patch: candidate.patch, against: workspace)
        validationReport = report
        guard let committed = NarrativeValidationEngine.applying(
            candidate.patch,
            validation: report,
            to: workspace,
            trace: candidate.trace
        ) else {
            compilerMessage = "提交被确定性验证器阻止；请查看审计台。"
            return
        }
        var learned = committed
        learned.preferenceComparisons.append(contentsOf: candidates.compactMap { rejected in
            guard rejected.id != candidate.id else { return nil }
            return PreferenceComparison(
                id: UUID(),
                preferredCandidateID: candidate.id,
                rejectedCandidateID: rejected.id,
                projectSpecific: true,
                createdAt: .now
            )
        })
        do {
            try ProjectPersistenceStore.transaction(in: modelContext) {
                project.nsirWorkspace = learned
                SceneMappingEngine.synchronizeNSIRTransitions(
                    in: project,
                    document: learned,
                    modelContext: modelContext
                )
            }
        } catch {
            present(error)
            return
        }
        candidates = []
        selectedCandidateID = nil
        selectedTransitionID = learned.transitions.last?.id
        validationReport = report
        compilerMessage = "已提交为 NSIR revision \(learned.revision)；选择偏好已记录，剧本正文未被修改。"
        mode = .graph
    }

    @discardableResult
    private func persist(_ value: CompilerWorkspaceDocument) -> Bool {
        do {
            try ProjectPersistenceStore.transaction(in: modelContext) {
                project.nsirWorkspace = value
            }
            return true
        } catch {
            present(error)
            return false
        }
    }

    private func importPackage(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            let imported = try NSIRProjectPackageDocument.load(from: url)
            var value = imported.workspace
            value.projectID = project.id
            guard persist(value) else { return }
            compilerMessage = imported.screenplayText == project.screenplayText
                ? "NSIR 项目包已导入并通过项目 ID 重新绑定。"
                : "NSIR 已导入；为保护现有 Final Draft 正文，包内 screenplay.fountain 未自动覆盖当前文本。"
        } catch {
            present(error)
        }
    }

    private func routeProjection(_ item: NarrativeNavigatorProjection) {
        switch item {
        case .propositions: mode = .proposition
        case .transitions: mode = .transitions
        case .causal: mode = .graph
        case .scenes: mode = .timeline
        case .knowledge, .relationships, .motifs, .obligations: mode = .timeline
        case .characters: onNavigate(.characters)
        }
    }

    private func projectionCount(_ item: NarrativeNavigatorProjection) -> Int {
        switch item {
        case .propositions: workspace.propositions.count
        case .characters: project.characters.count
        case .relationships: max(workspace.state.relationships.count, project.characterRelationships.count)
        case .scenes: workspace.transitions.count
        case .transitions, .causal: workspace.transitions.count
        case .knowledge: workspace.state.beliefs.count
        case .motifs: workspace.state.motifStates.count
        case .obligations: workspace.obligations.count { $0.status == .open }
        }
    }

    private func characterName(_ id: UUID) -> String {
        project.characters.first { $0.id == id }?.name ?? "未命名人物"
    }

    private var safePackageName: String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let clean = project.title.components(separatedBy: invalid).joined(separator: "-")
        return "\(clean.isEmpty ? "StoryMentor-Project" : clean).storyproject"
    }

    private func objectiveTint(_ label: String) -> Color {
        switch label {
        case "因果": StudioTheme.accent
        case "知识合法": StudioTheme.sky
        case "情感覆盖": StudioTheme.warm
        default: StudioTheme.mint
        }
    }

    private func ruleTint(_ value: RuleClass) -> Color {
        switch value {
        case .l0: .red
        case .l1: StudioTheme.accent
        case .l2, .l3: StudioTheme.sky
        case .l4: StudioTheme.mint
        case .l5: StudioTheme.warm
        }
    }

    private func issueTint(_ value: IssueSeverity) -> Color {
        switch value {
        case .error: .red
        case .warning: StudioTheme.warm
        case .decision: StudioTheme.sky
        case .note: .secondary
        }
    }

    private func issueSymbol(_ value: IssueSeverity) -> String {
        switch value {
        case .error: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .decision: "questionmark.diamond.fill"
        case .note: "info.circle.fill"
        }
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
    }
}

private struct CompilerTransitionGraph: View {
    let transitions: [DramaticTransition]
    @Binding var selectedID: UUID?

    var body: some View {
        GeometryReader { proxy in
            if transitions.isEmpty {
                ContentUnavailableView(
                    "因果图为空",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("提交候选后，部分序转移会显示在这里。")
                )
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    let phase = timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 2.4) / 2.4
                    ZStack {
                        Canvas { context, size in
                            let points = graphPoints(size: size)
                            for index in 1..<points.count {
                                var path = Path()
                                path.move(to: points[index - 1])
                                path.addCurve(
                                    to: points[index],
                                    control1: CGPoint(x: (points[index - 1].x + points[index].x) / 2, y: points[index - 1].y),
                                    control2: CGPoint(x: (points[index - 1].x + points[index].x) / 2, y: points[index].y)
                                )
                                context.stroke(path, with: .color(StudioTheme.accent.opacity(0.28)), lineWidth: 2)
                                let moving = CGPoint(
                                    x: points[index - 1].x + (points[index].x - points[index - 1].x) * phase,
                                    y: points[index - 1].y + (points[index].y - points[index - 1].y) * phase
                                )
                                context.fill(Path(ellipseIn: CGRect(x: moving.x - 3, y: moving.y - 3, width: 6, height: 6)), with: .color(StudioTheme.mint))
                            }
                        }
                        ForEach(Array(transitions.enumerated()), id: \.element.id) { index, transition in
                            let point = graphPoints(size: proxy.size)[index]
                            Button {
                                withAnimation(.snappy(duration: 0.22)) { selectedID = transition.id }
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("τ\(index + 1) · \(transition.title)")
                                        .font(.caption.weight(.bold)).lineLimit(1)
                                    Text(transition.effects.first.map { "\($0.dimension.code) · \($0.afterValue)" } ?? "待定义状态")
                                        .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                }
                                .padding(11)
                                .frame(width: 180, alignment: .leading)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 13)
                                        .stroke(selectedID == transition.id ? StudioTheme.accent : Color.primary.opacity(0.08), lineWidth: selectedID == transition.id ? 2 : 1)
                                }
                                .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)
                            }
                            .buttonStyle(.plain)
                            .position(point)
                        }
                    }
                }
            }
        }
        .frame(minHeight: 390)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(Color.primary.opacity(0.06)) }
    }

    private func graphPoints(size: CGSize) -> [CGPoint] {
        guard !transitions.isEmpty else { return [] }
        let count = transitions.count
        let available = max(size.width - 220, 1)
        return transitions.indices.map { index in
            let fraction = count == 1 ? 0.5 : CGFloat(index) / CGFloat(count - 1)
            return CGPoint(
                x: 110 + available * fraction,
                y: size.height * (index.isMultiple(of: 2) ? 0.38 : 0.64)
            )
        }
    }
}

struct CompilerAnimatedBackdrop: View {
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: active ? 1 / 24 : 1)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                for index in 0..<7 {
                    let speed = 18 + Double(index * 7)
                    let x = (time * speed + Double(index) * 137)
                        .truncatingRemainder(dividingBy: max(Double(size.width), 1))
                    let y = Double(size.height) * (0.12 + Double(index) * 0.11)
                    let radius = active ? 3.5 : 2
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
                        with: .color(StudioTheme.accent.opacity(active ? 0.15 : 0.045))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? 560
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
