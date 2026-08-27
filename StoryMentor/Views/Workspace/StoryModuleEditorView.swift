import SwiftUI

/// Focused editors for the two story systems that are intentionally authored
/// outside the fixed-structure and screenplay workspaces.
struct StoryModuleEditorView: View {
  @Bindable var project: StoryProject
  let section: WorkspaceSection

  var body: some View {
    ZStack {
      StudioCanvas()

      VStack(spacing: 0) {
        header
        Divider().opacity(0.42)

        ScrollView {
          GlassEffectContainer(spacing: 10) {
            switch section {
            case .theme:
              storyCoreWorkspace
            case .world:
              worldWorkspace
            default:
              unsupportedState
            }
          }
        }
      }
    }
  }

  private var header: some View {
    HStack(spacing: 16) {
      Image(systemName: section == .theme ? "scope" : "globe.asia.australia.fill")
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(section == .theme ? StudioTheme.warm : StudioTheme.mint)
        .frame(width: 44, height: 44)
        .animatedStoryBubble(
          tint: section == .theme ? StudioTheme.warm : StudioTheme.mint,
          cornerRadius: 18,
          isSelected: true
        )

      VStack(alignment: .leading, spacing: 3) {
        EyebrowLabel(
          text: section == .theme ? "STORY CORE" : "WORLD PRESSURE SYSTEM",
          color: section == .theme ? StudioTheme.warm : StudioTheme.mint
        )
        Text(section == .theme ? "故事核心工作台" : "世界规则工作台")
          .font(.system(.title2, design: .serif, weight: .semibold))
        Text(
          section == .theme
            ? "用前提、戏剧问题、冲突和主题组成同一台发动机。"
            : "只保留会限制行动、制造稀缺或改变代价的设定。"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Spacer()

      HStack(spacing: 10) {
        ProgressRing(value: readiness, lineWidth: 5, diameter: 48)
        VStack(alignment: .leading, spacing: 2) {
          Text("完成度")
            .font(.caption2)
            .foregroundStyle(.secondary)
          Text("\(completedItemCount)/\(requiredItemCount)")
            .font(.callout.monospacedDigit().weight(.semibold))
        }
      }
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 15)
    .background(.ultraThinMaterial)
  }

  private var storyCoreWorkspace: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: 18) {
        storyCoreEditors
          .frame(minWidth: 620)
        storyCoreGuide
          .frame(width: 310)
      }
      .frame(maxWidth: .infinity)

      VStack(alignment: .leading, spacing: 18) {
        storyCoreEditors
        storyCoreGuide
      }
    }
    .padding(24)
    .frame(maxWidth: 1_180)
    .frame(maxWidth: .infinity)
  }

  private var storyCoreEditors: some View {
    VStack(alignment: .leading, spacing: 14) {
      StorySystemField(
        title: "1 · 一句话前提",
        purpose: "谁为了什么采取行动；什么力量阻止；失败会失去什么。",
        placeholder: "例如：一名替陌生人保管记忆的档案员，必须在系统销毁证据前查明一段来自未来的记忆。",
        text: tracked(\.logline),
        minimumHeight: 105,
        tint: StudioTheme.warm
      )

      BubbleWorkspaceConnector(tint: StudioTheme.warm, height: 30)

      StorySystemField(
        title: "2 · 戏剧问题",
        purpose: "用一个能贯穿全片、直到结尾才被回答的问题维持期待。",
        placeholder: "主人公能否在保护所爱之人与公开真相之间作出选择？",
        text: tracked(\.dramaticPromise),
        minimumHeight: 105,
        tint: StudioTheme.accent
      )

      BubbleWorkspaceConnector(tint: StudioTheme.accent, height: 30)

      StorySystemField(
        title: "3 · 核心冲突",
        purpose: "写清两股无法同时满足的力量，以及选择任一方的具体代价。",
        placeholder: "保护妹妹的新生活，与保留公共罪行的证据，二者只能选择其一。",
        text: tracked(\.coreConflictText),
        minimumHeight: 145,
        tint: StudioTheme.sky
      )

      BubbleWorkspaceConnector(tint: StudioTheme.sky, height: 30)

      StorySystemField(
        title: "4 · 主题命题",
        purpose: "不是关键词，而是故事将通过行动检验的一句可争论判断。",
        placeholder: "人无法靠删去痛苦获得完整自由；记住有时也是对他人的责任。",
        text: tracked(\.themeText),
        minimumHeight: 145,
        tint: StudioTheme.mint
      )
    }
    .frame(maxWidth: .infinity)
  }

  private var storyCoreGuide: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 12) {
        Label("完成标准", systemImage: "checklist")
          .font(.headline)
        LocalCheckRow(
          text: "一句话里有行动主体与明确目标",
          state: checkState(project.logline)
        )
        LocalCheckRow(
          text: "戏剧问题可以由结尾回答",
          state: checkState(project.dramaticPromise)
        )
        LocalCheckRow(
          text: "冲突包含不可兼得的选择与代价",
          state: checkState(project.coreConflictText)
        )
        LocalCheckRow(
          text: "主题是一句可反驳的判断",
          state: checkState(project.themeText)
        )
      }
      .padding(17)
      .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 42)

      VStack(alignment: .leading, spacing: 10) {
        Label("精修顺序", systemImage: "arrow.down.circle")
          .font(.headline)
        guideStep("1", "先确认主人公在追求什么")
        guideStep("2", "再制造一个无法两全的选择")
        guideStep("3", "让正反双方用行动给出相反答案")
        guideStep("4", "最后才提炼主题命题")
      }
      .padding(17)
      .animatedStoryBubble(tint: StudioTheme.warm, cornerRadius: 42)

      if !project.themeBibleText.moduleIsBlank {
        contextCard(
          title: "固定结构给出的主题证据",
          icon: "lock.doc.fill",
          text: project.themeBibleText
        )
      }

      if let projection = DramaticProjectionEngine.projection(.theme, key: "root", in: project) {
        contextCard(
          title: "正文正在检验的主题",
          icon: "point.3.filled.connected.trianglepath.dotted",
          text: projection.summary
        )
      }

      if let projection = DramaticProjectionEngine.projection(.conflict, key: "root", in: project) {
        contextCard(
          title: "正文实际运行的冲突",
          icon: "bolt.horizontal.fill",
          text: projection.summary
        )
      }
    }
  }

  private var worldWorkspace: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: 18) {
        worldEditors
          .frame(minWidth: 600)
        worldGuide
          .frame(width: 330)
      }
      .frame(maxWidth: .infinity)

      VStack(alignment: .leading, spacing: 18) {
        worldEditors
        worldGuide
      }
    }
    .padding(24)
    .frame(maxWidth: 1_180)
    .frame(maxWidth: .infinity)
  }

  private var worldEditors: some View {
    VStack(alignment: .leading, spacing: 14) {
      StorySystemField(
        title: "1 · 压力规则",
        purpose: "只写会迫使人物改变计划的制度、限制、资源与禁令。",
        placeholder: "例如：记忆只能由本人取回；销毁必须由两名工作人员交叉见证；黑市能够伪造授权。",
        text: tracked(\.worldText),
        minimumHeight: 250,
        tint: StudioTheme.mint
      )

      BubbleWorkspaceConnector(tint: StudioTheme.mint, branchCount: 2, height: 36)

      quickWorldPrompts

      StorySystemField(
        title: "2 · 现实与事实边界",
        purpose: "标明不能被虚构改写的事实，以及仍需核验的部分。",
        placeholder: "记录真实资料、不可改动事实、匿名化要求，以及明确属于虚构的内容。",
        text: tracked(\.sourceFacts),
        minimumHeight: 180,
        tint: StudioTheme.sky
      )

      if !project.worldBibleText.moduleIsBlank {
        contextCard(
          title: "固定结构中的世界投影",
          icon: "book.closed.fill",
          text: project.worldBibleText
        )
      }
    }
    .frame(maxWidth: .infinity)
  }

  private var worldGuide: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 12) {
        Label("规则筛选器", systemImage: "line.3.horizontal.decrease.circle")
          .font(.headline)
        LocalCheckRow(
          text: "规则会限制某个具体行动",
          state: checkState(project.worldText)
        )
        LocalCheckRow(
          text: "违反规则会产生可见代价",
          state: checkState(project.worldText)
        )
        LocalCheckRow(
          text: "事实与虚构的边界已标明",
          state: checkState(project.sourceFacts)
        )
        Text("删掉只解释背景、却不改变任何选择的设定。")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(17)
      .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 42)

      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Label("作者锁定事实", systemImage: "lock.fill")
            .font(.headline)
          Spacer()
          Text("\(lockedFacts.count)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }

        if lockedFacts.isEmpty {
          Text("当前没有作者锁定事实。这里不会创建第二套事实库。")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          ForEach(lockedFacts.prefix(6)) { fact in
            Text("• \(fact.subject) \(fact.predicate) \(fact.value)")
              .font(.caption)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .padding(17)
      .animatedStoryBubble(tint: StudioTheme.sky, cornerRadius: 42)

      if let projection = DramaticProjectionEngine.projection(.world, key: "root", in: project) {
        contextCard(
          title: "正文已经建立的世界事实",
          icon: "point.3.filled.connected.trianglepath.dotted",
          text: projection.summary
        )
      }
    }
  }

  private var quickWorldPrompts: some View {
    VStack(alignment: .leading, spacing: 9) {
      EyebrowLabel(text: "快速建立压力")
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(worldPrompts, id: \.self) { prompt in
            Button(prompt) {
              appendWorldPrompt(prompt)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }
        }
      }
    }
    .padding(14)
    .animatedStoryBubble(tint: StudioTheme.warm, cornerRadius: 34)
  }

  private func contextCard(title: String, icon: String, text: String) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      Label(title, systemImage: icon)
        .font(.headline)
      Text(text)
        .font(.callout)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(17)
    .animatedStoryBubble(
      tint: section == .theme ? StudioTheme.warm : StudioTheme.mint,
      cornerRadius: 42
    )
  }

  private func guideStep(_ number: String, _ text: String) -> some View {
    HStack(alignment: .top, spacing: 9) {
      Text(number)
        .font(.caption2.monospacedDigit().weight(.bold))
        .foregroundStyle(.white)
        .frame(width: 20, height: 20)
        .background(StudioTheme.accent, in: Circle())
      Text(text)
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var unsupportedState: some View {
    ContentUnavailableView(
      "这里没有独立编辑器",
      systemImage: "arrowshape.turn.up.left",
      description: Text("固定结构与剧本生产分别在各自的专用工作区完成。")
    )
    .frame(maxWidth: .infinity, minHeight: 480)
  }

  private var lockedFacts: [StoryFactRecord] {
    project.canonicalFacts.filter(\.isLockedByAuthor)
  }

  private var worldPrompts: [String] {
    ["不可违反的规则", "稀缺资源", "权力如何执行", "违规代价", "谁从规则中获利"]
  }

  private var requiredValues: [String] {
    switch section {
    case .theme:
      [project.logline, project.dramaticPromise, project.coreConflictText, project.themeText]
    case .world:
      [project.worldText, project.sourceFacts]
    default:
      []
    }
  }

  private var completedItemCount: Int {
    requiredValues.filter { !$0.moduleIsBlank }.count
  }

  private var requiredItemCount: Int {
    max(requiredValues.count, 1)
  }

  private var readiness: Double {
    Double(completedItemCount) / Double(requiredItemCount)
  }

  private func tracked(_ keyPath: ReferenceWritableKeyPath<StoryProject, String>) -> Binding<String>
  {
    Binding(
      get: { project[keyPath: keyPath] },
      set: { value in
        project[keyPath: keyPath] = value
        project.touch()
      }
    )
  }

  private func checkState(_ value: String) -> LocalCheckRow.State {
    value.moduleIsBlank ? .missing : .present
  }

  private func appendWorldPrompt(_ prompt: String) {
    let prefix = project.worldText.moduleIsBlank ? "" : "\n\n"
    project.worldText += "\(prefix)【\(prompt)】\n"
    project.touch()
  }
}

private struct StorySystemField: View {
  let title: String
  let purpose: String
  let placeholder: String
  @Binding var text: String
  let minimumHeight: CGFloat
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 11) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.headline)
            .foregroundStyle(tint)
          Text(purpose)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
        LocalPolishButton(text: $text)
        Text("\(text.count) 字")
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.tertiary)
      }

      ZStack(alignment: .topLeading) {
        if text.moduleIsBlank {
          Text(placeholder)
            .font(.callout)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .allowsHitTesting(false)
        }

        TextEditor(text: $text)
          .font(.body)
          .scrollContentBackground(.hidden)
          .frame(minHeight: minimumHeight)
      }
      .padding(9)
      .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
      .overlay {
        RoundedRectangle(cornerRadius: 12)
          .stroke(tint.opacity(0.12))
      }
    }
    .padding(18)
    .animatedStoryBubble(tint: tint, cornerRadius: 50)
  }
}

extension String {
  fileprivate var moduleIsBlank: Bool {
    trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}
