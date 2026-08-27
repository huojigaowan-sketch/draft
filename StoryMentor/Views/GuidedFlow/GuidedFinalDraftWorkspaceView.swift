import SwiftData
import SwiftUI

struct GuidedFinalDraftWorkspaceView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(AISettingsStore.self) private var settings
  @Query(sort: \GuidedFlowSession.updatedAt, order: .reverse)
  private var storedSessions: [GuidedFlowSession]
  @Query private var workspaceStates: [ScreenplayWorkspaceState]

  @Bindable var project: StoryProject
  let onNavigate: (WorkspaceSection) -> Void

  @State private var activeSession: GuidedFlowSession?
  @State private var isWorking = false
  @State private var lastEcho: GuidedScreenplayCompileEcho?
  @State private var showingEcho = false
  @State private var pendingNextContractID: UUID?
  @State private var errorMessage = ""
  @State private var showingError = false

  private var workspaceState: ScreenplayWorkspaceState? {
    workspaceStates
      .filter { $0.projectID == project.id }
      .max { $0.updatedAt < $1.updatedAt }
  }

  private var snapshot: GuidedScreenplayCompletionSnapshot? {
    guard let activeSession else { return nil }
    return GuidedScreenplayObligationEngine.snapshot(
      project: project,
      session: activeSession,
      workspaceState: workspaceState
    )
  }

  private var prompt: GuidedScreenplayPrompt? {
    guard let snapshot else { return nil }
    return GuidedScreenplayObligationEngine.prompt(
      snapshot: snapshot,
      project: project
    )
  }

  var body: some View {
    ZStack {
      StudioCanvas()

      if let session = activeSession {
        if !project.hasSelectedStructureTemplate || !project.isStructureLocked {
          GuidedStructureSelectionView(project: project) { template, scale in
            selectStructure(
              template,
              scale: scale,
              session: session
            )
          }
        } else {
          editorWorkspace(session)
        }
      } else {
        ProgressView("正在恢复正式剧本与完成地图…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .task(id: project.id) {
      prepareSession()
    }
    .onChange(of: snapshot?.nextObligation?.id) { _, _ in
      focusCurrentObligation()
    }
    .alert("本轮暂时无法完成", isPresented: $showingError) {
      Button("好", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  private func editorWorkspace(
    _ session: GuidedFlowSession
  ) -> some View {
    ZStack(alignment: .topTrailing) {
      VStack(spacing: 0) {
        if let snapshot, let prompt {
          guidedPromptBar(
            session: session,
            snapshot: snapshot,
            prompt: prompt
          )
        }

        ScreenplayStudioView(
          project: project,
          onNavigate: onNavigate,
          guidedMode: true
        )
      }

      if showingEcho, let lastEcho {
        creativeEchoPanel(lastEcho)
          .transition(.move(edge: .trailing).combined(with: .opacity))
          .zIndex(4)
      }

      if snapshot?.isComplete == true {
        completedOverlay(session)
          .transition(.opacity.combined(with: .scale(scale: 0.98)))
          .zIndex(6)
      }
    }
    .animation(.spring(response: 0.42, dampingFraction: 0.86), value: showingEcho)
    .animation(.spring(response: 0.46, dampingFraction: 0.88), value: snapshot?.isComplete)
  }

  private func guidedPromptBar(
    session: GuidedFlowSession,
    snapshot: GuidedScreenplayCompletionSnapshot,
    prompt: GuidedScreenplayPrompt
  ) -> some View {
    HStack(spacing: 15) {
      Circle()
        .fill(isWorking ? StudioTheme.warm : StudioTheme.mint)
        .frame(width: 8, height: 8)
        .shadow(
          color: (isWorking ? StudioTheme.warm : StudioTheme.mint).opacity(0.45),
          radius: 5
        )

      VStack(alignment: .leading, spacing: 3) {
        Text(prompt.eyebrow)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
        Text(prompt.title)
          .font(.system(size: 16.5, weight: .semibold, design: .serif))
        Text(prompt.question)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      Spacer(minLength: 12)

      Menu {
        Section("当前命题") {
          Text(prompt.writingDirection)
          Text(prompt.completionHint)
        }
        Divider()
        Section("后台完成地图") {
          ForEach(snapshot.obligations) { obligation in
            Label(
              obligation.title,
              systemImage: obligationIcon(obligation.status)
            )
          }
        }
        Divider()
        Button("打开高级结构编译器", systemImage: "function") {
          onNavigate(.structure)
        }
        Button("打开全本交付检查", systemImage: "checkmark.seal") {
          onNavigate(.delivery)
        }
      } label: {
        Label(
          "\(snapshot.sceneCompleted)/\(max(snapshot.sceneTotal, 1)) 场",
          systemImage: "ellipsis.circle"
        )
        .font(.caption.weight(.semibold))
      }
      .menuStyle(.borderlessButton)
      .help("命题说明与后台完成地图")

      Button {
        completeCurrentObligation(
          session: session,
          snapshot: snapshot,
          prompt: prompt
        )
      } label: {
        if isWorking {
          HStack(spacing: 7) {
            ProgressView().controlSize(.small)
            Text("正在整理当前范围…")
          }
        } else {
          Label(prompt.actionTitle, systemImage: "arrow.right.circle.fill")
        }
      }
      .buttonStyle(.borderedProminent)
      .tint(StudioTheme.mint)
      .controlSize(.large)
      .disabled(isWorking)
      .keyboardShortcut(.return, modifiers: [.command])
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 10)
    .background(.ultraThinMaterial)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(Color.primary.opacity(0.06))
        .frame(height: 1)
    }
  }

  private func creativeEchoPanel(
    _ echo: GuidedScreenplayCompileEcho
  ) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          EyebrowLabel(text: "你的文字已经造成", color: StudioTheme.mint)
          Text(echo.headline)
            .font(.system(size: 21, weight: .semibold, design: .serif))
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
        Button {
          continueAfterEcho()
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
      }

      ScrollView {
        VStack(alignment: .leading, spacing: 13) {
          ForEach(echo.findings) { finding in
            VStack(alignment: .leading, spacing: 6) {
              Label(
                finding.title,
                systemImage: echoIcon(finding.kind)
              )
              .font(.callout.weight(.semibold))
              .foregroundStyle(StudioTheme.mint)

              Text(finding.effect)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

              Text("“\(finding.evidence)”")
                .font(.callout.italic())
                .foregroundStyle(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                  Color.primary.opacity(0.035),
                  in: RoundedRectangle(cornerRadius: 10)
                )
            }
            .padding(.bottom, 4)
          }

          if !echo.preservedQuotes.isEmpty {
            Divider()
            Text("已原样保留的作者句子")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
            ForEach(echo.preservedQuotes, id: \.self) { quote in
              Label("“\(quote)”", systemImage: "quote.opening")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      }

      Button("继续下一处必要创作", systemImage: "arrow.right") {
        continueAfterEcho()
      }
      .buttonStyle(.borderedProminent)
      .tint(StudioTheme.mint)
      .frame(maxWidth: .infinity)
    }
    .padding(20)
    .frame(width: 390)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(.regularMaterial)
    .overlay(alignment: .leading) {
      Rectangle()
        .fill(StudioTheme.mint.opacity(0.28))
        .frame(width: 1)
    }
    .shadow(color: Color.black.opacity(0.16), radius: 22, x: -6)
  }

  private func completedOverlay(
    _ session: GuidedFlowSession
  ) -> some View {
    let scenes = FountainParser.scenes(in: project.screenplayText)
    let pages = scenes.reduce(0) { $0 + $1.estimatedPages }
    return ZStack {
      Color.black.opacity(0.24)
        .ignoresSafeArea()

      VStack(spacing: 18) {
        Image(systemName: "checkmark.seal.fill")
          .font(.system(size: 44, weight: .light))
          .foregroundStyle(StudioTheme.mint)

        VStack(spacing: 7) {
          Text("你的完整剧本已经完成")
            .font(.system(size: 31, weight: .semibold, design: .serif))
          Text("\(project.structureTemplate.name) · \(scenes.count) 场 · 约 \(pages) 页")
            .font(.callout)
            .foregroundStyle(.secondary)
          Text("全部硬性结构义务、正式场景、Final Draft 元素与阻断检查均已完成。")
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }

        HStack(spacing: 11) {
          Button("继续阅读与润色", systemImage: "text.book.closed.fill") {
            session.invalidateCompletedScreenplayApproval()
            saveSilently()
          }
          .buttonStyle(.bordered)

          Button("进入交付与导出", systemImage: "square.and.arrow.up") {
            onNavigate(.delivery)
          }
          .buttonStyle(.borderedProminent)
          .tint(StudioTheme.mint)
        }
      }
      .padding(.horizontal, 42)
      .padding(.vertical, 36)
      .frame(maxWidth: 650)
      .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 44, isSelected: true)
    }
  }

  private func prepareSession() {
    let session = storedSessions.first { $0.projectID == project.id }
      ?? GuidedFlowSession(
        projectID: project.id,
        phase: .structure
      )
    if !storedSessions.contains(where: { $0.id == session.id }) {
      modelContext.insert(session)
    }
    activeSession = session

    do {
      if project.isStructureLocked && project.hasSelectedStructureTemplate {
        try GuidedScreenplayObligationEngine.bootstrapSceneSlotsIfNeeded(
          project: project,
          session: session,
          modelContext: modelContext
        )
      }
      try ProjectPersistenceStore.savePendingChanges(in: modelContext)
      focusCurrentObligation()
    } catch {
      present(error)
    }
  }

  private func selectStructure(
    _ template: StoryStructureTemplate,
    scale: GuidedScriptScale,
    session: GuidedFlowSession
  ) {
    do {
      try GuidedScreenplayObligationEngine.selectStructure(
        template: template,
        scale: scale,
        project: project,
        session: session,
        modelContext: modelContext
      )
      focusCurrentObligation()
    } catch {
      present(error)
    }
  }

  private func completeCurrentObligation(
    session: GuidedFlowSession,
    snapshot: GuidedScreenplayCompletionSnapshot,
    prompt: GuidedScreenplayPrompt
  ) {
    guard let obligation = snapshot.nextObligation else { return }

    if obligation.kind == .authorApproval {
      session.approveCompletedScreenplay(
        fingerprint: snapshot.screenplayFingerprint
      )
      saveSilently()
      return
    }

    if obligation.kind == .screenplayReview,
       obligation.sceneContractID == nil {
      guard let state = workspaceState else {
        errorMessage = "正式剧本工作区仍在准备。请稍候再检查全本。"
        showingError = true
        return
      }
      GuidedScreenplayObligationEngine.refreshReviews(
        state: state,
        project: project
      )
      session.invalidateCompletedScreenplayApproval()
      saveSilently()
      focusCurrentObligation()
      return
    }

    guard let contractID = prompt.targetSceneContractID,
          let contract = project.sceneContracts.first(where: {
            $0.id == contractID
          }) else {
      errorMessage = "当前命题没有找到对应的正式场景。"
      showingError = true
      return
    }

    NotificationCenter.default.post(
      name: .guidedFlowCommitScreenplay,
      object: project.id
    )

    Task { @MainActor in
      isWorking = true
      defer { isWorking = false }
      try? await Task.sleep(for: .milliseconds(320))

      do {
        let source = GuidedScreenplayObligationEngine.sceneText(
          for: contract,
          in: project
        )
        let visibleBody = FountainParser.paragraphs(in: source)
          .dropFirst()
          .contains { !$0.trimmedText.isEmpty }
        guard visibleBody else {
          throw GuidedFinalDraftWorkspaceError.emptyScene
        }

        let stageIndex = contract.structureStageIndex ?? 0
        guard project.structureTemplate.stages.indices.contains(stageIndex) else {
          throw GuidedFinalDraftWorkspaceError.structureStageMissing
        }
        let stage = project.structureTemplate.stages[stageIndex]
        let result: GuidedSceneCompilationResult
        if settings.hasAPIKey {
          result = try await GuidedFinalDraftCompilerEngine(
            settings: settings
          ).compile(
            sourceScene: source,
            contract: contract,
            stage: stage,
            project: project,
            scale: session.guidedScriptScale
          )
        } else {
          result = try GuidedFinalDraftCompilerEngine.localResult(
            sourceScene: source,
            contract: contract,
            stage: stage
          )
        }

        try GuidedFinalDraftProjectWriter.apply(
          result,
          sourceScene: source,
          contract: contract,
          project: project,
          session: session,
          workspaceState: workspaceState,
          modelContext: modelContext
        )

        let echo = GuidedScreenplayCompileEcho(
          sceneContractID: contract.id,
          headline: result.echoHeadline,
          findings: result.echoFindings,
          preservedQuotes: result.preservedQuotes
        )
        lastEcho = echo
        showingEcho = true

        let refreshed = GuidedScreenplayObligationEngine.snapshot(
          project: project,
          session: session,
          workspaceState: workspaceState
        )
        if refreshed.sceneTotal > 0,
           refreshed.sceneCompleted == refreshed.sceneTotal,
           let state = workspaceState {
          GuidedScreenplayObligationEngine.refreshReviews(
            state: state,
            project: project
          )
          try ProjectPersistenceStore.savePendingChanges(in: modelContext)
        }
        let finalSnapshot = GuidedScreenplayObligationEngine.snapshot(
          project: project,
          session: session,
          workspaceState: workspaceState
        )
        pendingNextContractID = finalSnapshot.nextObligation?.sceneContractID
      } catch {
        present(error)
      }
    }
  }

  private func continueAfterEcho() {
    showingEcho = false
    lastEcho = nil
    if let pendingNextContractID {
      project.requestedSceneContractID = pendingNextContractID
      self.pendingNextContractID = nil
    } else {
      focusCurrentObligation()
    }
  }

  private func focusCurrentObligation() {
    guard let snapshot else { return }
    let target = GuidedScreenplayObligationEngine.targetContract(
      for: snapshot,
      project: project
    )
    if let target {
      project.requestedSceneContractID = target.id
    }
  }

  private func obligationIcon(
    _ status: GuidedScreenplayObligationStatus
  ) -> String {
    switch status {
    case .pending: "circle"
    case .active: "circle.dashed"
    case .satisfied: "checkmark.circle.fill"
    case .blocked: "exclamationmark.octagon.fill"
    }
  }

  private func echoIcon(
    _ kind: GuidedScreenplayEchoKind
  ) -> String {
    switch kind {
    case .character: "person.crop.circle.fill"
    case .plot: "arrow.triangle.branch"
    case .relationship: "person.2.fill"
    case .image: "viewfinder"
    case .voice: "quote.bubble.fill"
    case .world: "globe.asia.australia.fill"
    case .structure: "point.3.connected.trianglepath.dotted"
    }
  }

  private func saveSilently() {
    do {
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

enum GuidedFinalDraftWorkspaceError: LocalizedError {
  case emptyScene
  case structureStageMissing

  var errorDescription: String? {
    switch self {
    case .emptyScene:
      "先在当前 Final Draft 场景里写下一些动作、对白或生活细节。写长一点也可以；系统只会整理当前这一场。"
    case .structureStageMissing:
      "当前场景失去了结构锚点。请返回结构选择重新定位。"
    }
  }
}
