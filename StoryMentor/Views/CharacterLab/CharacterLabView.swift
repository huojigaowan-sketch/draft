import SwiftData
import SwiftUI

struct CharacterLabView: View {
  @Environment(\.modelContext) private var modelContext
  @Bindable var project: StoryProject
  @State private var selectedCharacterID: UUID?

  private var sortedCharacters: [StoryCharacter] {
    project.characters.sorted { $0.updatedAt > $1.updatedAt }
  }

  private var selectedCharacter: StoryCharacter? {
    if let selectedCharacterID,
      let match = project.characters.first(where: { $0.id == selectedCharacterID })
    {
      return match
    }
    return sortedCharacters.first
  }

  var body: some View {
    ZStack {
      StudioCanvas()

      VStack(spacing: 0) {
        labHeader
        Divider().opacity(0.42)

        if let selectedCharacter {
          CharacterEditorView(character: selectedCharacter, project: project)
        } else {
          EmptyCharacterState(onCreate: addCharacter)
        }
      }
    }
    .task(id: project.requestedCharacterID) {
      if let requestedID = project.requestedCharacterID,
        project.characters.contains(where: { $0.id == requestedID })
      {
        selectedCharacterID = requestedID
        project.requestedCharacterID = nil
      } else if selectedCharacterID == nil {
        selectedCharacterID = sortedCharacters.first?.id
      }
    }
    .onChange(of: project.characters.count) { _, _ in
      if selectedCharacterID == nil {
        selectedCharacterID = sortedCharacters.first?.id
      }
    }
  }

  private var labHeader: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          EyebrowLabel(text: "Character Lab")
          Text("人物实验室")
            .font(.system(.title, design: .serif, weight: .semibold))
        }

        Spacer()

        Button("新建人物", systemImage: "plus") {
          addCharacter()
        }
        .buttonStyle(.borderedProminent)
      }

      if !sortedCharacters.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(sortedCharacters) { character in
              characterTab(character)
            }
          }
        }
      }
    }
    .padding(.horizontal, 26)
    .padding(.vertical, 18)
    .background(.ultraThinMaterial)
  }

  private func characterTab(_ character: StoryCharacter) -> some View {
    let isSelected = selectedCharacter?.id == character.id
    let tint: Color = character.role == .antagonist ? .red : StudioTheme.accent

    return Button {
      selectedCharacterID = character.id
    } label: {
      HStack(spacing: 8) {
        Image(systemName: character.role == .antagonist ? "bolt.fill" : "person.fill")
          .font(.caption)
        Text(character.name)
          .lineLimit(1)
        Text(character.role.rawValue)
          .font(.caption2)
          .foregroundStyle(isSelected ? tint : .secondary)
      }
      .font(.callout.weight(.medium))
      .padding(.horizontal, 12)
      .padding(.vertical, 9)
      .foregroundStyle(Color.primary)
      .animatedStoryBubble(
        tint: tint,
        cornerRadius: 24,
        isSelected: isSelected
      )
    }
    .buttonStyle(.plain)
  }

  private func addCharacter() {
    let character = StoryCharacter(project: project)
    modelContext.insert(character)
    project.characters.append(character)
    project.touch()
    selectedCharacterID = character.id
  }
}

private struct EmptyCharacterState: View {
  let onCreate: () -> Void

  var body: some View {
    VStack(spacing: 20) {
      Image(systemName: "person.crop.circle.dashed")
        .font(.system(size: 44, weight: .light))
        .foregroundStyle(StudioTheme.accent)

      VStack(spacing: 7) {
        Text("写下第一个人物")
          .font(.system(.title, design: .serif, weight: .semibold))
        Text("可以是一句印象、一个矛盾，甚至只是一个你忘不掉的动作。")
          .font(.body)
          .foregroundStyle(.secondary)
      }
      .multilineTextAlignment(.center)

      Button("创建人物草稿", systemImage: "plus") {
        onCreate()
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
    }
    .padding(40)
    .frame(maxWidth: 680, minHeight: 360)
    .animatedStoryBubble(tint: StudioTheme.accent, cornerRadius: 72)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct CharacterEditorView: View {
  @Bindable var character: StoryCharacter
  let project: StoryProject

  private let fieldColumns = [
    GridItem(.adaptive(minimum: 245), spacing: 14)
  ]

  var body: some View {
    ScrollView {
      GlassEffectContainer(spacing: 10) {
        VStack(alignment: .leading, spacing: 18) {
          identityCard
          seedCard
          semanticTrajectoryCard

          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text("人物发动机")
                .font(.headline)
              Text("先完成最能产生戏剧的四个维度。")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            ProgressRing(value: character.readinessFraction, lineWidth: 6, diameter: 54)
          }
          .padding(.horizontal, 8)
          .padding(.top, 4)

          BubbleWorkspaceConnector(tint: StudioTheme.accent, branchCount: 4)

          LazyVGrid(columns: fieldColumns, spacing: 14) {
            PromptFieldCard(
              title: "外部目标",
              icon: "target",
              prompt: "他具体想得到什么？观众如何看见成功或失败？",
              text: $character.externalGoal
            )
            PromptFieldCard(
              title: "内在需求",
              icon: "heart.text.square",
              prompt: "他真正需要学会、接受或放下什么？",
              text: $character.internalNeed
            )
            PromptFieldCard(
              title: "核心恐惧",
              icon: "exclamationmark.triangle",
              prompt: "什么结果会让他宁愿逃避，也不愿面对？",
              text: $character.fear
            )
            PromptFieldCard(
              title: "错误信念",
              icon: "eye.trianglebadge.exclamationmark",
              prompt: "他深信什么，但故事最终会证明这并不完整？",
              text: $character.falseBelief
            )
          }

          VStack(alignment: .leading, spacing: 14) {
            DisclosureGroup {
              LazyVGrid(columns: fieldColumns, spacing: 14) {
                PromptFieldCard(
                  title: "过去创伤",
                  icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                  prompt: "哪件旧事塑造了今天的防御方式？",
                  text: $character.trauma
                )
                PromptFieldCard(
                  title: "秘密",
                  icon: "lock.doc",
                  prompt: "一旦暴露，什么会改变关系或行动？",
                  text: $character.secret
                )
                PromptFieldCard(
                  title: "缺陷",
                  icon: "aqi.medium",
                  prompt: "哪种行为持续制造伤害或错误选择？",
                  text: $character.flaw
                )
                PromptFieldCard(
                  title: "能力",
                  icon: "sparkles",
                  prompt: "他凭什么值得被放进这场故事？",
                  text: $character.strength
                )
                PromptFieldCard(
                  title: "人物弧线",
                  icon: "arrow.trianglehead.2.clockwise.rotate.90",
                  prompt: "开场与结尾，他会在哪个价值选择上不同？",
                  text: $character.arc
                )
                PromptFieldCard(
                  title: "背景",
                  icon: "books.vertical",
                  prompt: "只记录会影响当前选择的过去。",
                  text: $character.background
                )
              }
              .padding(.top, 14)
            } label: {
              Label("展开更多人物维度", systemImage: "slider.horizontal.3")
                .font(.headline)
            }
          }
          .padding(20)
          .animatedStoryBubble(tint: StudioTheme.sky, cornerRadius: 48)
        }
        .padding(26)
        .frame(maxWidth: 1_180)
        .frame(maxWidth: .infinity)
      }
    }
    .onDisappear {
      character.touch()
    }
  }

  private var identityCard: some View {
    HStack(alignment: .bottom, spacing: 16) {
      VStack(alignment: .leading, spacing: 7) {
        Text("姓名")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        TextField("人物姓名", text: $character.name)
          .textFieldStyle(.plain)
          .font(.system(.title, design: .serif, weight: .semibold))
      }

      VStack(alignment: .leading, spacing: 7) {
        Text("角色功能")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        Picker("角色功能", selection: $character.roleRawValue) {
          ForEach(CharacterRole.allCases) { role in
            Text(role.rawValue).tag(role.rawValue)
          }
        }
        .labelsHidden()
        .frame(width: 130)
      }

      VStack(alignment: .leading, spacing: 7) {
        Text("年龄")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        TextField("可留空", text: $character.age)
          .frame(width: 80)
      }

      VStack(alignment: .leading, spacing: 7) {
        Text("职业 / 身份")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        TextField("例如：外科医生", text: $character.occupation)
          .frame(minWidth: 140)
      }
    }
    .padding(20)
    .animatedStoryBubble(tint: StudioTheme.accent, cornerRadius: 54, isSelected: true)
  }

  private var seedCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("自由人物草稿", systemImage: "pencil.and.scribble")
          .font(.headline)
        Spacer()
        LocalPolishButton(text: $character.seedText)
        Text("\(character.seedText.count) 字")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.tertiary)
      }

      ZStack(alignment: .topLeading) {
        if character.seedText.isEmpty {
          Text("随便写。比如：一个天才医生，害怕失败，所以从不接真正困难的手术……")
            .font(.body)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 8)
            .allowsHitTesting(false)
        }

        TextEditor(text: $character.seedText)
          .font(.body)
          .scrollContentBackground(.hidden)
          .frame(minHeight: 170)
      }
      .padding(8)
      .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))

      Label("SwiftData 会把草稿保存在本机；AI 尚未读取这段内容。", systemImage: "lock.fill")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(20)
    .animatedStoryBubble(tint: StudioTheme.warm, cornerRadius: 50)
  }

  @ViewBuilder
  private var semanticTrajectoryCard: some View {
    if let projection = DramaticProjectionEngine.projection(
      .character,
      key: character.id.uuidString,
      in: project
    ) {
      VStack(alignment: .leading, spacing: 11) {
        HStack {
          Label("正文实证的人物轨迹", systemImage: "point.3.filled.connected.trianglepath.dotted")
            .font(.headline)
            .foregroundStyle(StudioTheme.mint)
          Spacer()
          Text("\(projection.evidenceIDs.count) 条证据")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        Text(projection.summary)
          .font(.callout)
          .lineSpacing(4)
          .fixedSize(horizontal: false, vertical: true)
        if !projection.exitState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          Divider()
          Text(projection.exitState)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
        }
        Text("人物设定是创作意图；这里仅显示正文实际改变了哪些目标、信念、关系与承诺。")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      .padding(18)
      .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 46)
    }
  }
}

private struct PromptFieldCard: View {
  let title: String
  let icon: String
  let prompt: String
  @Binding var text: String

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(title, systemImage: icon)
        .font(.callout.weight(.semibold))
        .foregroundStyle(StudioTheme.accent)

      TextField(prompt, text: $text, axis: .vertical)
        .lineLimit(2...5)
        .textFieldStyle(.plain)
        .font(.callout)
    }
    .padding(16)
    .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
    .animatedStoryBubble(tint: StudioTheme.accent, cornerRadius: 38)
  }
}
