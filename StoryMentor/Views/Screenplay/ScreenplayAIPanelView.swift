import SwiftData
import SwiftUI

struct ScreenplayAIPanelView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AISettingsStore.self) private var settings
    @Bindable var project: StoryProject
    @Query private var workspaceStates: [ScreenplayWorkspaceState]

    @State private var isWorking = false
    @State private var progressMessage = ""
    @State private var latestResult: ScreenplaySceneAIResult?
    @State private var showingFullDraftOptions = false
    @State private var showingCompiledDraftOptions = false
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var sceneTask: Task<Void, Never>?
    @State private var fullDraftTask: Task<Void, Never>?
    @State private var compiledDraftTask: Task<Void, Never>?
    @State private var expandedOptionIDs = Set<UUID>()
    @State private var evidencePreview: [TheoryEvidence] = []
    @State private var isLoadingEvidence = false

    private var workspaceState: ScreenplayWorkspaceState? {
        workspaceStates
            .filter { $0.projectID == project.id }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private var scenes: [FountainSceneSnapshot] {
        FountainParser.scenes(in: project.screenplayText)
    }

    private var activeIndex: Int {
        min(max(workspaceState?.activeSceneIndex ?? 0, 0), max(scenes.count - 1, 0))
    }

    private var activeScene: FountainSceneSnapshot? {
        scenes.indices.contains(activeIndex) ? scenes[activeIndex] : nil
    }

    private func sceneRecord(at order: Int) -> ScreenplaySceneRecord? {
        workspaceState?.sceneRecords.first { $0.order == order }
    }

    private var cards: [SceneCardReference] {
        project.sceneContracts.isEmpty
            ? SceneCardImporter.cards(from: project.scenesText)
            : []
    }

    private var activeCard: SceneCardReference? {
        cards.indices.contains(activeIndex) ? cards[activeIndex] : nil
    }

    private var activeMetadata: ScreenplaySceneMetadata? {
        workspaceState?.sceneMetadata(at: activeIndex)
    }

    private var scenesNeedingProfessionalDraft: Int {
        scenes.count(where: SceneCompilationEngine.needsProfessionalDraft)
    }

    private var fullDraftPrerequisitesReady: Bool {
        let contracts = project.sceneContracts
        if ScreenplayProductionContextBuilder.isStandaloneScreenplay(project) {
            return true
        }
        return project.isStructureLocked
            && !contracts.isEmpty
            && contracts.allSatisfy {
                SceneCompilationEngine.isComplete($0)
                    && $0.areMicroBeatsConfirmed
            }
    }

    private var hasActiveGeneration: Bool {
        sceneTask != nil || fullDraftTask != nil || compiledDraftTask != nil
    }

    private var activeContract: SceneContract? {
        guard let contractID = sceneRecord(at: activeIndex)?.sceneContractID else {
            return nil
        }
        return project.sceneContracts.first { $0.id == contractID }
    }

    private var activeStructureAnchor: ScreenplayStructureAnchor? {
        ScreenplayProductionContextBuilder.anchor(
            for: activeContract,
            in: project
        )
    }

    private var evidenceQuery: String {
        guard let activeScene else { return "" }
        return ScreenplayProductionContextBuilder.retrievalQuery(
            project: project,
            scene: activeScene,
            contract: activeContract,
            task: ScreenplayGenerationMode.draft.rawValue
        )
    }

    private var evidenceTaskID: String {
        "\(settings.useKnowledgeBase)|\(evidenceQuery)"
    }

    var body: some View {
        ZStack {
            StudioCanvas()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    panelHeader

                    if let scene = activeScene {
                        sceneNavigator
                        sceneBrief(scene)
                        productionContextCard
                        actionGrid
                        instructionBox

                        if isWorking {
                            workingCard
                        }
                        if let activeMetadata,
                           !(activeMetadata.screenplayDraftOptions ?? []).isEmpty {
                            draftOptionsCard(activeMetadata)
                        }
                        if let latestResult {
                            resultCard(latestResult)
                        }
                        if let activeMetadata,
                           activeMetadata.status != .outline
                            || !(activeMetadata.continuityWarnings ?? []).isEmpty
                            || !(activeMetadata.choicesForAuthor ?? []).isEmpty {
                            authorReviewCard(activeMetadata)
                        }

                        fullDraftCard
                    } else {
                        noSceneCard
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
            }
            .scrollIndicators(.visible)
        }
        .confirmationDialog(
            "为全本逐场生成三案",
            isPresented: $showingFullDraftOptions,
            titleVisibility: .visible
        ) {
            Button("只补齐尚无三案的场景") {
                startFullDraft(rewriteExisting: false)
            }
            .keyboardShortcut(.defaultAction)
            Button("重新生成全部场景三案") {
                startFullDraft(rewriteExisting: true)
            }
            Button("取消", role: .cancel) {}
                .keyboardShortcut(.cancelAction)
        } message: {
            Text("系统会逐场调用当前 AI API，每场保存三个可选正文方案。生成阶段不会覆盖剧本正文，只有你选中的方案才会写入。")
        }
        .confirmationDialog(
            "把场景设计编译为完整剧本",
            isPresented: $showingCompiledDraftOptions,
            titleVisibility: .visible
        ) {
            Button("只完成骨架与占位场景") {
                startCompiledDraft(rewriteExisting: false)
            }
            .keyboardShortcut(.defaultAction)
            Button("按当前结构重写全本", role: .destructive) {
                startCompiledDraft(rewriteExisting: true)
            }
            Button("取消", role: .cancel) {}
                .keyboardShortcut(.cancelAction)
        } message: {
            Text("系统会按全本结构轨道和场景顺序逐场写入专业正文。开始前自动保存全本版本；中途停止时，已完成的场景会保留。")
        }
        .alert("智能编剧室", isPresented: $showingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .task(id: evidenceTaskID) {
            await refreshEvidencePreview()
        }
        .onDisappear {
            // Closing the writing room must never leave a whole-screenplay
            // or scene generation task mutating work that is no longer visible.
            sceneTask?.cancel()
            fullDraftTask?.cancel()
            compiledDraftTask?.cancel()
        }
    }

    private var panelHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "text.book.closed.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(StudioTheme.mint)
                EyebrowLabel(text: "智能编剧室", color: StudioTheme.mint)
                Text("逐场完成剧本")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                Text("\(settings.provider.displayName) 读取全部前序场景并生成三案；你负责创意注入、审阅、选择与锁定。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.bordered)
            .clipShape(Circle())
            .keyboardShortcut(.cancelAction)
            .help("关闭智能编剧室")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sceneNavigator: some View {
        HStack(spacing: 8) {
            Button {
                selectScene(activeIndex - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(activeIndex == 0 || isWorking)
            .help("上一场")

            Menu {
                ForEach(scenes) { scene in
                    Button {
                        selectScene(scene.index)
                    } label: {
                        if scene.index == activeIndex {
                            Label(
                                "场 \(scene.index + 1) · \(scene.heading)",
                                systemImage: "checkmark"
                            )
                        } else {
                            Text("场 \(scene.index + 1) · \(scene.heading)")
                        }
                    }
                }
            } label: {
                Label(
                    "场 \(activeIndex + 1) / \(max(scenes.count, 1))",
                    systemImage: "list.number"
                )
                .frame(minWidth: 116)
            }
            .disabled(isWorking)

            Button {
                selectScene(activeIndex + 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(activeIndex + 1 >= scenes.count || isWorking)
            .help("下一场")

            Spacer()

            Text(settings.provider.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(settings.hasAPIKey ? StudioTheme.mint : .secondary)
        }
        .controlSize(.small)
    }

    private func sceneBrief(_ scene: FountainSceneSnapshot) -> some View {
        StudioCard(padding: 15) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("场景 \(scene.index + 1)")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(StudioTheme.mint)
                    Spacer()
                    if let state = workspaceState {
                        PhaseBadge(text: state.sceneMetadata(at: activeIndex).status.rawValue)
                    }
                }
                Text(scene.heading)
                    .font(.headline)
                if let activeCard {
                    briefLine("目的", activeCard.purpose)
                    briefLine("冲突", activeCard.conflict)
                    briefLine("转折", activeCard.turningPoint)
                    briefLine("钩子", activeCard.endingHook)
                } else {
                    Text(scene.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !scene.characterNames.isEmpty {
                    Text("人物：\(scene.characterNames.joined(separator: "、"))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func briefLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(StudioTheme.mint)
                .frame(width: 28, alignment: .leading)
            Text(value.isEmpty ? "等待具体化" : value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var productionContextCard: some View {
        StudioCard(padding: 15) {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    EyebrowLabel(
                        text: "结构 → 场景 → 正文",
                        color: StudioTheme.sky
                    )
                    Spacer()
                    if let anchor = activeStructureAnchor {
                        PhaseBadge(text: anchor.progressLabel)
                    }
                }

                if let anchor = activeStructureAnchor {
                    Label(anchor.label, systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.callout.weight(.semibold))
                    Text(anchor.purpose)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if anchor.isInferred {
                        Text("旧项目未保存阶段编号，已按全片场景顺序稳定推定；生成时会将该阶段职责作为硬约束。")
                            .font(.caption2)
                            .foregroundStyle(StudioTheme.warm)
                    }
                } else {
                    Label("当前场景尚未连接结构阶段", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(StudioTheme.warm)
                }

                Divider()

                HStack(spacing: 7) {
                    Label(
                        settings.useKnowledgeBase ? "Private Theory RAG" : "RAG 已关闭",
                        systemImage: settings.useKnowledgeBase
                            ? "books.vertical.fill"
                            : "books.vertical"
                    )
                    .font(.caption.weight(.semibold))
                    Spacer()
                    if isLoadingEvidence {
                        ProgressView()
                            .controlSize(.mini)
                    } else if settings.useKnowledgeBase {
                        Text("命中 \(evidencePreview.count) 条")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if settings.useKnowledgeBase {
                    if evidencePreview.isEmpty && !isLoadingEvidence {
                        Text("本场未命中专门理论片段；已确认结构与场景契约仍会完整进入正文。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(evidencePreview.prefix(3)) { evidence in
                            Label(evidence.sourceLabel, systemImage: "text.quote")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                } else {
                    Text("可在 AI 设置中启用本地理论知识库；理论只改善执行，不覆盖作者选择。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                EyebrowLabel(text: "当前场 · 生成三个正文方案")
                Spacer()
                if !settings.hasAPIKey {
                    Label("请先配置 AI API", systemImage: "key.fill")
                        .font(.caption2)
                        .foregroundStyle(StudioTheme.warm)
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 150), spacing: 8)
                ],
                spacing: 8
            ) {
                ForEach(ScreenplayGenerationMode.allCases) { mode in
                    Button {
                        run(mode)
                    } label: {
                        Label(mode.rawValue, systemImage: mode.systemImage)
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isWorking || !settings.hasAPIKey)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var instructionBox: some View {
        StudioCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                EyebrowLabel(text: "当前场 · 作者创意注入")
                TextEditor(text: authorInstructionBinding)
                    .font(.caption)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 72)
                    .padding(7)
                    .background(
                        Color.primary.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                Text("这条创意只属于当前场。全本写作走到这里时会自动读取，例如：不要让母亲说出真相，让她一直擦同一个杯子。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var workingCard: some View {
        StudioCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 11) {
                    ProgressView()
                        .controlSize(.small)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(progressMessage.isEmpty ? "正在写当前场景" : progressMessage)
                            .font(.callout.weight(.semibold))
                        Text("先检查连续性和已确认场景，再生成动作与对白。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if hasActiveGeneration {
                        Button("停止") {
                            sceneTask?.cancel()
                            fullDraftTask?.cancel()
                            compiledDraftTask?.cancel()
                        }
                        .controlSize(.small)
                    }
                }

                if let state = workspaceState,
                   state.generationTotalScenes > 0,
                   fullDraftTask != nil || compiledDraftTask != nil {
                    ProgressView(value: state.generationProgress)
                        .tint(StudioTheme.mint)
                    HStack {
                        Text("全本进度")
                        Spacer()
                        Text(
                            "\(state.generationCompletedScenes) / \(state.generationTotalScenes) 场"
                        )
                        .monospacedDigit()
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func draftOptionsCard(
        _ metadata: ScreenplaySceneMetadata
    ) -> some View {
        let options = metadata.screenplayDraftOptions ?? []
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                EyebrowLabel(text: "当前场 · 三个 Final Draft 正文方案", color: StudioTheme.mint)
                Text("三个方案执行同一场景契约；选中前只保存为候选，不会覆盖正文。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(options.enumerated()), id: \.element.id) { offset, option in
                let isSelected = metadata.selectedScreenplayDraftOptionID == option.id
                let currentMatches = activeScene.map {
                    ScreenplayDraftOptionPolicy.fingerprint($0.text)
                        == ScreenplayDraftOptionPolicy.fingerprint(option.fountainText)
                } ?? false
                let sourceStillMatches = activeScene.map {
                    let sceneMatches = ScreenplayDraftOptionPolicy.fingerprint(
                        $0.text
                    ) == option.sourceSceneFingerprint
                    let upstreamMatches = option.sourceUpstreamSignature == nil
                        || option.sourceUpstreamSignature
                            == ScreenplayProjectionEngine.sourceSignature(
                                for: project
                            )
                    return sceneMatches && upstreamMatches
                } ?? false

                StudioCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("方案 \(["A", "B", "C"][min(offset, 2)])")
                                .font(.caption.monospaced().weight(.bold))
                                .foregroundStyle(StudioTheme.mint)
                            Text(option.title)
                                .font(.headline)
                            Spacer()
                            if isSelected {
                                PhaseBadge(
                                    text: currentMatches ? "已写入正文" : "已选 · 正文已修改"
                                )
                            }
                        }

                        Text(option.approach)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)

                        if !option.scenePurpose.isEmpty {
                            Text("场景作用：\(option.scenePurpose)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !option.emotionalTurn.isEmpty {
                            Text("情绪转向：\(option.emotionalTurn)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let anchor = option.structureAnchor,
                           !anchor.isEmpty {
                            Label(anchor, systemImage: "point.3.connected.trianglepath.dotted")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(StudioTheme.sky)
                        }
                        if let sources = option.knowledgeSources,
                           !sources.isEmpty {
                            DisclosureGroup("RAG 理论依据 · \(sources.count) 条") {
                                VStack(alignment: .leading, spacing: 5) {
                                    ForEach(sources, id: \.self) { source in
                                        Label(source, systemImage: "text.quote")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.top, 5)
                            }
                            .font(.caption.weight(.semibold))
                        }

                        DisclosureGroup(
                            "阅读完整 Final Draft/Fountain 正文",
                            isExpanded: expandedOptionBinding(option.id)
                        ) {
                            ScrollView {
                                Text(option.fountainText)
                                    .font(.system(size: 12, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                            }
                            .frame(maxHeight: 360)
                            .background(
                                Color.black.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .padding(.top, 6)
                        }
                        .font(.caption.weight(.semibold))

                        if !sourceStillMatches && !currentMatches {
                            Label(
                                "候选生成后正文已有变化；再次写入前会先保存当前版本",
                                systemImage: "clock.arrow.circlepath"
                            )
                            .font(.caption2)
                            .foregroundStyle(StudioTheme.warm)
                        }

                        Button {
                            applyDraftOption(option)
                        } label: {
                            Label(
                                isSelected && currentMatches
                                    ? "已写入剧本正文"
                                    : "选用并写入剧本正文",
                                systemImage: isSelected && currentMatches
                                    ? "checkmark.circle.fill"
                                    : "text.badge.checkmark"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(StudioTheme.mint)
                        .disabled(isWorking || (isSelected && currentMatches))
                    }
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(StudioTheme.mint.opacity(0.7), lineWidth: 1.5)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resultCard(_ result: ScreenplaySceneAIResult) -> some View {
        StudioCard(padding: 15) {
            VStack(alignment: .leading, spacing: 10) {
                Label("本轮场景变化", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(StudioTheme.mint)
                Text(result.scenePurpose)
                    .font(.callout.weight(.medium))
                if !result.emotionalTurn.isEmpty {
                    Text("情绪转向：\(result.emotionalTurn)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !result.structureAnchor.isEmpty {
                    Label(
                        result.structureAnchor,
                        systemImage: "point.3.connected.trianglepath.dotted"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(StudioTheme.sky)
                }
                if !result.knowledgeSources.isEmpty {
                    Label(
                        "RAG 命中 \(result.knowledgeSources.count) 条理论证据",
                        systemImage: "books.vertical.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                ForEach(result.beatSummary.prefix(5), id: \.self) {
                    Text("• \($0)")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func authorReviewCard(_ metadata: ScreenplaySceneMetadata) -> some View {
        let warnings = metadata.continuityWarnings ?? []
        let choices = metadata.choicesForAuthor ?? []
        return StudioCard(padding: 15) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("作者审阅台", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.headline)
                        .foregroundStyle(StudioTheme.warm)
                    Spacer()
                    Button {
                        setActiveSceneLocked(metadata.status != .approved)
                    } label: {
                        Label(
                            metadata.status == .approved ? "解除锁定" : "审阅通过并锁定",
                            systemImage: metadata.status == .approved
                                ? "lock.open.fill"
                                : "lock.fill"
                        )
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(metadata.status == .approved ? .secondary : StudioTheme.mint)
                }

                if !warnings.isEmpty {
                    EyebrowLabel(text: "需要核实", color: .red)
                    ForEach(warnings, id: \.self) {
                        LocalCheckRow(text: $0, state: .missing)
                    }
                }
                if !choices.isEmpty {
                    EyebrowLabel(text: "关键判断", color: StudioTheme.warm)
                    ForEach(choices, id: \.self) {
                        LocalCheckRow(text: $0, state: .neutral)
                    }
                }
                if warnings.isEmpty && choices.isEmpty {
                    Text("AI 没有把常规写作问题推回给你；确认本场成立后即可锁定。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fullDraftCard: some View {
        StudioCard(padding: 15) {
            VStack(alignment: .leading, spacing: 12) {
                EyebrowLabel(text: "全本交付成稿", color: StudioTheme.warm)
                Text("把前序实验、结构和场景选择编译成完整剧本")
                    .font(.headline)
                Text("全本编译会整体阅读锁定结构、全部场景契约、已确认小节拍、人物与世界圣经，并用本地 RAG 理论证据检查执行，然后按顺序写入可交付正文。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let state = workspaceState,
                   state.generationTotalScenes > 0,
                   state.generationStatus != "idle" {
                    ProgressView(value: state.generationProgress)
                        .tint(
                            state.generationStatus == "completed"
                                ? StudioTheme.mint
                                : StudioTheme.warm
                        )
                    HStack {
                        Text(state.generationMessage)
                            .lineLimit(1)
                        Spacer()
                        Text(
                            "\(state.generationCompletedScenes)/\(state.generationTotalScenes)"
                        )
                        .monospacedDigit()
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Button(
                        scenesNeedingProfessionalDraft > 0
                            ? "编译完整第一稿 · \(scenesNeedingProfessionalDraft) 场待完成"
                            : "重新编译完整第一稿",
                        systemImage: "text.book.closed.fill"
                    ) {
                        showingCompiledDraftOptions = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StudioTheme.mint)

                    Button(
                        "为全本生成三案精修",
                        systemImage: "sparkles.rectangle.stack.fill"
                    ) {
                        showingFullDraftOptions = true
                    }
                    .buttonStyle(.bordered)
                }
                .disabled(
                    isWorking
                        || scenes.isEmpty
                        || !settings.hasAPIKey
                        || !fullDraftPrerequisitesReady
                )

                if !fullDraftPrerequisitesReady {
                    Label(
                        fullDraftPrerequisiteMessage,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(StudioTheme.warm)
                }

                Text("“编译完整第一稿”直接产生全本正文；“三案精修”保留每场 A/B/C 候选，适合后续逐场打磨。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var noSceneCard: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("还没有可写的场景")
                    .font(.headline)
                Text("先在前序工作区完成至少一个场景；剧本页会读取场景契约与已确认小节拍生成正文三案。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func run(_ mode: ScreenplayGenerationMode) {
        guard !hasActiveGeneration else { return }
        sceneTask = Task {
            await generateSceneOptions(mode)
            sceneTask = nil
        }
    }

    private func generateSceneOptions(
        _ mode: ScreenplayGenerationMode
    ) async {
        guard let scene = activeScene else { return }
        let sceneIndex = activeIndex
        isWorking = true
        progressMessage = "\(mode.rawValue) · 正在生成场景 \(sceneIndex + 1) 的三个方案"
        defer { isWorking = false }
        do {
            guard let state = ensureWorkspaceState() else { return }
            let metadata = state.sceneMetadata(at: sceneIndex)
            let options = try await ScreenplayWritingEngine(
                settings: settings
            ).generateOptions(
                project: project,
                scene: scene,
                sceneContractID: sceneRecord(at: sceneIndex)?.sceneContractID,
                nextSceneContractID: sceneRecord(at: sceneIndex + 1)?.sceneContractID,
                sceneCard: cards.indices.contains(sceneIndex)
                    ? cards[sceneIndex]
                    : nil,
                nextSceneCard: cards.indices.contains(sceneIndex + 1)
                    ? cards[sceneIndex + 1]
                    : nil,
                mode: mode,
                length: metadata.length,
                authorInstruction: metadata.authorInstruction ?? ""
            )
            try Task.checkCancellation()
            let latestScenes = FountainParser.scenes(in: project.screenplayText)
            guard latestScenes.indices.contains(sceneIndex),
                  latestScenes[sceneIndex].text == scene.text else {
                throw CancellationError()
            }
            state.updateScene(at: sceneIndex) {
                $0.screenplayDraftOptions = options
                $0.selectedScreenplayDraftOptionID = nil
            }
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            expandedOptionIDs = []
            latestResult = nil
            progressMessage = "场景 \(sceneIndex + 1) 的三个方案已保存；选中前正文保持不变"
        } catch is CancellationError {
            progressMessage = "已停止；正文与原有候选均未改变"
        } catch {
            present(error)
        }
    }

    private func startCompiledDraft(rewriteExisting: Bool) {
        guard !hasActiveGeneration else { return }
        compiledDraftTask = Task {
            await compileFullDraft(rewriteExisting: rewriteExisting)
            compiledDraftTask = nil
        }
    }

    /// Sequentially realizes the confirmed story tree as one canonical first
    /// draft. Every request sees the scenes already completed before it, so
    /// entrances, exits, knowledge and tone carry across the whole screenplay.
    private func compileFullDraft(rewriteExisting: Bool) async {
        guard !scenes.isEmpty else {
            present(ScreenplayWritingError.noScenes)
            return
        }
        isWorking = true
        defer { isWorking = false }

        do {
            try validateFullDraftPrerequisites()
            guard let state = ensureWorkspaceState() else { return }
            let initialSceneCount = scenes.count
            state.addRevision(
                title: "全本结构编译前",
                fountainText: project.screenplayText
            )
            state.beginGeneration(totalScenes: initialSceneCount)
            state.generationMessage = "正在建立全本结构与 RAG 执行上下文"
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            var completedScenes = 0

            for index in 0..<initialSceneCount {
                try Task.checkCancellation()
                let currentScenes = FountainParser.scenes(
                    in: project.screenplayText
                )
                guard currentScenes.indices.contains(index) else {
                    throw ScreenplayWritingError.invalidResponse
                }
                let scene = currentScenes[index]
                if !rewriteExisting,
                   !SceneCompilationEngine.needsProfessionalDraft(scene) {
                    completedScenes += 1
                    state.updateGeneration(
                        completed: completedScenes,
                        current: index + 1,
                        message: "第 \(index + 1) 场已是完整正文，已保留"
                    )
                    try ProjectPersistenceStore.savePendingChanges(
                        in: modelContext
                    )
                    continue
                }

                let record = state.sceneRecords.first { $0.order == index }
                let contractID = record?.sceneContractID
                let nextContractID = state.sceneRecords.first {
                    $0.order == index + 1
                }?.sceneContractID
                let metadata = state.sceneMetadata(at: index)
                progressMessage = "全本编译 · 正在完成第 \(index + 1) / \(initialSceneCount) 场"
                state.updateGeneration(
                    completed: completedScenes,
                    current: index + 1,
                    message: progressMessage
                )
                try ProjectPersistenceStore.savePendingChanges(in: modelContext)

                let result = try await ScreenplayWritingEngine(
                    settings: settings
                ).generate(
                    project: project,
                    scene: scene,
                    sceneContractID: contractID,
                    nextSceneContractID: nextContractID,
                    sceneCard: cards.indices.contains(index)
                        ? cards[index]
                        : nil,
                    nextSceneCard: cards.indices.contains(index + 1)
                        ? cards[index + 1]
                        : nil,
                    mode: .draft,
                    length: metadata.length,
                    authorInstruction: metadata.authorInstruction ?? ""
                )
                try Task.checkCancellation()
                guard ScreenplayDraftOptionPolicy.isProfessionalSceneText(
                    result.fountainText
                ) else {
                    throw ScreenplayWritingError.incompleteProfessionalScene
                }

                let latestScenes = FountainParser.scenes(
                    in: project.screenplayText
                )
                guard latestScenes.indices.contains(index),
                      latestScenes[index].text == scene.text else {
                    throw CancellationError()
                }

                let updated = FountainParser.replacingScene(
                    at: index,
                    in: project.screenplayText,
                    with: result.fountainText
                )
                project.screenplayText = updated
                project.touch()
                if let recordID = record?.id {
                    DramaticProjectionEngine.markSceneStale(
                        sceneRecordID: recordID,
                        in: project
                    )
                }

                let refreshed = FountainParser.scenes(in: updated)
                let records = state.reconcileScenes(refreshed)
                state.activeSceneIndex = min(
                    index,
                    max(refreshed.count - 1, 0)
                )
                state.activeSceneID = records.first {
                    $0.order == state.activeSceneIndex
                }?.id
                state.updateScene(at: state.activeSceneIndex) { sceneMetadata in
                    sceneMetadata.status = sceneMetadata.status == .outline
                        ? .drafted
                        : .revised
                    sceneMetadata.selectedScreenplayDraftOptionID = nil
                    sceneMetadata.emotionalTurn = result.emotionalTurn
                    sceneMetadata.aiNote = result.scenePurpose
                    sceneMetadata.continuityWarnings = result.continuityWarnings
                    sceneMetadata.choicesForAuthor = result.choicesForAuthor
                    sceneMetadata.structureAnchor = result.structureAnchor
                    sceneMetadata.knowledgeSources = result.knowledgeSources
                }
                completedScenes += 1
                state.updateGeneration(
                    completed: completedScenes,
                    current: index + 1,
                    message: "第 \(index + 1) 场已写入完整正文"
                )
                try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            }

            state.addRevision(
                title: "全本结构编译第一稿",
                fountainText: project.screenplayText
            )
            StoryCompiler.insertSnapshot(
                project: project,
                title: "全本结构编译第一稿",
                reason: "已将实验结果、结构阶段、场景契约、小节拍与本地 RAG 理论证据落实为完整剧本正文",
                in: modelContext
            )
            state.finishGeneration(
                status: "completed",
                message: "完整第一稿已写入，可进入四轮检查与 Final Draft 交付"
            )
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            progressMessage = state.generationMessage
        } catch is CancellationError {
            progressMessage = "已停止，完成的场景和编译前版本均已保留"
            workspaceState?.finishGeneration(
                status: "paused",
                message: progressMessage
            )
            savePendingChanges()
        } catch {
            workspaceState?.finishGeneration(
                status: "failed",
                message: error.localizedDescription
            )
            savePendingChanges()
            present(error)
        }
    }

    private func startFullDraft(rewriteExisting: Bool) {
        guard !hasActiveGeneration else { return }
        fullDraftTask = Task {
            await generateFullDraft(rewriteExisting: rewriteExisting)
            fullDraftTask = nil
        }
    }

    private func generateFullDraft(rewriteExisting: Bool) async {
        guard !scenes.isEmpty else {
            present(ScreenplayWritingError.noScenes)
            return
        }
        isWorking = true
        defer { isWorking = false }

        do {
            try validateFullDraftPrerequisites()
            guard let state = ensureWorkspaceState() else { return }
            let initialSceneCount = scenes.count
            state.beginGeneration(totalScenes: initialSceneCount)
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            var completedScenes = 0

            for index in 0..<initialSceneCount {
                try Task.checkCancellation()
                let currentScenes = FountainParser.scenes(in: project.screenplayText)
                guard currentScenes.indices.contains(index) else {
                    completedScenes += 1
                    state.updateGeneration(
                        completed: completedScenes,
                        current: index + 1,
                        message: "场景 \(index + 1) 不存在，已跳过"
                    )
                    try ProjectPersistenceStore.savePendingChanges(in: modelContext)
                    continue
                }
                let scene = currentScenes[index]
                let metadata = state.sceneMetadata(at: index)
                if !rewriteExisting,
                   let existing = metadata.screenplayDraftOptions,
                   ScreenplayDraftOptionPolicy.isValidSet(existing) {
                    completedScenes += 1
                    state.updateGeneration(
                        completed: completedScenes,
                        current: index + 1,
                        message: "第 \(index + 1) 场已有三个候选，已保留"
                    )
                    try ProjectPersistenceStore.savePendingChanges(in: modelContext)
                    continue
                }

                progressMessage = "全本三案 · 正在生成第 \(index + 1) / \(initialSceneCount) 场"
                state.updateGeneration(
                    completed: completedScenes,
                    current: index + 1,
                    message: progressMessage
                )
                try ProjectPersistenceStore.savePendingChanges(in: modelContext)
                let card = cards.indices.contains(index) ? cards[index] : nil
                let nextCard = cards.indices.contains(index + 1) ? cards[index + 1] : nil
                let options = try await ScreenplayWritingEngine(
                    settings: settings
                ).generateOptions(
                    project: project,
                    scene: scene,
                    sceneContractID: sceneRecord(at: index)?.sceneContractID,
                    nextSceneContractID: sceneRecord(at: index + 1)?.sceneContractID,
                    sceneCard: card,
                    nextSceneCard: nextCard,
                    mode: .draft,
                    length: metadata.length,
                    authorInstruction: metadata.authorInstruction ?? ""
                )
                try Task.checkCancellation()
                guard ScreenplayDraftOptionPolicy.isValidSet(options) else {
                    throw ScreenplayWritingError.invalidOptionSet
                }
                let latestScenes = FountainParser.scenes(in: project.screenplayText)
                guard latestScenes.indices.contains(index),
                      latestScenes[index].text == scene.text else {
                    progressMessage = "第 \(index + 1) 场检测到作者修改，已保留并跳过"
                    completedScenes += 1
                    state.updateGeneration(
                        completed: completedScenes,
                        current: index + 1,
                        message: progressMessage
                    )
                    try ProjectPersistenceStore.savePendingChanges(in: modelContext)
                    continue
                }
                state.updateScene(at: index) {
                    $0.screenplayDraftOptions = options
                    $0.selectedScreenplayDraftOptionID = nil
                }
                completedScenes += 1
                state.updateGeneration(
                    completed: completedScenes,
                    current: index + 1,
                    message: "第 \(index + 1) 场三个候选已保存，正文未改动"
                )
                try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            }
            state.finishGeneration(
                status: "completed",
                message: "全本每场三个正文候选已保存，请逐场选择"
            )
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            progressMessage = "全本三案已生成；请选择每场方案后写入正文"
        } catch is CancellationError {
            progressMessage = "已停止，完成的场景均已保留"
            workspaceState?.finishGeneration(
                status: "paused",
                message: progressMessage
            )
            savePendingChanges()
        } catch {
            workspaceState?.finishGeneration(
                status: "failed",
                message: error.localizedDescription
            )
            savePendingChanges()
            present(error)
        }
    }

    private func applyDraftOption(_ option: ScreenplaySceneDraftOption) {
        guard let state = ensureWorkspaceState(),
              activeScene != nil,
              let updated = ScreenplayDraftOptionPolicy.applying(
                option,
                to: project.screenplayText,
                at: activeIndex
              ) else {
            present(ScreenplayWritingError.invalidOptionSet)
            return
        }

        let index = activeIndex
        let recordID = sceneRecord(at: index)?.id
        state.addRevision(
            title: "选用 AI 正文方案 · 第 \(index + 1) 场 · \(option.title) 前",
            fountainText: project.screenplayText
        )
        project.screenplayText = updated
        if let recordID {
            DramaticProjectionEngine.markSceneStale(
                sceneRecordID: recordID,
                in: project
            )
        }

        let refreshed = FountainParser.scenes(in: updated)
        let records = state.reconcileScenes(refreshed)
        state.activeSceneIndex = min(index, max(refreshed.count - 1, 0))
        state.activeSceneID = records.first {
            $0.order == state.activeSceneIndex
        }?.id
        state.updateScene(at: state.activeSceneIndex) { metadata in
            metadata.status = metadata.status == .outline ? .drafted : .revised
            metadata.selectedScreenplayDraftOptionID = option.id
            metadata.emotionalTurn = option.emotionalTurn
            metadata.aiNote = option.scenePurpose
            metadata.continuityWarnings = option.continuityWarnings
            metadata.choicesForAuthor = option.choicesForAuthor
            metadata.structureAnchor = option.structureAnchor
            metadata.knowledgeSources = option.knowledgeSources
        }
        project.touch()

        do {
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            latestResult = ScreenplaySceneAIResult(
                fountainText: option.fountainText,
                scenePurpose: option.scenePurpose,
                emotionalTurn: option.emotionalTurn,
                beatSummary: option.beatSummary,
                continuityWarnings: option.continuityWarnings,
                choicesForAuthor: option.choicesForAuthor,
                structureAnchor: option.structureAnchor ?? "",
                knowledgeSources: option.knowledgeSources ?? []
            )
            progressMessage = "方案“\(option.title)”已写入第 \(index + 1) 场；关闭面板即可继续编辑正文"
        } catch {
            present(error)
        }
    }

    private func selectScene(_ requestedIndex: Int) {
        guard !isWorking,
              scenes.indices.contains(requestedIndex),
              let state = ensureWorkspaceState() else {
            return
        }
        state.activeSceneIndex = requestedIndex
        state.activeSceneID = state.sceneRecords.first {
            $0.order == requestedIndex
        }?.id
        state.updatedAt = .now
        latestResult = nil
        expandedOptionIDs = []
        savePendingChanges()
    }

    private func expandedOptionBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedOptionIDs.contains(id) },
            set: { expanded in
                if expanded {
                    expandedOptionIDs.insert(id)
                } else {
                    expandedOptionIDs.remove(id)
                }
            }
        )
    }

    private var authorInstructionBinding: Binding<String> {
        Binding(
            get: {
                workspaceState?
                    .sceneMetadata(at: activeIndex)
                    .authorInstruction ?? ""
            },
            set: { value in
                guard let state = ensureWorkspaceState() else { return }
                state.updateScene(at: activeIndex) {
                    $0.authorInstruction = value
                }
                savePendingChanges()
            }
        )
    }

    private func setActiveSceneLocked(_ locked: Bool) {
        guard let state = ensureWorkspaceState() else { return }
        state.updateScene(at: activeIndex) {
            $0.status = locked ? .approved : .revised
        }
        savePendingChanges()
    }

    private func ensureWorkspaceState() -> ScreenplayWorkspaceState? {
        if let workspaceState { return workspaceState }
        do {
            return try ProjectPersistenceStore.screenplayState(
                for: project,
                in: modelContext
            )
        } catch {
            present(error)
            return nil
        }
    }

    private func validateFullDraftPrerequisites() throws {
        if ScreenplayProductionContextBuilder.isStandaloneScreenplay(project) {
            return
        }
        guard project.isStructureLocked else {
            throw ScreenplayWritingError.unlockedStructure
        }
        guard !project.sceneContracts.isEmpty else {
            throw ScreenplayWritingError.missingSceneMapping
        }
        guard project.sceneContracts.allSatisfy({
            SceneCompilationEngine.isComplete($0)
                && $0.areMicroBeatsConfirmed
        }) else {
            throw ScreenplayWritingError.incompleteSmallBeats
        }
    }

    private var fullDraftPrerequisiteMessage: String {
        if !project.isStructureLocked {
            return "先选择并锁定全本结构，再把每场映射落实到正文"
        }
        if project.sceneContracts.isEmpty {
            return "结构已锁定；请先在场景工作台把结构阶段拆成完整场景"
        }
        return "先回到场景工作台确认每场契约与全部小节拍，才能编译全本正文"
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
    }

    private func refreshEvidencePreview() async {
        let query = evidenceQuery
        guard settings.useKnowledgeBase, !query.isEmpty else {
            evidencePreview = []
            isLoadingEvidence = false
            return
        }
        isLoadingEvidence = true
        let matches = (try? await TheoryIndexStore.shared.search(
            query: query,
            route: TheoryRouting.route(for: .screenplay),
            maximumMatches: 5,
            maximumCharacters: 2_600
        )) ?? []
        guard query == evidenceQuery else { return }
        evidencePreview = matches
        isLoadingEvidence = false
    }

    private func savePendingChanges() {
        do {
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
        } catch {
            present(error)
        }
    }
}
