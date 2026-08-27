import SwiftData
import SwiftUI

/// The novice-first production path. It deliberately exposes one creative
/// decision at a time and never asks the language model for a whole outline,
/// scene, episode, or screenplay.
struct GuidedFlowWorkspaceView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(AISettingsStore.self) private var settings
  @Query(sort: \GuidedFlowSession.updatedAt, order: .reverse)
  private var storedSessions: [GuidedFlowSession]

  @Bindable var project: StoryProject
  let onNavigate: (WorkspaceSection) -> Void

  @State private var activeSession: GuidedFlowSession?
  @State private var isReviewing = false
  @State private var isRequestingAssist = false
  @State private var errorMessage = ""
  @State private var showingError = false
  @FocusState private var answerIsFocused: Bool

  private var challenge: GuidedFlowChallenge? {
    guard let activeSession else { return nil }
    return GuidedFlowCoordinator.challenge(
      for: activeSession,
      project: project
    )
  }

  var body: some View {
    ZStack {
      StudioCanvas()

      if let session = activeSession {
        if let contribution = session.pendingContribution {
          contributionImpactWorkspace(
            session: session,
            contribution: contribution
          )
        } else if session.phase == .completed {
          completionView(session)
        } else if let challenge {
          challengeWorkspace(session: session, challenge: challenge)
        } else {
          recoveryView(session)
        }
      } else {
        ProgressView("正在找到下一项最小创作决定…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .navigationSplitViewColumnWidth(min: 700, ideal: 980)
    .task(id: project.id) {
      prepareSession()
    }
    .alert("心流引导暂时无法继续", isPresented: $showingError) {
      Button("好", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  private func challengeWorkspace(
    session: GuidedFlowSession,
    challenge: GuidedFlowChallenge
  ) -> some View {
    VStack(spacing: 0) {
      header(session: session, challenge: challenge)
      Divider().opacity(0.45)

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          currentChallengeCard(session: session, challenge: challenge)

          if !challenge.referenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            referenceCard(challenge)
          }

          answerCard(session: session, challenge: challenge)

          if !session.lastFeedback.isEmpty || !session.lastNudge.isEmpty {
            feedbackCard(session: session)
          }

          confirmedTrail(session)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: 960)
        .frame(maxWidth: .infinity)
      }
    }
  }

  private func header(
    session: GuidedFlowSession,
    challenge: GuidedFlowChallenge
  ) -> some View {
    VStack(spacing: 12) {
      HStack(spacing: 14) {
        Image(systemName: session.phase.systemImage)
          .font(.system(size: 22, weight: .semibold))
          .foregroundStyle(StudioTheme.accent)
          .frame(width: 44, height: 44)
          .background(StudioTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))

        VStack(alignment: .leading, spacing: 3) {
          EyebrowLabel(text: "GUIDED FLOW · 一次只做一小步")
          Text(project.title)
            .font(.system(.title2, design: .serif, weight: .semibold))
          Text(phaseStepLabel(session))
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        VStack(alignment: .trailing, spacing: 5) {
          Text(
            GuidedFlowCoordinator.overallProgress(
              session: session,
              project: project
            ),
            format: .percent.precision(.fractionLength(0))
          )
          .font(.caption.monospacedDigit().weight(.bold))
          ProgressView(
            value: GuidedFlowCoordinator.overallProgress(
              session: session,
              project: project
            )
          )
          .tint(StudioTheme.mint)
          .frame(width: 170)
        }

        Menu {
          Button("下一步再简单一点", systemImage: "minus.circle") {
            session.targetStretch = max(0, session.targetStretch - 1)
            session.touch()
            saveSilently()
          }
          Button("保持现在的步幅", systemImage: "equal.circle") {
            session.targetStretch = min(session.targetStretch, 1)
            session.touch()
            saveSilently()
          }
          Button("下一步增加一点挑战", systemImage: "plus.circle") {
            session.targetStretch = min(4, session.targetStretch + 1)
            session.touch()
            saveSilently()
          }
          Divider()
          Button("打开高级结构编译器", systemImage: "function") {
            onNavigate(.structure)
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .help("步幅与高级工具")
      }

      HStack(spacing: 8) {
        phaseChip(.foundation, current: session.phase)
        phaseConnector
        phaseChip(.structure, current: session.phase)
        phaseConnector
        phaseChip(.scene, current: session.phase)
        phaseConnector
        phaseChip(.beat, current: session.phase)
        phaseConnector
        phaseChip(.screenplay, current: session.phase)
      }
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 15)
    .background(.ultraThinMaterial)
  }

  private func phaseChip(
    _ phase: GuidedFlowPhase,
    current: GuidedFlowPhase
  ) -> some View {
    let all: [GuidedFlowPhase] = [.foundation, .structure, .scene, .beat, .screenplay]
    let currentIndex = all.firstIndex(of: current) ?? all.count
    let index = all.firstIndex(of: phase) ?? 0
    let isCurrent = phase == current
    let isDone = index < currentIndex || current == .completed
    return Label(phase.rawValue, systemImage: isDone ? "checkmark.circle.fill" : phase.systemImage)
      .font(.caption.weight(isCurrent ? .bold : .semibold))
      .foregroundStyle(isCurrent ? StudioTheme.accent : (isDone ? StudioTheme.mint : .secondary))
      .padding(.horizontal, 9)
      .padding(.vertical, 6)
      .background(
        isCurrent ? StudioTheme.accent.opacity(0.11) : Color.primary.opacity(0.035),
        in: Capsule()
      )
  }

  private var phaseConnector: some View {
    Image(systemName: "chevron.right")
      .font(.system(size: 8, weight: .bold))
      .foregroundStyle(.tertiary)
  }

  private func currentChallengeCard(
    session: GuidedFlowSession,
    challenge: GuidedFlowChallenge
  ) -> some View {
    StudioCard(padding: 22) {
      VStack(alignment: .leading, spacing: 16) {
        HStack(alignment: .top, spacing: 14) {
          VStack(alignment: .leading, spacing: 5) {
            EyebrowLabel(text: challenge.skill.rawValue, color: StudioTheme.warm)
            Text(challenge.title)
              .font(.system(size: 28, weight: .semibold, design: .serif))
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 12)
          VStack(alignment: .trailing, spacing: 5) {
            PhaseBadge(text: challenge.difficulty.label)
            Text(session.scaffoldLevel.label)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }

        Text(challenge.question)
          .font(.system(size: 20, weight: .medium, design: .rounded))
          .lineSpacing(5)
          .fixedSize(horizontal: false, vertical: true)

        Label(challenge.whyItMatters, systemImage: "arrow.right.circle.fill")
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        HStack(spacing: 8) {
          ForEach(challenge.successContract, id: \.self) { item in
            Text(item)
              .font(.caption2.weight(.semibold))
              .padding(.horizontal, 8)
              .padding(.vertical, 5)
              .background(StudioTheme.mint.opacity(0.08), in: Capsule())
              .foregroundStyle(StudioTheme.mint)
          }
        }
      }
    }
  }

  private func referenceCard(_ challenge: GuidedFlowChallenge) -> some View {
    DisclosureGroup {
      Text(challenge.referenceText)
        .font(.callout)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 9)
    } label: {
      Label("只查看当前一步需要的已确认事实", systemImage: "lock.doc.fill")
        .font(.callout.weight(.semibold))
    }
    .padding(16)
    .animatedStoryBubble(tint: StudioTheme.sky, cornerRadius: 30)
  }

  private func answerCard(
    session: GuidedFlowSession,
    challenge: GuidedFlowChallenge
  ) -> some View {
    let responseMode: GuidedFlowResponseMode =
      challenge.supportsPromptedWriting
      ? session.responseMode
      : .focused
    let maximumCharacters = challenge.maximumCharacters(for: responseMode)
    let isPromptedWriting = responseMode == .promptedWriting

    return StudioCard(padding: 20) {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .center) {
          VStack(alignment: .leading, spacing: 3) {
            EyebrowLabel(
              text: isPromptedWriting ? "你的命题写作" : "你的当前决定",
              color: StudioTheme.mint
            )
            if isPromptedWriting {
              Text("可以像写命题作文一样展开；不需要先懂剧本格式。")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          Spacer()
          Text("\(session.currentDraft.count)/\(maximumCharacters)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(
              session.currentDraft.count > maximumCharacters
                ? Color.red
                : Color.secondary
            )
        }

        if challenge.supportsPromptedWriting {
          HStack(spacing: 12) {
            Picker("回答方式", selection: responseModeBinding(session)) {
              ForEach(GuidedFlowResponseMode.allCases) { mode in
                Label(mode.rawValue, systemImage: mode.systemImage)
                  .tag(mode)
              }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)

            if isPromptedWriting {
              Label("建议 300—1200 字", systemImage: "pencil.line")
                .font(.caption.weight(.semibold))
                .foregroundStyle(StudioTheme.warm)
            }
            Spacer()
          }
        }

        if isPromptedWriting {
          VStack(alignment: .leading, spacing: 8) {
            Label("本轮命题", systemImage: "doc.text.fill")
              .font(.caption.weight(.bold))
              .foregroundStyle(StudioTheme.warm)
            Text(challenge.promptedWritingPrompt)
              .font(.system(size: 17, weight: .medium, design: .serif))
              .lineSpacing(5)
              .fixedSize(horizontal: false, vertical: true)
            Text("可以写动作、对话、回忆、观察和生活细节。系统会保留全文，并从原文中提炼人物、情节、关系与画面。")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding(15)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(StudioTheme.warm.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        }

        if !challenge.options.isEmpty {
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 170), spacing: 9)],
            spacing: 9
          ) {
            ForEach(challenge.options, id: \.self) { option in
              Button {
                applyOption(option, challenge: challenge, session: session)
              } label: {
                Text(option)
                  .font(.callout.weight(.semibold))
                  .frame(maxWidth: .infinity, minHeight: 32)
              }
              .buttonStyle(.bordered)
            }
          }
        }

        TextEditor(text: draftBinding(session))
          .font(
            .system(
              size: isPromptedWriting ? 17 : 16,
              design: isPromptedWriting
                ? .serif
                : (challenge.phase == .beat ? .monospaced : .default)
            )
          )
          .lineSpacing(isPromptedWriting ? 6 : 2)
          .scrollContentBackground(.hidden)
          .frame(
            minHeight: isPromptedWriting
              ? 340
              : (challenge.phase == .beat ? 150 : 105)
          )
          .padding(11)
          .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
          .overlay(alignment: .topLeading) {
            if session.currentDraft.isEmpty {
              Text(
                isPromptedWriting
                  ? challenge.promptedWritingPlaceholder
                  : challenge.placeholder
              )
              .font(.system(size: 15))
              .foregroundStyle(.tertiary)
              .padding(.horizontal, 16)
              .padding(.vertical, 18)
              .allowsHitTesting(false)
            }
          }
          .focused($answerIsFocused)

        HStack(spacing: 10) {
          Button {
            requestSupport(session: session, challenge: challenge)
          } label: {
            if isRequestingAssist {
              HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text(isPromptedWriting ? "正在准备一个写作切口…" : "只准备当前一步的提示…")
              }
            } else {
              Label(
                supportButtonTitle(session, responseMode: responseMode),
                systemImage: "lifepreserver.fill"
              )
            }
          }
          .buttonStyle(.bordered)
          .disabled(isReviewing || isRequestingAssist)

          Spacer()

          if isReviewing {
            HStack(spacing: 8) {
              ProgressView().controlSize(.small)
              Text(isPromptedWriting ? "正在从你的原文中寻找故事材料…" : "只检查当前一步…")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }

          Button {
            submit(session: session, challenge: challenge)
          } label: {
            Label(
              isPromptedWriting ? "提交这篇命题写作" : "确认这一小步",
              systemImage: isPromptedWriting ? "doc.badge.arrow.up.fill" : "arrow.right.circle.fill"
            )
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .tint(StudioTheme.mint)
          .disabled(
            isReviewing
              || isRequestingAssist
              || session.currentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          )
          .keyboardShortcut(.return, modifiers: [.command])
        }

        Text(
          isPromptedWriting
            ? "全文会作为作者原稿原样保存。AI只指出你的文字已经创造了什么，并提炼当前小步；不会用摘要替换原文。"
            : "确认后只写入这一项故事决定；系统不会顺手生成后续大纲或完整场景。"
        )
        .font(.caption2)
        .foregroundStyle(.tertiary)
      }
    }
  }

  private func feedbackCard(session: GuidedFlowSession) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      if !session.lastFeedback.isEmpty {
        Label(session.lastFeedback, systemImage: "scope")
          .font(.callout.weight(.semibold))
          .foregroundStyle(session.awaitingRevision ? StudioTheme.warm : StudioTheme.mint)
          .fixedSize(horizontal: false, vertical: true)
      }
      if !session.lastNudge.isEmpty {
        Text(session.lastNudge)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineSpacing(3)
          .fixedSize(horizontal: false, vertical: true)

        if session.scaffoldLevel == .minimalAssist {
          Button("把这份最小建议放入草稿，再由我修改", systemImage: "arrow.down.doc.fill") {
            session.currentDraft = session.lastNudge
            session.touch()
            answerIsFocused = true
          }
          .buttonStyle(.bordered)
        }
      }
    }
    .padding(16)
    .animatedStoryBubble(
      tint: session.awaitingRevision ? StudioTheme.warm : StudioTheme.sky,
      cornerRadius: 30,
      isSelected: session.awaitingRevision
    )
  }

  private func confirmedTrail(_ session: GuidedFlowSession) -> some View {
    let recent = Array(session.acceptedSteps.suffix(4).reversed())
    return Group {
      if !recent.isEmpty {
        DisclosureGroup {
          VStack(alignment: .leading, spacing: 10) {
            ForEach(recent) { step in
              HStack(alignment: .top, spacing: 9) {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(StudioTheme.mint)
                  .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                  Text(step.acceptedSummary)
                    .font(.callout)
                  Text(
                    "\(step.phase.rawValue) · \(step.skill.rawValue) · \(step.responseMode.rawValue)"
                  )
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                }
              }
            }
          }
          .padding(.top, 10)
        } label: {
          Label("最近确认的创作决定", systemImage: "clock.arrow.circlepath")
            .font(.callout.weight(.semibold))
        }
        .padding(16)
        .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 30)
      }
    }
  }

  private func contributionImpactWorkspace(
    session: GuidedFlowSession,
    contribution: GuidedFlowContribution
  ) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 14) {
          HStack(alignment: .top, spacing: 16) {
            Image(systemName: "text.badge.checkmark")
              .font(.system(size: 28, weight: .semibold))
              .foregroundStyle(.white)
              .frame(width: 58, height: 58)
              .background(
                LinearGradient(
                  colors: [StudioTheme.mint, StudioTheme.accent],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18)
              )

            VStack(alignment: .leading, spacing: 7) {
              EyebrowLabel(text: "即时创作回声", color: StudioTheme.mint)
              Text("你的文字已经进入故事")
                .font(.system(size: 34, weight: .semibold, design: .serif))
              Text(contribution.echo.headline)
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
          }

          Text(contribution.echo.impactSummary)
            .font(.system(size: 16))
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)

          HStack(spacing: 9) {
            contributionMetric(
              "\(contribution.rawText.count) 字原文",
              icon: "doc.text.fill",
              tint: StudioTheme.mint
            )
            contributionMetric(
              "\(contribution.echo.discoveries.count) 个故事抓手",
              icon: "sparkles",
              tint: StudioTheme.warm
            )
            contributionMetric(
              "已保存为作者原稿",
              icon: "lock.doc.fill",
              tint: StudioTheme.sky
            )
          }
        }
        .padding(24)
        .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 46, isSelected: true)

        VStack(alignment: .leading, spacing: 12) {
          EyebrowLabel(text: "这篇文字已经创造了什么", color: StudioTheme.warm)
          Text("这里不评价作文好坏，只显示原文已经为人物、情节和场面提供了哪些可用材料。")
            .font(.callout)
            .foregroundStyle(.secondary)

          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 280), spacing: 12)],
            spacing: 12
          ) {
            ForEach(contribution.echo.discoveries) { discovery in
              contributionDiscoveryCard(discovery)
            }
          }
        }
        .padding(20)
        .animatedStoryBubble(tint: StudioTheme.warm, cornerRadius: 40)

        VStack(alignment: .leading, spacing: 10) {
          EyebrowLabel(text: "当前小步被提炼为", color: StudioTheme.accent)
          Text(contribution.echo.canonicalDecision)
            .font(.system(size: 20, weight: .semibold, design: .serif))
            .lineSpacing(5)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
          Label(
            "这是对当前命题的工作提炼。你的全文仍然原样保存，并会继续进入后续AI上下文。",
            systemImage: "arrow.triangle.branch"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        .padding(20)
        .animatedStoryBubble(tint: StudioTheme.accent, cornerRadius: 38)

        if !contribution.echo.preservedLines.isEmpty {
          VStack(alignment: .leading, spacing: 11) {
            EyebrowLabel(text: "值得原样保留的句子", color: StudioTheme.sky)
            ForEach(contribution.echo.preservedLines, id: \.self) { line in
              Text("“\(line)”")
                .font(.system(size: 16, design: .serif))
                .italic()
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            }
          }
          .padding(20)
          .animatedStoryBubble(tint: StudioTheme.sky, cornerRadius: 38)
        }

        DisclosureGroup {
          Text(contribution.rawText)
            .font(.system(size: 16, design: .serif))
            .lineSpacing(6)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
        } label: {
          Label("查看我提交的完整原文", systemImage: "doc.richtext.fill")
            .font(.callout.weight(.semibold))
        }
        .padding(18)
        .animatedStoryBubble(tint: StudioTheme.sky, cornerRadius: 34)

        HStack(alignment: .center, spacing: 14) {
          VStack(alignment: .leading, spacing: 4) {
            EyebrowLabel(text: "下一步会从这里继续", color: StudioTheme.mint)
            Text(contribution.echo.nextQuestion)
              .font(.system(size: 17, weight: .medium))
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 18)
          Button("带着这些发现继续", systemImage: "arrow.right.circle.fill") {
            session.pendingContribution = nil
            saveSilently()
            Task { @MainActor in
              try? await Task.sleep(for: .milliseconds(160))
              answerIsFocused = true
            }
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .tint(StudioTheme.mint)
        }
        .padding(20)
        .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 38)
      }
      .padding(.horizontal, 28)
      .padding(.vertical, 26)
      .frame(maxWidth: 980)
      .frame(maxWidth: .infinity)
    }
  }

  private func contributionMetric(
    _ text: String,
    icon: String,
    tint: Color
  ) -> some View {
    Label(text, systemImage: icon)
      .font(.caption.weight(.semibold))
      .foregroundStyle(tint)
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(tint.opacity(0.08), in: Capsule())
  }

  private func contributionDiscoveryCard(
    _ discovery: GuidedFlowDiscovery
  ) -> some View {
    let tint = discoveryTint(discovery.kind)
    return VStack(alignment: .leading, spacing: 9) {
      Label(discovery.kind.rawValue, systemImage: discovery.kind.systemImage)
        .font(.caption.weight(.bold))
        .foregroundStyle(tint)
      Text(discovery.finding)
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
      if !discovery.sourceExcerpt.isEmpty {
        Text("原文：“\(discovery.sourceExcerpt)”")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
    .background(tint.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(tint.opacity(0.15))
    }
  }

  private func discoveryTint(_ kind: GuidedFlowDiscoveryKind) -> Color {
    switch kind {
    case .character: StudioTheme.mint
    case .plot: StudioTheme.warm
    case .relationship: StudioTheme.accent
    case .image: StudioTheme.sky
    case .voice: .purple
    case .world: .cyan
    case .theme: .indigo
    }
  }

  private func completionView(_ session: GuidedFlowSession) -> some View {
    VStack(spacing: 22) {
      Image(systemName: "checkmark.seal.fill")
        .font(.system(size: 46, weight: .light))
        .foregroundStyle(StudioTheme.mint)
      VStack(spacing: 8) {
        Text("剧本已经由你的决定逐步组成")
          .font(.system(.largeTitle, design: .serif, weight: .semibold))
        Text("共确认 \(session.acceptedSteps.count) 个微型创作决定。正文来自这些已确认的小步，而不是一次性整块生成。")
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 620)
      }
      HStack(spacing: 12) {
        Button("阅读并继续修订", systemImage: "text.book.closed.fill") {
          onNavigate(.screenplay)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(StudioTheme.mint)

        Button("查看版本", systemImage: "clock.arrow.circlepath") {
          onNavigate(.versions)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
      }
    }
    .padding(48)
    .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 58, isSelected: true)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func recoveryView(_ session: GuidedFlowSession) -> some View {
    ContentUnavailableView {
      Label("正在重新定位当前小步", systemImage: "arrow.triangle.branch")
    } description: {
      Text("项目状态可能刚刚发生变化。重新进入后会从第一个未完成决定继续。")
    } actions: {
      Button("重新定位") {
        GuidedFlowCoordinator.bootstrap(
          session,
          project: project,
          modelContext: modelContext
        )
        saveSilently()
      }
    }
  }

  private func prepareSession() {
    let existing = storedSessions.first { $0.projectID == project.id }
    let session = existing ?? GuidedFlowCoordinator.makeSession(for: project)
    if existing == nil {
      modelContext.insert(session)
    }
    GuidedFlowCoordinator.bootstrap(
      session,
      project: project,
      modelContext: modelContext
    )
    activeSession = session
    saveSilently()
    if session.pendingContribution == nil {
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(180))
        answerIsFocused = true
      }
    }
  }

  private func submit(
    session: GuidedFlowSession,
    challenge: GuidedFlowChallenge
  ) {
    let answer = session.currentDraft
    let responseMode: GuidedFlowResponseMode =
      challenge.supportsPromptedWriting
      ? session.responseMode
      : .focused
    let local = GuidedFlowCoordinator.localEvaluation(
      answer: answer,
      challenge: challenge,
      responseMode: responseMode
    )
    guard local.isReady else {
      GuidedFlowCoordinator.recordFailedAttempt(
        answer: answer,
        challenge: challenge,
        feedback: local.feedback,
        passedLocalChecks: false,
        coachReviewed: nil,
        responseMode: responseMode,
        session: session
      )
      session.lastNudge = local.singleNudge
      saveSilently()
      return
    }

    if responseMode == .promptedWriting {
      submitPromptedWriting(
        answer: answer,
        local: local,
        session: session,
        challenge: challenge
      )
      return
    }

    if settings.hasAPIKey {
      Task {
        isReviewing = true
        defer { isReviewing = false }
        do {
          let review = try await GuidedFlowCoachEngine.review(
            answer: answer,
            challenge: challenge,
            project: project,
            configuration: try settings.configuration()
          )
          if review.isReady {
            try GuidedFlowCoordinator.accept(
              answer: answer,
              acceptedSummary: review.acceptedSummary,
              challenge: challenge,
              coachReviewed: true,
              responseMode: .focused,
              session: session,
              project: project,
              modelContext: modelContext
            )
            answerIsFocused = true
          } else {
            GuidedFlowCoordinator.recordFailedAttempt(
              answer: answer,
              challenge: challenge,
              feedback: review.feedback,
              passedLocalChecks: true,
              coachReviewed: false,
              responseMode: .focused,
              session: session
            )
            session.lastNudge = review.singleNudge
            saveSilently()
          }
        } catch {
          present(error)
        }
      }
    } else {
      do {
        try GuidedFlowCoordinator.accept(
          answer: answer,
          acceptedSummary: local.acceptedSummary,
          challenge: challenge,
          coachReviewed: nil,
          responseMode: .focused,
          session: session,
          project: project,
          modelContext: modelContext
        )
        answerIsFocused = true
      } catch {
        present(error)
      }
    }
  }

  private func submitPromptedWriting(
    answer: String,
    local: GuidedFlowEvaluation,
    session: GuidedFlowSession,
    challenge: GuidedFlowChallenge
  ) {
    if settings.hasAPIKey {
      Task {
        isReviewing = true
        defer { isReviewing = false }
        do {
          let review = try await GuidedFlowCoachEngine.reflectOnPromptedWriting(
            answer: answer,
            challenge: challenge,
            project: project,
            configuration: try settings.configuration()
          )
          guard review.isReady, let echo = review.echo else {
            GuidedFlowCoordinator.recordFailedAttempt(
              answer: answer,
              challenge: challenge,
              feedback: review.feedback,
              passedLocalChecks: true,
              coachReviewed: false,
              responseMode: .promptedWriting,
              session: session
            )
            session.lastNudge = review.singleNudge
            saveSilently()
            return
          }
          try GuidedFlowCoordinator.accept(
            answer: answer,
            acceptedSummary: echo.canonicalDecision,
            challenge: challenge,
            coachReviewed: true,
            responseMode: .promptedWriting,
            contributionEcho: echo,
            session: session,
            project: project,
            modelContext: modelContext
          )
        } catch {
          present(error)
        }
      }
    } else {
      let review = GuidedFlowContributionAnalyzer.localReview(
        answer: answer,
        challenge: challenge
      )
      guard review.isReady, let echo = review.echo else {
        GuidedFlowCoordinator.recordFailedAttempt(
          answer: answer,
          challenge: challenge,
          feedback: review.feedback,
          passedLocalChecks: true,
          coachReviewed: nil,
          responseMode: .promptedWriting,
          session: session
        )
        session.lastNudge = review.singleNudge
        saveSilently()
        return
      }
      do {
        try GuidedFlowCoordinator.accept(
          answer: answer,
          acceptedSummary: local.acceptedSummary,
          challenge: challenge,
          coachReviewed: nil,
          responseMode: .promptedWriting,
          contributionEcho: echo,
          session: session,
          project: project,
          modelContext: modelContext
        )
      } catch {
        present(error)
      }
    }
  }

  private func requestSupport(
    session: GuidedFlowSession,
    challenge: GuidedFlowChallenge
  ) {
    let responseMode: GuidedFlowResponseMode =
      challenge.supportsPromptedWriting
      ? session.responseMode
      : .focused
    GuidedFlowCoordinator.requestNextSupport(
      for: session,
      challenge: challenge
    )

    guard session.scaffoldLevel == .minimalAssist else {
      saveSilently()
      return
    }

    guard settings.hasAPIKey else {
      if responseMode == .promptedWriting {
        session.lastNudge =
          "可以从这个切口开始：\(challenge.sentenceStarter.isEmpty ? challenge.reframe : challenge.sentenceStarter) 然后写一个具体动作或细节，让人物不得不回应。"
      } else {
        session.lastNudge =
          challenge.sentenceStarter.isEmpty
          ? (challenge.mechanismHints.first ?? challenge.reframe)
          : challenge.sentenceStarter
      }
      saveSilently()
      return
    }

    Task {
      isRequestingAssist = true
      defer { isRequestingAssist = false }
      do {
        session.lastNudge = try await GuidedFlowCoachEngine.minimalAssist(
          challenge: challenge,
          currentDraft: session.currentDraft,
          project: project,
          configuration: try settings.configuration(),
          responseMode: responseMode
        )
        session.touch()
        saveSilently()
      } catch {
        present(error)
      }
    }
  }

  private func applyOption(
    _ option: String,
    challenge: GuidedFlowChallenge,
    session: GuidedFlowSession
  ) {
    if challenge.answerKind == .choice || challenge.answerKind == .confirmation {
      session.currentDraft = option
    } else if option.hasSuffix("：") {
      session.currentDraft = option
    } else {
      session.currentDraft = option
    }
    session.touch()
    answerIsFocused = true
  }

  private func responseModeBinding(
    _ session: GuidedFlowSession
  ) -> Binding<GuidedFlowResponseMode> {
    Binding(
      get: { session.responseMode },
      set: { mode in
        session.responseMode = mode
        session.lastFeedback = ""
        session.lastNudge = ""
        session.awaitingRevision = false
        session.scaffoldLevel = .questionOnly
        session.touch()
        answerIsFocused = true
      }
    )
  }

  private func draftBinding(_ session: GuidedFlowSession) -> Binding<String> {
    Binding(
      get: { session.currentDraft },
      set: {
        session.currentDraft = $0
        session.awaitingRevision = false
        session.touch()
      }
    )
  }

  private func supportButtonTitle(
    _ session: GuidedFlowSession,
    responseMode: GuidedFlowResponseMode
  ) -> String {
    if session.scaffoldLevel == .minimalAssist {
      return responseMode == .promptedWriting
        ? "再给我一个写作切口"
        : "再给当前一步一个最小建议"
    }
    let nextRaw = min(
      GuidedFlowScaffoldLevel.minimalAssist.rawValue,
      session.scaffoldLevel.rawValue + 1
    )
    let next = GuidedFlowScaffoldLevel(rawValue: nextRaw) ?? .minimalAssist
    if responseMode == .promptedWriting {
      return "我需要一个写作切口 · \(next.label)"
    }
    return "我需要一点帮助 · \(next.label)"
  }

  private func phaseStepLabel(_ session: GuidedFlowSession) -> String {
    switch session.phase {
    case .foundation:
      "故事核心 · 第 \(min(session.stepIndex + 1, 6))/6 小步"
    case .structure:
      "结构推进 · 第 \(session.itemIndex + 1)/\(max(project.structureTemplate.stages.count, 1)) 阶段 · 小步 \(session.stepIndex + 1)/3"
    case .scene:
      "场景设计 · 场 \(session.itemIndex + 1)/\(max(project.sceneContracts.count, 1)) · 小步 \(session.stepIndex + 1)/7"
    case .beat:
      "情境更新 · 场 \(session.itemIndex + 1) · 第 \(session.subitemIndex + 1) 次变化 · 小步 \(session.stepIndex + 1)/6"
    case .screenplay:
      "逐场确认 · 场 \(session.itemIndex + 1)/\(max(project.sceneContracts.count, 1))"
    case .completed:
      "剧本完成"
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
