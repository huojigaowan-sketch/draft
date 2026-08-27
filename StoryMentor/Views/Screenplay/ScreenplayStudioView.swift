import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private struct ScreenplaySceneWorkspaceItem: Identifiable {
    let id: UUID
    let record: ScreenplaySceneRecord
    let snapshot: FountainSceneSnapshot
}

private struct ScreenplaySceneHeadingEditRequest: Identifiable {
    let id: UUID
    let heading: String
}

private enum ScreenplayCanvasMode: String, CaseIterable, Identifiable {
    case scene = "单场编辑"
    case fullScript = "全本页稿"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .scene: "square.and.pencil"
        case .fullScript: "text.book.closed.fill"
        }
    }
}

struct ScreenplayStudioView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AISettingsStore.self) private var aiSettings
    @Bindable var project: StoryProject
    let onNavigate: (WorkspaceSection) -> Void
    @Query private var workspaceStates: [ScreenplayWorkspaceState]

    @State private var isImporting = false
    @State private var showingAIPanel = false
    @State private var showingNavigator = true
    @State private var showingRuler = false
    @State private var showingFindReplace = false
    @State private var editingSceneHeading: ScreenplaySceneHeadingEditRequest?
    @State private var showingElementSettings = false
    @State private var showingSceneBeatPlanner = false
    @State private var showingDramaticLens = true
    @State private var isAnalyzingSemantics = false
    @State private var semanticWarnings: [String] = []
    @State private var semanticMessage = ""
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var pendingUpstreamContractIDs = Set<UUID>()
    @State private var forceRemapContractID: UUID?
    @State private var zoomScale = 1.65
    @State private var editorController = FountainEditorController()
    @State private var cursorContext = FountainCursorContext.action
    @State private var canvasMode: ScreenplayCanvasMode = .scene
    @State private var synchronizedSceneRecords: [ScreenplaySceneRecord] = []
    @State private var cachedScenes: [FountainSceneSnapshot] = []

    @State private var activeSceneDraft = ""
    @State private var cachedActiveEstimatedSeconds: Double = 0
    @State private var cachedActiveEstimatedPages = 1
    @State private var loadedSceneIndex = -1
    @State private var lastSavedSceneDraft = ""
    @State private var lastCommittedFullText = ""
    @State private var hasPendingSave = false
    @State private var sceneDraftSaveTask: Task<Void, Never>?

    private var workspaceState: ScreenplayWorkspaceState? {
        workspaceStates
            .filter { $0.projectID == project.id }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private var scenes: [FountainSceneSnapshot] {
        cachedScenes
    }

    private var sceneItems: [ScreenplaySceneWorkspaceItem] {
        let records = synchronizedSceneRecords.sorted { $0.order < $1.order }
        let recordsByOrder = Dictionary(
            uniqueKeysWithValues: records.map { ($0.order, $0) }
        )
        return scenes.compactMap { snapshot in
            guard let record = recordsByOrder[snapshot.index] else {
                return nil
            }
            return ScreenplaySceneWorkspaceItem(
                id: record.id,
                record: record,
                snapshot: snapshot
            )
        }
    }

    private var activeIndex: Int {
        min(
            max(workspaceState?.activeSceneIndex ?? loadedSceneIndex, 0),
            max(scenes.count - 1, 0)
        )
    }

    private var committedScreenplayText: String {
        guard loadedSceneIndex >= 0,
              scenes.indices.contains(loadedSceneIndex) else {
            return project.screenplayText
        }
        let current = activeSceneDraft.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let saved = scenes[loadedSceneIndex].text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard current != saved else { return project.screenplayText }
        return FountainParser.replacingScene(
            at: loadedSceneIndex,
            in: project.screenplayText,
            with: current
        )
    }

    private var activeEstimatedSeconds: Double {
        cachedActiveEstimatedSeconds
    }

    private var activeEstimatedPages: Int {
        cachedActiveEstimatedPages
    }

    private var estimatedPages: Int {
        scenes.enumerated().reduce(0) { total, item in
            total + (
                item.offset == loadedSceneIndex
                    ? activeEstimatedPages
                    : item.element.estimatedPages
            )
        }
    }

    private var estimatedDuration: Double {
        scenes.enumerated().reduce(0) { total, item in
            total + (
                item.offset == loadedSceneIndex
                    ? activeEstimatedSeconds
                    : item.element.estimatedDurationSeconds
            )
        }
    }

    private var activePageStart: Int {
        guard activeIndex > 0 else { return 1 }
        return scenes.prefix(activeIndex).reduce(1) { $0 + $1.estimatedPages }
    }

    private var elementStyles: [ScreenplayElementStyleDefinition] {
        workspaceState?.elementStyles
            ?? ScreenplayElementStyleDefinition.defaultStyles
    }

    private var activeSceneMetadata: ScreenplaySceneMetadata {
        workspaceState?.sceneMetadata(at: activeIndex)
            ?? ScreenplaySceneMetadata(sceneIndex: activeIndex)
    }

    private var orderedSceneContracts: [SceneContract] {
        project.sceneContracts.sorted { $0.sceneIndex < $1.sceneIndex }
    }

    private var upstreamSceneSignature: String {
        ScreenplayProjectionEngine.sourceSignature(for: project)
    }

    private var scenesReadyForSmallBeats: Bool {
        !orderedSceneContracts.isEmpty
            && orderedSceneContracts.allSatisfy {
                $0.selectedSceneOptionID != nil
                    && SceneCompilationEngine.isComplete($0)
            }
    }

    private var isLegacyStandaloneScreenplay: Bool {
        orderedSceneContracts.isEmpty
            && !project.screenplayText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
    }

    private var allSmallBeatsConfirmed: Bool {
        scenesReadyForSmallBeats
            && orderedSceneContracts.allSatisfy(\.areMicroBeatsConfirmed)
    }

    private var firstIncompleteSmallBeatContract: SceneContract? {
        orderedSceneContracts.first { !$0.areMicroBeatsConfirmed }
    }

    private var activeSceneRecord: ScreenplaySceneRecord? {
        synchronizedSceneRecords.first { $0.order == activeIndex }
    }

    private var activeSceneContract: SceneContract? {
        guard let contractID = activeSceneRecord?.sceneContractID else { return nil }
        return orderedSceneContracts.first { $0.id == contractID }
    }

    private var activeStructureAnchor: ScreenplayStructureAnchor? {
        ScreenplayProductionContextBuilder.anchor(
            for: activeSceneContract,
            in: project
        )
    }

    private var activeDramaticUpdates: [DramaticUpdateRecord] {
        guard let id = activeSceneRecord?.id else { return [] }
        return project.dramaticUpdates.filter { $0.sceneRecordID == id }
    }

    private var activeSceneProjection: NarrativeProjectionRecord? {
        guard let id = activeSceneRecord?.id else { return nil }
        return DramaticProjectionEngine.projection(
            .scene,
            key: id.uuidString,
            in: project
        )
    }

    private var smallBeatPlanningContract: SceneContract? {
        guard scenesReadyForSmallBeats else { return nil }
        if showingSceneBeatPlanner, let activeSceneContract {
            return activeSceneContract
        }
        guard !allSmallBeatsConfirmed else { return nil }
        if let activeSceneContract, !activeSceneContract.areMicroBeatsConfirmed {
            return activeSceneContract
        }
        return firstIncompleteSmallBeatContract
    }

    var body: some View {
        VStack(spacing: 10) {
            aiCreationHeader
            editorBody
            statusBar
        }
        .padding(10)
        .background(ScreenplayEditorPalette.workspace)
        .task {
            let addedNSIRMappings = SceneMappingEngine.synchronizeNSIRTransitions(
                in: project,
                document: project.nsirWorkspace,
                modelContext: modelContext
            )
            let addedLegacyMappings = SceneMappingEngine.synchronizeConfirmedStages(
                in: project,
                modelContext: modelContext
            )
            guard let state = ensureWorkspaceState() else { return }
            synchronizeUpstreamScreenplay(in: state)

            if project.screenplayText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty {
                project.screenplayText = "INT. 未定地点 - 日\n\n"
                project.touch()
                savePendingChanges()
            } else {
                let localizedText = FountainParser.standardizingSceneFlow(
                    in: project.screenplayText
                )
                if localizedText != project.screenplayText {
                    project.screenplayText = localizedText
                    project.touch()
                    savePendingChanges()
                }
            }

            let initialScenes = refreshSceneCache(from: project.screenplayText)
            synchronizeSceneRecords(using: initialScenes)
            bindSceneContractsIfNeeded(in: state)
            if addedNSIRMappings || addedLegacyMappings {
                savePendingChanges()
            }
            lastCommittedFullText = project.screenplayText
            if let incomplete = firstIncompleteSmallBeatContract,
               let record = synchronizedSceneRecords.first(where: {
                   $0.sceneContractID == incomplete.id
               }) {
                loadScene(at: record.order)
            } else if let activeSceneID = state.activeSceneID,
               let record = synchronizedSceneRecords.first(where: {
                   $0.id == activeSceneID
               }) {
                loadScene(at: record.order)
            } else {
                loadScene(at: state.activeSceneIndex)
            }
        }
        .onChange(of: activeSceneDraft) { _, newValue in
            refreshActiveMetrics(for: newValue)
            guard newValue != lastSavedSceneDraft else {
                sceneDraftSaveTask?.cancel()
                hasPendingSave = false
                return
            }
            scheduleSceneSave()
        }
        .onChange(of: project.screenplayText) { _, newValue in
            guard newValue != lastCommittedFullText else { return }
            sceneDraftSaveTask?.cancel()
            // This path represents an external full-script write (AI task,
            // version restore, or another workspace). Without a reliable
            // scene-local edit token, invalidate conservatively.
            DramaticProjectionEngine.markAllStale(in: project)
            lastCommittedFullText = newValue
            let refreshedScenes = refreshSceneCache(from: newValue)
            let selectedID = workspaceState?.activeSceneID
            synchronizeSceneRecords(using: refreshedScenes)
            if let selectedID,
               let record = synchronizedSceneRecords.first(where: {
                   $0.id == selectedID
               }) {
                loadScene(at: record.order)
            } else {
                loadScene(at: activeIndex)
            }
            do {
                try ProjectPersistenceStore.transaction(in: modelContext) {
                    StoryCompiler.updateFindings(project: project, in: modelContext)
                }
            } catch {
                present(error)
            }
        }
        .onChange(of: upstreamSceneSignature) { oldValue, newValue in
            guard oldValue != newValue else { return }
            commitSceneDraft()
            guard let state = ensureWorkspaceState() else { return }
            synchronizeUpstreamScreenplay(in: state, reloadCurrentScene: true)
        }
        .onDisappear {
            sceneDraftSaveTask?.cancel()
            commitSceneDraft()
        }
        .sheet(isPresented: $showingAIPanel) {
            ScreenplayAIPanelView(
                project: project
            )
            .frame(width: 680)
            .frame(minHeight: 640, idealHeight: 820, maxHeight: 880)
        }
        .sheet(isPresented: $showingElementSettings) {
            ScreenplayElementSettingsView(styles: elementStylesBinding)
        }
        .sheet(isPresented: $showingFindReplace) {
            ScreenplayFindReplaceView(
                scriptText: committedScreenplayText,
                onSelectScene: { sceneIndex in
                    showingFindReplace = false
                    selectScene(sceneIndex)
                },
                onApply: { updatedText, revisionTitle in
                    applyBulkEdit(
                        updatedText,
                        revisionTitle: revisionTitle
                    )
                }
            )
        }
        .sheet(item: $editingSceneHeading) { request in
            ScreenplaySceneHeadingEditorView(
                initialHeading: request.heading
            ) { heading in
                renameSceneHeading(
                    sceneID: request.id,
                    heading: heading
                )
            }
        }
        .onChange(of: editorController.manageStylesRequestID) {
            showingElementSettings = true
        }
        .onChange(of: showingAIPanel) { wasShowing, isShowing in
            if wasShowing && !isShowing {
                lastCommittedFullText = project.screenplayText
                loadScene(at: activeIndex)
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: false,
            onCompletion: importFountain
        )
        .alert("剧本编辑器", isPresented: $showingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .confirmationDialog(
            "用上游场景内容重建当前场？",
            isPresented: Binding(
                get: { forceRemapContractID != nil },
                set: { if !$0 { forceRemapContractID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("重建当前场", role: .destructive) {
                guard let contractID = forceRemapContractID,
                      let state = ensureWorkspaceState() else { return }
                forceRemapContractID = nil
                commitSceneDraft()
                state.addRevision(
                    title: "重新汇聚当前场前",
                    fountainText: project.screenplayText
                )
                synchronizeUpstreamScreenplay(
                    in: state,
                    forceContractIDs: [contractID],
                    reloadCurrentScene: true
                )
            }
            Button("取消", role: .cancel) {
                forceRemapContractID = nil
            }
        } message: {
            Text("当前场的直接修改会先进入版本记录，然后由前序结构与小节拍内容重新生成。其他场景不会受影响。")
        }
    }

    private var lockedScreenplayWorkspace: some View {
        VStack(spacing: 0) {
            StoryHierarchyBar(
                selection: .screenplay,
                onSelect: onNavigate,
                compact: true
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.thinMaterial)

            VStack(spacing: 16) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(StudioTheme.warm)
                Text("先完成全部场景")
                    .font(.system(size: 27, weight: .semibold, design: .serif))
                Text("第 4 层只接受第 3 层已经确认的完整场景。返回场景工作台，完成每个大节拍下的全部场景后，再逐场推导必要情境更新。")
                    .font(.system(size: 15.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 680)
                Button("返回场景工作台", systemImage: "arrow.up.left") {
                    onNavigate(.scenes)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(30)
        }
    }

    private func smallBeatWorkflowHeader(_ contract: SceneContract) -> some View {
        let completedScenes = orderedSceneContracts.count {
            $0.areMicroBeatsConfirmed
        }
        return HStack(spacing: 12) {
            StoryHierarchyBar(
                selection: .screenplay,
                onSelect: onNavigate,
                compact: true
            )

            Spacer()

            Text("情境更新完成 \(completedScenes)/\(orderedSceneContracts.count) 场")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)

            Menu {
                ForEach(orderedSceneContracts) { scene in
                    let confirmed = scene.microBeats.count {
                        $0.selectedOption != nil
                    }
                    Button {
                        selectSceneContract(scene)
                    } label: {
                        Label(
                            "场 \(scene.sceneIndex) · \(scene.heading) · \(confirmed)/\(scene.microBeats.count)",
                            systemImage: scene.areMicroBeatsConfirmed
                                ? "checkmark.circle.fill"
                                : "circle.dashed"
                        )
                    }
                }
            } label: {
                Label(
                    "场 \(contract.sceneIndex) / \(orderedSceneContracts.count)",
                    systemImage: "list.number"
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    private var aiCreationHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Final Draft 正文")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Text(
                    activeStructureAnchor.map {
                        "\($0.label) · TextKit 元素流转 · 全本标准页流"
                    } ?? "TextKit 元素流转 · 全本标准页流"
                )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 18)

            Picker("剧本视图", selection: canvasModeBinding) {
                ForEach(ScreenplayCanvasMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.systemImage)
                        .tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 210)
            .help("在单场 TextKit 编辑和完整标准剧本页稿之间切换")

            Button {
                openAIPanel()
            } label: {
                Label(
                    aiSettings.hasAPIKey
                        ? "\(aiSettings.provider.displayName) 全本成稿"
                        : "AI 全本成稿",
                    systemImage: "text.book.closed.fill"
                )
                .font(.system(size: 12, weight: .semibold))
                .frame(minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioTheme.warm)
            .help("将实验结果、锁定结构、场景契约、小节拍与本地 RAG 理论证据编译为完整剧本，也可在初稿后逐场三案精修")

            upstreamProjectionMenu

            elementMenu

            Button {
                commitSceneDraft()
                showingFindReplace = true
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("查找与替换")

            fileMenu
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .foregroundStyle(.primary)
        .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 26)
    }

    private var upstreamProjectionMenu: some View {
        Menu {
            Section("前序内容汇聚") {
                Button("安全同步全部场景", systemImage: "arrow.triangle.merge") {
                    commitSceneDraft()
                    guard let state = ensureWorkspaceState() else { return }
                    synchronizeUpstreamScreenplay(
                        in: state,
                        reloadCurrentScene: true
                    )
                }
                Button("返回场景工作台修改", systemImage: "arrow.up.left") {
                    commitSceneDraft()
                    onNavigate(.scenes)
                }
            }

            if let activeSceneContract {
                Divider()
                Button(
                    "用上游内容重建当前场…",
                    systemImage: "arrow.clockwise"
                ) {
                    forceRemapContractID = activeSceneContract.id
                }
            }

            if !pendingUpstreamContractIDs.isEmpty {
                Divider()
                Text("有 \(pendingUpstreamContractIDs.count) 场包含正文修改，已保留作者版本")
            }
        } label: {
            Label(
                pendingUpstreamContractIDs.isEmpty
                    ? "上游已汇聚"
                    : "待汇聚 \(pendingUpstreamContractIDs.count)",
                systemImage: pendingUpstreamContractIDs.isEmpty
                    ? "arrow.triangle.merge"
                    : "exclamationmark.arrow.triangle.2.circlepath"
            )
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(
                pendingUpstreamContractIDs.isEmpty
                    ? StudioTheme.mint
                    : StudioTheme.warm
            )
            .padding(.horizontal, 10)
            .frame(minHeight: 34)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .help(
            pendingUpstreamContractIDs.isEmpty
                ? "种子、实验、结构、场景与小节拍已安全汇聚到正文"
                : "上游已有变化；为保护直接改过的正文，需要确认后重建"
        )
    }

    private var elementMenu: some View {
        Menu {
            Section("当前行元素") {
                ForEach(elementStyles) { style in
                    Button {
                        editorController.applyElement(style.id)
                    } label: {
                        if style.id == cursorContext.elementID {
                            Label(style.displayName, systemImage: "checkmark")
                        } else {
                            Text(style.displayName)
                        }
                    }
                    .disabled(canvasMode == .fullScript)
                }
            }
            Divider()
            Button("在光标处弹出元素菜单", systemImage: "list.bullet.rectangle") {
                editorController.showElementMenu()
            }
            .disabled(canvasMode == .fullScript)
            Button("元素格式设置…", systemImage: "slider.horizontal.3") {
                showingElementSettings = true
            }
        } label: {
            HStack(spacing: 8) {
                Text("元素：")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(cursorContext.elementName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 174, minHeight: 34)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel("当前行元素")
        .accessibilityValue(cursorContext.elementName)
        .frame(minWidth: 190, minHeight: 36)
        .padding(.horizontal, 8)
        .background(
            StudioTheme.mint.opacity(0.14),
            in: RoundedRectangle(cornerRadius: 11)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(StudioTheme.mint.opacity(0.42), lineWidth: 1)
        }
        .help("当前光标位于第 \(cursorContext.paragraphIndex + 1) 段·\(cursorContext.elementName)；Return 后默认为\(cursorContext.nextElementName)")
    }

    private var fileMenu: some View {
        Menu {
            Section("视图") {
                Button(
                    showingRuler ? "隐藏标尺" : "显示标尺",
                    systemImage: "ruler"
                ) {
                    showingRuler.toggle()
                }
            }
            Button("导入 Fountain…", systemImage: "square.and.arrow.down") {
                commitSceneDraft()
                isImporting = true
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .help("更多")
    }

    private var editorBody: some View {
        Group {
            switch canvasMode {
            case .scene:
                scriptCanvas
            case .fullScript:
                fullScriptCanvas
            }
        }
            .animatedStoryBubble(tint: StudioTheme.accent, cornerRadius: 34)
    }

    private var workspaceContent: some View {
        scriptCanvas
    }

    private var sceneNavigator: some View {
        VStack(spacing: 0) {
            HStack {
                Text("场景导航器")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(sceneItems.count) 场")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)

            Divider()

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(sceneItems) { item in
                        sceneButton(item)
                    }
                }
                .padding(.vertical, 5)
            }
        }
        .background(ScreenplayEditorPalette.chrome.opacity(0.88))
    }

    private func sceneButton(
        _ item: ScreenplaySceneWorkspaceItem
    ) -> some View {
        let scene = item.snapshot
        let selected = item.id == workspaceState?.activeSceneID
        let metadata = workspaceState?.sceneMetadata(at: scene.index)
            ?? ScreenplaySceneMetadata(
                sceneID: item.id,
                sceneIndex: scene.index
            )

        return Button {
            selectScene(id: item.id)
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Text("\(scene.index + 1)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(selected ? StudioTheme.mint : .secondary)
                    .frame(width: 24, alignment: .trailing)

                VStack(alignment: .leading, spacing: 3) {
                    Text(scene.heading)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(2)
                    Text(scene.summary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Label(
                        "\(metadata.status.rawValue) · \(scene.estimatedPages) 页",
                        systemImage: metadata.status.systemImage
                    )
                    .font(.system(size: 10.5))
                    .foregroundStyle(
                        metadata.status == .approved
                            ? StudioTheme.mint
                            : Color.secondary
                    )
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? Color.white.opacity(0.07) : Color.clear
            )
            .overlay(alignment: .leading) {
                if selected {
                    Rectangle()
                        .fill(StudioTheme.mint)
                        .frame(width: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("编辑场景标题…", systemImage: "pencil") {
                beginEditingSceneHeading(item)
            }
        }
    }

    private var sceneOverview: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(sceneItems) { item in
                    sceneOverviewRow(item)
                }
            }
            .padding(18)
        }
        .background(ScreenplayEditorPalette.workspace)
    }

    private func sceneOverviewRow(
        _ item: ScreenplaySceneWorkspaceItem
    ) -> some View {
        let scene = item.snapshot
        let components = FountainParser.sceneHeadingComponents(scene.heading)
        let metadata = workspaceState?.sceneMetadata(at: scene.index)
            ?? ScreenplaySceneMetadata(
                sceneID: item.id,
                sceneIndex: scene.index
            )
        let selected = item.id == workspaceState?.activeSceneID

        return VStack(alignment: .leading, spacing: 9) {
            Button {
                selectScene(id: item.id)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(String(format: "%02d", scene.index + 1))
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(selected ? StudioTheme.mint : .secondary)
                    Text(scene.heading)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(scene.estimatedPages) 页")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(
                        ChineseScreenplayTiming.formattedDuration(
                            scene.estimatedDurationSeconds
                        )
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(scene.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 7) {
                sceneBadge(components?.locationKind.rawValue ?? "未标注")
                sceneBadge(components?.locationName ?? "未定地点")
                sceneBadge(components?.timeOfDay ?? "未标注")
                if !scene.characterNames.isEmpty {
                    sceneBadge(scene.characterNames.joined(separator: "、"))
                }
                Spacer()
                Menu(metadata.status.rawValue) {
                    ForEach(ScreenplaySceneStatus.allCases) { status in
                        Button(status.rawValue) {
                            updateSceneStatus(
                                item,
                                status: status
                            )
                        }
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(
            selected ? Color.white.opacity(0.09) : Color.white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    selected ? StudioTheme.mint.opacity(0.75) : Color.white.opacity(0.08),
                    lineWidth: selected ? 1.5 : 1
                )
        }
        .contextMenu {
            Button("编辑场景标题…", systemImage: "pencil") {
                beginEditingSceneHeading(item)
            }
        }
    }

    private var sceneCardBoard: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: 250, maximum: 360),
                        spacing: 12
                    )
                ],
                spacing: 12
            ) {
                ForEach(sceneItems) { item in
                    sceneCard(item)
                }
            }
            .padding(18)
        }
        .background(ScreenplayEditorPalette.workspace)
    }

    private func sceneCard(
        _ item: ScreenplaySceneWorkspaceItem
    ) -> some View {
        let scene = item.snapshot
        let metadata = workspaceState?.sceneMetadata(at: scene.index)
            ?? ScreenplaySceneMetadata(
                sceneID: item.id,
                sceneIndex: scene.index
            )
        let selected = item.id == workspaceState?.activeSceneID

        return Button {
            selectScene(id: item.id)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("第 \(scene.index + 1) 场")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(selected ? StudioTheme.mint : .secondary)
                    Spacer()
                    Label(
                        metadata.status.rawValue,
                        systemImage: metadata.status.systemImage
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Text(scene.heading)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(scene.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .frame(maxHeight: .infinity, alignment: .top)
                Divider()
                HStack {
                    Label(
                        "\(scene.characterNames.count) 人",
                        systemImage: "person.2"
                    )
                    Spacer()
                    Text(
                        ChineseScreenplayTiming.formattedDuration(
                            scene.estimatedDurationSeconds
                        )
                    )
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
            .contentShape(Rectangle())
            .background(
                selected ? Color.white.opacity(0.10) : Color.white.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        selected ? StudioTheme.mint : Color.white.opacity(0.10),
                        lineWidth: selected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("编辑场景标题…", systemImage: "pencil") {
                beginEditingSceneHeading(item)
            }
        }
    }

    private func sceneBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.06), in: Capsule())
            .lineLimit(1)
    }

    private func updateSceneStatus(
        _ item: ScreenplaySceneWorkspaceItem,
        status: ScreenplaySceneStatus
    ) {
        guard let state = workspaceState else { return }
        state.updateScene(at: item.snapshot.index) {
            $0.sceneID = item.id
            $0.status = status
        }
        savePendingChanges()
    }

    private func beginEditingSceneHeading(
        _ item: ScreenplaySceneWorkspaceItem
    ) {
        editingSceneHeading = ScreenplaySceneHeadingEditRequest(
            id: item.id,
            heading: item.snapshot.heading
        )
    }

    private func sceneControls(_ state: ScreenplayWorkspaceState) -> some View {
        let metadata = state.sceneMetadata(at: activeIndex)
        return VStack(alignment: .leading, spacing: 8) {
            Text("当前场景")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
            Picker(
                "状态",
                selection: Binding(
                    get: { metadata.status },
                    set: { value in
                        state.updateScene(at: activeIndex) { $0.status = value }
                        savePendingChanges()
                    }
                )
            ) {
                ForEach(ScreenplaySceneStatus.allCases) { status in
                    Label(status.rawValue, systemImage: status.systemImage)
                        .tag(status)
                }
            }
            Picker(
                "目标长度",
                selection: Binding(
                    get: { metadata.length },
                    set: { value in
                        state.updateScene(at: activeIndex) { $0.length = value }
                        savePendingChanges()
                    }
                )
            ) {
                ForEach(ScreenplaySceneLength.allCases) { length in
                    Text(length.rawValue).tag(length)
                }
            }
        }
        .controlSize(.small)
    }

    private var scriptCanvas: some View {
        VStack(spacing: 0) {
            if showingRuler {
                ScreenplayRulerView()
                    .frame(height: 24)
            }

            FountainTextEditor(
                text: $activeSceneDraft,
                paragraphAssignments: paragraphAssignmentsBinding,
                cursorContext: $cursorContext,
                elementStyles: elementStyles,
                controller: editorController,
                focusSceneIndex: 0,
                zoomScale: zoomScale
            )
            .id(loadedSceneIndex)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .background(ScreenplayEditorPalette.workspace)
    }

    private var fullScriptCanvas: some View {
        ZStack(alignment: .topTrailing) {
            FountainTextEditor(
                text: fullScriptPreviewBinding,
                paragraphAssignments: .constant([]),
                cursorContext: $cursorContext,
                elementStyles: elementStyles,
                controller: editorController,
                focusSceneIndex: activeIndex,
                zoomScale: zoomScale,
                isEditable: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Menu {
                ForEach(sceneItems) { item in
                    Button {
                        selectScene(id: item.id)
                    } label: {
                        if item.snapshot.index == activeIndex {
                            Label(
                                "场 \(item.snapshot.index + 1) · \(item.snapshot.heading)",
                                systemImage: "checkmark"
                            )
                        } else {
                            Text("场 \(item.snapshot.index + 1) · \(item.snapshot.heading)")
                        }
                    }
                }
            } label: {
                Label("全本只读 · 跳到场景", systemImage: "list.number")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .padding(18)
        }
        .padding(12)
        .background(ScreenplayEditorPalette.workspace)
    }

    private var scenePageDivider: some View {
        VStack(spacing: 7) {
            HStack(spacing: 12) {
                Rectangle()
                    .fill(Color.white.opacity(0.16))
                    .frame(height: 1)
                Text("===  第 \(activeIndex + 1) 场结束  ===")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Rectangle()
                    .fill(Color.white.opacity(0.16))
                    .frame(height: 1)
            }

            if activeIndex + 1 < scenes.count {
                Text("下一场按标准连续页流排版")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("全剧结束")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Text("第 \(activeIndex + 1) / \(max(scenes.count, 1)) 场")

            Label(
                hasPendingSave ? "保存中" : "已保存",
                systemImage: hasPendingSave
                    ? "arrow.triangle.2.circlepath"
                    : "checkmark.circle"
            )
            .foregroundStyle(hasPendingSave ? .secondary : StudioTheme.mint)

            Spacer()

            Text(
                "约 \(estimatedPages) 页 · \(ChineseScreenplayTiming.formattedDuration(estimatedDuration))"
            )
                .foregroundStyle(.secondary)

            Slider(value: $zoomScale, in: 0.75...2.0, step: 0.05)
                .frame(width: 76)
            Text("\(Int((zoomScale * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)
        }
        .font(.system(size: 10.5))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .animatedStoryBubble(tint: StudioTheme.sky, cornerRadius: 18)
    }

    private var writingStats: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("写作统计")
                .font(.headline)

            statRow("场景", value: "\(scenes.count) 场")
            statRow("标准页数", value: "约 \(estimatedPages) 页")
            statRow(
                "预计时长",
                value: ChineseScreenplayTiming.formattedDuration(estimatedDuration)
            )
            statRow("有效字数", value: "\(project.screenplayText.count) 字")

            Divider()

            Text("当前第 \(activeIndex + 1) 场")
                .font(.subheadline.weight(.semibold))
            statRow("本场页数", value: "约 \(activeEstimatedPages) 页")
            statRow(
                "本场时长",
                value: ChineseScreenplayTiming.formattedDuration(
                    activeEstimatedSeconds
                )
            )

            Text("中文时长按对白、动作、停顿和转场分别估算；约 350 个有效中文字符对应 1 分钟基准。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 270)
    }

    private func statRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.caption)
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

    private func synchronizeUpstreamScreenplay(
        in state: ScreenplayWorkspaceState,
        forceContractIDs: Set<UUID> = [],
        reloadCurrentScene: Bool = false
    ) {
        let selectedContractID = activeSceneContract?.id
            ?? forceContractIDs.first
        let selectedSceneID = state.activeSceneID
        let previousText = project.screenplayText
        let result = ScreenplayProjectionEngine.synchronize(
            project: project,
            state: state,
            forceContractIDs: forceContractIDs
        )
        pendingUpstreamContractIDs = result.pendingContractIDs

        if result.changed {
            if !result.replacedPlaceholder,
               !previousText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.addRevision(
                    title: "同步前序场景前",
                    fountainText: previousText
                )
            }
            lastCommittedFullText = result.text
            project.screenplayText = result.text
            DramaticProjectionEngine.markAllStale(in: project)
            project.touch()
        }

        let refreshedScenes = refreshSceneCache(from: project.screenplayText)
        synchronizedSceneRecords = state.reconcileScenes(refreshedScenes)
        bindSceneContractsIfNeeded(in: state)

        if reloadCurrentScene, !refreshedScenes.isEmpty {
            let targetOrder = selectedContractID.flatMap { contractID in
                synchronizedSceneRecords.first {
                    $0.sceneContractID == contractID
                }?.order
            } ?? selectedSceneID.flatMap { sceneID in
                synchronizedSceneRecords.first { $0.id == sceneID }?.order
            } ?? min(activeIndex, refreshedScenes.count - 1)
            loadScene(at: targetOrder)
        }
        savePendingChanges()
    }

    private func synchronizeSceneRecords() {
        let snapshots = refreshSceneCache(from: project.screenplayText)
        synchronizeSceneRecords(using: snapshots)
    }

    private func synchronizeSceneRecords(
        using snapshots: [FountainSceneSnapshot]
    ) {
        guard let state = ensureWorkspaceState() else { return }
        synchronizedSceneRecords = state.reconcileScenes(
            snapshots
        )
        savePendingChanges()
    }

    private func bindSceneContractsIfNeeded(
        in state: ScreenplayWorkspaceState
    ) {
        guard !orderedSceneContracts.isEmpty else { return }
        var records = state.sceneRecords
        let validContractIDs = Set(orderedSceneContracts.map(\.id))

        for index in records.indices {
            if let contractID = records[index].sceneContractID,
               !validContractIDs.contains(contractID) {
                records[index].sceneContractID = nil
            }
        }

        var claimedIDs = Set(records.compactMap(\.sceneContractID))
        for recordIndex in records.indices
        where records[recordIndex].sceneContractID == nil {
            let matches = orderedSceneContracts.filter {
                !claimedIDs.contains($0.id)
                    && canonicalSceneHeading($0.heading)
                        == canonicalSceneHeading(records[recordIndex].heading)
            }
            if matches.count == 1, let match = matches.first {
                records[recordIndex].sceneContractID = match.id
                claimedIDs.insert(match.id)
            }
        }

        // Initial skeletons have one parsed scene per contract. Position is
        // used only once to migrate records whose headings are not unique.
        if records.count == orderedSceneContracts.count {
            for contract in orderedSceneContracts
            where !claimedIDs.contains(contract.id) {
                guard let recordIndex = records.firstIndex(where: {
                    $0.order == contract.sceneIndex - 1
                        && $0.sceneContractID == nil
                }) else { continue }
                records[recordIndex].sceneContractID = contract.id
                claimedIDs.insert(contract.id)
            }
        }

        state.sceneRecords = records
        synchronizedSceneRecords = records.sorted { $0.order < $1.order }
        savePendingChanges()
    }

    private func canonicalSceneHeading(_ value: String) -> String {
        (FountainParser.localizedSceneHeading(value) ?? value)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { !$0.isWhitespace }
    }

    private func selectSceneContract(_ contract: SceneContract) {
        commitSceneDraft()
        guard let record = synchronizedSceneRecords.first(where: {
            $0.sceneContractID == contract.id
        }) else {
            present(ScreenplayTreeError.sceneLinkMissing)
            return
        }
        guard let state = ensureWorkspaceState() else { return }
        state.activeSceneIndex = record.order
        state.activeSceneID = record.id
        state.updatedAt = .now
        showingSceneBeatPlanner = true
        savePendingChanges()
        loadScene(at: record.order)
    }

    private func selectScene(id: UUID) {
        guard let record = synchronizedSceneRecords.first(where: {
            $0.id == id
        }) else {
            return
        }
        selectScene(record.order)
    }

    private func selectScene(_ index: Int) {
        let targetID = synchronizedSceneRecords.first {
            $0.order == index
        }?.id
        if index == loadedSceneIndex,
           targetID == workspaceState?.activeSceneID {
            return
        }
        sceneDraftSaveTask?.cancel()
        commitSceneDraft()

        guard let state = ensureWorkspaceState() else { return }
        let resolvedIndex = targetID.flatMap { id in
            synchronizedSceneRecords.first { $0.id == id }?.order
        } ?? index
        state.activeSceneIndex = resolvedIndex
        state.activeSceneID = targetID
        state.updatedAt = .now
        savePendingChanges()
        loadScene(at: resolvedIndex)
    }

    private func loadScene(at requestedIndex: Int) {
        let snapshots = cachedScenes.isEmpty
            ? refreshSceneCache(from: project.screenplayText)
            : cachedScenes
        guard !snapshots.isEmpty else {
            loadedSceneIndex = -1
            activeSceneDraft = ""
            refreshActiveMetrics(for: "")
            lastSavedSceneDraft = ""
            hasPendingSave = false
            return
        }

        let index = min(max(requestedIndex, 0), snapshots.count - 1)
        loadedSceneIndex = index
        activeSceneDraft = snapshots[index].text
        refreshActiveMetrics(for: snapshots[index].text)
        lastSavedSceneDraft = snapshots[index].text
        hasPendingSave = false

        if workspaceState?.activeSceneIndex != index {
            workspaceState?.activeSceneIndex = index
        }
        workspaceState?.activeSceneID = synchronizedSceneRecords.first {
            $0.order == index
        }?.id
        workspaceState?.updatedAt = .now
        savePendingChanges()
    }

    private func scheduleSceneSave() {
        sceneDraftSaveTask?.cancel()
        hasPendingSave = true
        let expectedIndex = loadedSceneIndex
        let expectedDraft = activeSceneDraft

        sceneDraftSaveTask = Task { @MainActor in
            // Full-script replacement, scene reconciliation, and SwiftData
            // persistence happen only after a genuine typing pause. Explicit
            // navigation and commands still flush immediately.
            try? await Task.sleep(for: .milliseconds(1_200))
            guard !Task.isCancelled,
                  loadedSceneIndex == expectedIndex,
                  activeSceneDraft == expectedDraft else {
                return
            }
            commitSceneDraft()
        }
    }

    private func commitSceneDraft() {
        guard loadedSceneIndex >= 0 else { return }
        sceneDraftSaveTask?.cancel()
        sceneDraftSaveTask = nil

        let liveDraft = canvasMode == .scene
            ? (editorController.flushEditing() ?? activeSceneDraft)
            : activeSceneDraft
        if liveDraft != activeSceneDraft {
            activeSceneDraft = liveDraft
            refreshActiveMetrics(for: liveDraft)
        }
        let snapshots = cachedScenes.isEmpty
            ? refreshSceneCache(from: project.screenplayText)
            : cachedScenes
        guard snapshots.indices.contains(loadedSceneIndex) else { return }

        let newValue = liveDraft
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let oldValue = snapshots[loadedSceneIndex].text
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard newValue != oldValue else {
            lastSavedSceneDraft = activeSceneDraft
            hasPendingSave = false
            return
        }

        guard let state = ensureWorkspaceState() else { return }
        let selectedID = state.activeSceneID
            ?? synchronizedSceneRecords.first {
                $0.order == loadedSceneIndex
            }?.id
        let updatedText = FountainParser.replacingScene(
            at: loadedSceneIndex,
            in: project.screenplayText,
            with: newValue
        )
        lastCommittedFullText = updatedText
        project.screenplayText = updatedText
        project.touch()
        if let selectedID {
            DramaticProjectionEngine.markSceneStale(
                sceneRecordID: selectedID,
                in: project
            )
            semanticMessage = "正文已保存；旧语义证据已失效。"
        }
        let updatedScenes = refreshSceneCache(from: updatedText)
        synchronizedSceneRecords = state.reconcileScenes(
            updatedScenes
        )
        let savedIndex = selectedID.flatMap { id in
            synchronizedSceneRecords.first { $0.id == id }?.order
        } ?? min(
            loadedSceneIndex,
            max(synchronizedSceneRecords.count - 1, 0)
        )
        state.activeSceneID = synchronizedSceneRecords.first {
            $0.order == savedIndex
        }?.id
        state.activeSceneIndex = savedIndex
        loadedSceneIndex = savedIndex
        let savedDraft = updatedScenes
            .first { $0.index == savedIndex }?
            .text ?? liveDraft
        activeSceneDraft = savedDraft
        refreshActiveMetrics(for: savedDraft)
        lastSavedSceneDraft = savedDraft
        hasPendingSave = false
        do {
            try ProjectPersistenceStore.transaction(in: modelContext) {
                StoryCompiler.updateFindings(project: project, in: modelContext)
            }
        } catch {
            present(error)
            return
        }
        if aiSettings.automaticallyAnalyzeDramaticUpdates {
            analyzeCurrentScene(commitFirst: false)
        }
    }

    private func insert(_ type: FountainElementType) {
        let snippet: String
        switch type {
        case .sceneHeading: snippet = "内. 地点 - 日\n\n"
        case .action: snippet = "一个可见的动作改变了局面。\n\n"
        case .character: snippet = "@人物名\n"
        case .parenthetical: snippet = "（压低声音）\n"
        case .dialogue: snippet = "对白。\n\n"
        case .transition: snippet = "CUT TO:\n\n"
        case .note: snippet = "[[写作注释]]\n"
        }
        let separator = activeSceneDraft.hasSuffix("\n") ? "" : "\n\n"
        activeSceneDraft += separator + snippet
    }

    private var elementStylesBinding: Binding<[ScreenplayElementStyleDefinition]> {
        Binding(
            get: {
                workspaceState?.elementStyles
                    ?? ScreenplayElementStyleDefinition.defaultStyles
            },
            set: { styles in
                guard let state = ensureWorkspaceState() else { return }
                state.elementStyles = styles
                savePendingChanges()
            }
        )
    }

    private var canvasModeBinding: Binding<ScreenplayCanvasMode> {
        Binding(
            get: { canvasMode },
            set: { mode in
                guard mode != canvasMode else { return }
                if mode == .fullScript {
                    commitSceneDraft()
                } else {
                    loadScene(at: activeIndex)
                }
                canvasMode = mode
            }
        )
    }

    private var fullScriptPreviewBinding: Binding<String> {
        Binding(
            get: {
                FountainParser.standardizingSceneFlow(
                    in: committedScreenplayText
                )
            },
            set: { _ in }
        )
    }

    private var paragraphAssignmentsBinding:
        Binding<[ScreenplayParagraphElementAssignment]> {
        Binding(
            get: {
                workspaceState?
                    .sceneMetadata(at: activeIndex)
                    .paragraphElementAssignments ?? []
            },
            set: { assignments in
                guard let state = ensureWorkspaceState() else { return }
                state.updateScene(at: activeIndex) {
                    $0.paragraphElementAssignments = assignments
                }
            }
        )
    }

    private func openAIPanel() {
        commitSceneDraft()
        showingAIPanel = true
    }

    private func importFountain(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            let imported = try String(contentsOf: url, encoding: .utf8)
            let localizedImported = FountainParser.localizingSceneHeadings(
                in: imported
            )
            commitSceneDraft()
            guard let state = ensureWorkspaceState() else { return }
            state.addRevision(
                title: "导入前版本",
                fountainText: project.screenplayText
            )
            project.screenplayText = localizedImported
            DramaticProjectionEngine.markAllStale(in: project)
            let importedScenes = refreshSceneCache(from: localizedImported)
            synchronizedSceneRecords = state.reconcileScenes(importedScenes)
            state.activeSceneIndex = 0
            state.activeSceneID = synchronizedSceneRecords.first?.id
            project.touch()
            lastCommittedFullText = localizedImported
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            loadScene(at: 0)
        } catch {
            present(error)
        }
    }

    private func applyBulkEdit(
        _ updatedText: String,
        revisionTitle: String
    ) {
        commitSceneDraft()
        guard updatedText != project.screenplayText else { return }
        guard let state = ensureWorkspaceState() else { return }
        let selectedID = state.activeSceneID
        state.addRevision(
            title: revisionTitle,
            fountainText: project.screenplayText
        )
        let localized = FountainParser.localizingSceneHeadings(in: updatedText)
        project.screenplayText = localized
        DramaticProjectionEngine.markAllStale(in: project)
        lastCommittedFullText = localized
        project.touch()
        let editedScenes = refreshSceneCache(from: localized)
        synchronizedSceneRecords = state.reconcileScenes(editedScenes)
        let targetIndex = selectedID.flatMap { id in
            synchronizedSceneRecords.first { $0.id == id }?.order
        } ?? min(activeIndex, max(synchronizedSceneRecords.count - 1, 0))
        state.activeSceneIndex = targetIndex
        state.activeSceneID = synchronizedSceneRecords.first {
            $0.order == targetIndex
        }?.id
        savePendingChanges()
        loadScene(at: targetIndex)
    }

    private func renameSceneHeading(
        sceneID: UUID,
        heading: String
    ) {
        commitSceneDraft()
        guard let record = synchronizedSceneRecords.first(where: {
            $0.id == sceneID
        }) else {
            return
        }
        let updated = FountainParser.replacingSceneHeading(
            at: record.order,
            in: project.screenplayText,
            with: heading
        )
        applyBulkEdit(
            updated,
            revisionTitle: "修改场景标题前"
        )
    }

    private func applySceneBeatsToScreenplay(_ contract: SceneContract) {
        do {
            commitSceneDraft()
            let sceneText = try SceneBeatMappingEngine.screenplayScene(for: contract)
            guard let state = ensureWorkspaceState() else { return }
            guard let linkedRecord = synchronizedSceneRecords.first(where: {
                $0.sceneContractID == contract.id
            }) else {
                throw ScreenplayTreeError.sceneLinkMissing
            }
            let screenplayOrder = linkedRecord.order
            state.addRevision(
                title: "串联场 \(contract.sceneIndex) 情境更新前",
                fountainText: project.screenplayText
            )
            let updated = FountainParser.replacingScene(
                at: screenplayOrder,
                in: project.screenplayText,
                with: sceneText
            )
            project.screenplayText = updated
            DramaticProjectionEngine.markSceneStale(
                sceneRecordID: linkedRecord.id,
                in: project
            )
            project.touch()
            lastCommittedFullText = updated
            let refreshed = refreshSceneCache(from: updated)
            synchronizedSceneRecords = state.reconcileScenes(refreshed)
            bindSceneContractsIfNeeded(in: state)

            let nextContract = orderedSceneContracts.first {
                !$0.areMicroBeatsConfirmed
            }
            let targetRecord = nextContract.flatMap { next in
                synchronizedSceneRecords.first { $0.sceneContractID == next.id }
            } ?? synchronizedSceneRecords.first {
                $0.sceneContractID == contract.id
            }
            guard let targetRecord else {
                throw ScreenplayTreeError.sceneLinkMissing
            }
            state.activeSceneIndex = targetRecord.order
            state.activeSceneID = targetRecord.id
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            loadScene(at: state.activeSceneIndex)
            showingSceneBeatPlanner = false
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
    }

    private func savePendingChanges() {
        do {
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
        } catch {
            present(error)
        }
    }

    @discardableResult
    private func refreshSceneCache(
        from text: String
    ) -> [FountainSceneSnapshot] {
        let snapshots = FountainParser.scenes(in: text)
        if snapshots != cachedScenes {
            cachedScenes = snapshots
        }
        return snapshots
    }

    private func refreshActiveMetrics(for text: String) {
        let seconds = ChineseScreenplayTiming.estimatedSeconds(in: text)
        let lineCount = max(text.components(separatedBy: .newlines).count, 1)
        let linePages = Int(ceil(Double(lineCount) / 54.0))
        let durationPages = Int(ceil(max(seconds, 1) / 60.0))
        cachedActiveEstimatedSeconds = seconds
        cachedActiveEstimatedPages = max(1, max(linePages, durationPages))
    }

    private func analyzeCurrentScene() {
        analyzeCurrentScene(commitFirst: true)
    }

    private func analyzeCurrentScene(commitFirst: Bool) {
        guard !isAnalyzingSemantics else { return }
        if commitFirst { commitSceneDraft() }
        guard let record = activeSceneRecord else {
            semanticMessage = "当前场景还没有稳定标识，无法安全挂接语义证据。"
            return
        }
        let sceneText = activeSceneDraft.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !sceneText.isEmpty else {
            semanticMessage = "当前场景没有可分析的正文。"
            return
        }
        let contract = activeSceneContract
        let fingerprint = ScreenplayReviewEngine.fingerprint(sceneText)
        let durations: [UUID: Double] = Dictionary(
            uniqueKeysWithValues: synchronizedSceneRecords.compactMap { item in
                guard scenes.indices.contains(item.order) else { return nil }
                let seconds = item.order == loadedSceneIndex
                    ? activeEstimatedSeconds
                    : scenes[item.order].estimatedDurationSeconds
                return (item.id, seconds)
            }
        )

        isAnalyzingSemantics = true
        semanticWarnings = []
        semanticMessage = "正在辨认不可再分的情境更新…"
        Task { @MainActor in
            defer { isAnalyzingSemantics = false }
            do {
                let analysis = try await DramaticSemanticEngine.analyze(
                    sceneText: sceneText,
                    sceneContract: contract,
                    project: project,
                    settings: aiSettings
                )
                guard fingerprint == ScreenplayReviewEngine.fingerprint(activeSceneDraft),
                      activeSceneRecord?.id == record.id else {
                    semanticWarnings = ["分析期间正文或当前场景发生变化，本次结果已丢弃以避免错挂。"]
                    semanticMessage = "请重新分析当前版本。"
                    return
                }
                let saved = try DramaticProjectionEngine.apply(
                    analysis,
                    sceneText: sceneText,
                    sceneRecordID: record.id,
                    sceneContract: contract,
                    durationSeconds: activeEstimatedSeconds,
                    sceneDurations: durations,
                    project: project,
                    context: modelContext
                )
                semanticWarnings = analysis.warnings
                semanticMessage = saved.isEmpty
                    ? "本场没有辨认出有效情境更新。"
                    : "已建立 \(saved.count) 次情境更新，并重算全部向上投影。"
            } catch {
                semanticWarnings = [error.localizedDescription]
                semanticMessage = "情境更新分析失败。"
            }
        }
    }

    private func toggleDramaticUpdateLock(_ update: DramaticUpdateRecord) {
        update.status = update.status == .locked ? .confirmed : .locked
        update.origin = .authored
        update.updatedAt = .now
        DramaticProjectionEngine.refresh(
            project: project,
            sceneDurations: Dictionary(
                uniqueKeysWithValues: synchronizedSceneRecords.compactMap { item in
                    guard scenes.indices.contains(item.order) else { return nil }
                    return (item.id, scenes[item.order].estimatedDurationSeconds)
                }
            ),
            context: modelContext
        )
        savePendingChanges()
    }
}

private enum ScreenplayTreeError: LocalizedError {
    case sceneLinkMissing

    var errorDescription: String? {
        switch self {
        case .sceneLinkMissing:
            "当前剧本文本与故事树中的场景无法安全对应。请返回场景工作台检查场景数量，避免覆盖错误场景。"
        }
    }
}

private struct ScreenplayRulerView: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...8, id: \.self) { inch in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 1, height: 8)
                    Text("\(inch)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 3)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 7)
        .background(ScreenplayEditorPalette.chrome)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(height: 1)
        }
        .accessibilityLabel("剧本页面标尺")
    }
}
