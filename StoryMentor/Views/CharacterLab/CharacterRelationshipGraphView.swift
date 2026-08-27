import CryptoKit
import SwiftData
import SwiftUI

struct CharacterRelationshipGraphView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(AISettingsStore.self) private var settings

  @Bindable var project: StoryProject

  @State private var selectedCharacterID: UUID?
  @State private var layout: [UUID: CharacterGraphLayoutPoint] = [:]
  @State private var targetCharacterID: UUID?
  @State private var relationshipKind = CharacterRelationshipKind.alliance
  @State private var relationshipDetail = ""
  @State private var relationshipTension = 55.0
  @State private var relationshipIsSecret = false
  @State private var graphInstruction = ""
  @State private var isGenerating = false
  @State private var errorMessage = ""
  @State private var showingError = false

  private var characters: [StoryCharacter] {
    project.characters.sorted { lhs, rhs in
      if lhs.role == .protagonist { return true }
      if rhs.role == .protagonist { return false }
      return lhs.name < rhs.name
    }
  }

  private var selectedCharacter: StoryCharacter? {
    guard let selectedCharacterID else { return characters.first }
    return characters.first { $0.id == selectedCharacterID }
  }

  private var graphInstructionForAI: String {
    let clean = graphInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.isEmpty
      ? "请基于当前故事、人物和已确认关系，提出四套有明确戏剧作用的关系调整方案。"
      : clean
  }

  private var graphOptionsNeedRefresh: Bool {
    guard project.characterGraphOptions != nil else { return false }
    guard !project.characterGraphOptionsFingerprint.isEmpty else { return true }
    return CharacterGraphEngine(settings: settings).contextFingerprint(
      for: project,
      instruction: graphInstructionForAI
    ) != project.characterGraphOptionsFingerprint
  }

  var body: some View {
    ZStack {
      StudioCanvas()

      VStack(spacing: 0) {
        graphHeader
        Divider().opacity(0.45)

        ScrollView {
          GlassEffectContainer(spacing: 10) {
            VStack(alignment: .leading, spacing: 20) {
              if characters.isEmpty {
                emptyState
              } else {
                HSplitView {
                  graphCanvas
                    .frame(minWidth: 620, minHeight: 520)
                  characterInspector
                    .frame(minWidth: 280, idealWidth: 330, maxWidth: 390)
                }
                .frame(minHeight: 540)

                BubbleWorkspaceConnector(
                  tint: StudioTheme.mint,
                  branchCount: 4,
                  height: 40
                )

                aiAdjustmentStudio
              }
            }
            .padding(22)
          }
        }
      }
    }
    .onAppear {
      initializeLayout()
      if graphInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        !project.characterGraphLastInstruction.trimmingCharacters(
          in: .whitespacesAndNewlines
        ).isEmpty
      {
        graphInstruction = project.characterGraphLastInstruction
      }
      selectedCharacterID = selectedCharacterID ?? characters.first?.id
      targetCharacterID =
        characters.first {
          $0.id != selectedCharacterID
        }?.id
    }
    .onChange(of: project.characters.count) { _, _ in
      initializeLayout()
    }
    .alert("人物关系没有更新", isPresented: $showingError) {
      Button("好", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  private var graphHeader: some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 5) {
        EyebrowLabel(text: "CHARACTER CONSTELLATION", color: StudioTheme.mint)
        Text("人物关系图")
          .font(.system(size: 28, weight: .semibold, design: .serif))
      }
      Spacer()
      HStack(spacing: 8) {
        graphMetric("\(characters.count) 人", icon: "person.3.fill", tint: StudioTheme.accent)
        graphMetric(
          "\(project.characterRelationships.count) 条关系",
          icon: "point.3.connected.trianglepath.dotted",
          tint: StudioTheme.mint
        )
        if !project.characterGraphHistory.isEmpty {
          graphMetric(
            "\(project.characterGraphHistory.count) 次确认",
            icon: "clock.arrow.circlepath",
            tint: StudioTheme.warm
          )
        }
      }
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 17)
    .background(.ultraThinMaterial)
  }

  private func graphMetric(_ text: String, icon: String, tint: Color) -> some View {
    Label(text, systemImage: icon)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .animatedStoryBubble(tint: tint, cornerRadius: 18)
  }

  private var emptyState: some View {
    VStack(spacing: 16) {
      Image(systemName: "person.3.sequence.fill")
        .font(.system(size: 38))
        .foregroundStyle(StudioTheme.accent)
      Text("先建立至少两个人物")
        .font(.title2.weight(.semibold))
      Text("关系图会直接读取项目人物档案，不建立重复人物库。")
        .foregroundStyle(.secondary)
    }
    .padding(32)
    .frame(maxWidth: .infinity, minHeight: 360)
    .animatedStoryBubble(tint: StudioTheme.accent, cornerRadius: 80, isSelected: true)
  }

  private var graphCanvas: some View {
    GeometryReader { geometry in
      ZStack {
        Canvas { context, size in
          for relationship in project.characterRelationships {
            guard let from = layout[relationship.fromCharacterID],
              let to = layout[relationship.toCharacterID]
            else {
              continue
            }
            let start = point(from, in: size)
            let end = point(to, in: size)
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(
              path,
              with: .color(
                color(for: relationship.kind).opacity(
                  relationship.isSecret ? 0.46 : 0.78
                )),
              style: StrokeStyle(
                lineWidth: 1.5 + Double(relationship.tension) / 35,
                dash: relationship.isSecret ? [6, 5] : []
              )
            )

            let middle = CGPoint(
              x: (start.x + end.x) / 2,
              y: (start.y + end.y) / 2
            )
            context.draw(
              Text(relationship.kind.rawValue)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color(for: relationship.kind)),
              at: middle
            )
          }
        }

        ForEach(characters) { character in
          characterNode(character)
            .position(
              point(
                layout[character.id] ?? .init(x: 0.5, y: 0.5),
                in: geometry.size
              )
            )
            .gesture(
              DragGesture(coordinateSpace: .named("character-graph"))
                .onChanged { value in
                  layout[character.id] = normalized(
                    value.location,
                    in: geometry.size
                  )
                }
                .onEnded { _ in
                  project.characterGraphLayout = layout
                  save()
                }
            )
        }
      }
      .coordinateSpace(name: "character-graph")
      .overlay(alignment: .topLeading) {
        Label("拖动人物重新布局 · 线条越粗，关系张力越高", systemImage: "hand.draw.fill")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .padding(18)
      }
    }
    .padding(8)
    .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 58, isSelected: true)
  }

  private func characterNode(_ character: StoryCharacter) -> some View {
    let isSelected = selectedCharacter?.id == character.id
    let tint = roleColor(character.role)
    return VStack(spacing: 6) {
      Image(systemName: roleIcon(character.role))
        .font(.title3)
        .foregroundStyle(.white)
        .frame(width: 38, height: 38)
        .background(tint, in: Circle())
      Text(character.name)
        .font(.caption.weight(.bold))
        .lineLimit(1)
      Text(character.role.rawValue)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 13)
    .padding(.vertical, 10)
    .frame(width: 116)
    .animatedStoryBubble(tint: tint, cornerRadius: 34, isSelected: isSelected)
    .onTapGesture {
      selectedCharacterID = character.id
      if targetCharacterID == character.id {
        targetCharacterID = characters.first { $0.id != character.id }?.id
      }
    }
  }

  @ViewBuilder
  private var characterInspector: some View {
    if let character = selectedCharacter {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 5) {
            EyebrowLabel(text: "SELECTED NODE", color: StudioTheme.accent)
            Text(character.name)
              .font(.system(.title2, design: .serif, weight: .semibold))
          }

          inspectorField("姓名", text: characterBinding(character, \.name))
          inspectorField("职业 / 身份", text: characterBinding(character, \.occupation))
          inspectorField("外部目标", text: characterBinding(character, \.externalGoal), axis: .vertical)
          inspectorField("秘密", text: characterBinding(character, \.secret), axis: .vertical)
          inspectorField("人物弧线", text: characterBinding(character, \.arc), axis: .vertical)

          Divider()

          VStack(alignment: .leading, spacing: 11) {
            Label("增加或更新关系", systemImage: "link.badge.plus")
              .font(.headline)

            Picker("连接到", selection: $targetCharacterID) {
              Text("选择人物").tag(UUID?.none)
              ForEach(characters.filter { $0.id != character.id }) { target in
                Text(target.name).tag(Optional(target.id))
              }
            }

            Picker("关系", selection: $relationshipKind) {
              ForEach(CharacterRelationshipKind.allCases) { kind in
                Text(kind.rawValue).tag(kind)
              }
            }

            TextField("这段关系怎样互相施压？", text: $relationshipDetail, axis: .vertical)
              .lineLimit(2...4)

            HStack {
              Text("张力")
                .font(.caption.weight(.semibold))
              Slider(value: $relationshipTension, in: 0...100)
              Text("\(Int(relationshipTension))")
                .font(.caption.monospacedDigit())
                .frame(width: 28)
            }

            Toggle("这是暂不公开的秘密关系", isOn: $relationshipIsSecret)
              .font(.caption)

            Button("写入关系图", systemImage: "plus.circle.fill") {
              addRelationship(from: character)
            }
            .buttonStyle(.borderedProminent)
            .disabled(targetCharacterID == nil)
          }
          .padding(14)
          .animatedStoryBubble(tint: StudioTheme.warm, cornerRadius: 36)

          let linked = project.characterRelationships.filter {
            $0.fromCharacterID == character.id || $0.toCharacterID == character.id
          }
          if !linked.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              Text("已连接")
                .font(.headline)
              ForEach(linked) { relationship in
                relationshipRow(relationship, selected: character)
              }
            }
          }
        }
        .padding(18)
        .animatedStoryBubble(
          tint: StudioTheme.accent,
          cornerRadius: 52,
          isSelected: true
        )
      }
    }
  }

  private func inspectorField(
    _ title: String,
    text: Binding<String>,
    axis: Axis = .horizontal
  ) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      TextField(title, text: text, axis: axis)
        .textFieldStyle(.roundedBorder)
        .lineLimit(axis == .vertical ? 2...5 : 1...1)
    }
    .padding(10)
    .animatedStoryBubble(tint: StudioTheme.sky, cornerRadius: 26)
  }

  private func relationshipRow(
    _ relationship: CharacterRelationship,
    selected: StoryCharacter
  ) -> some View {
    let otherID =
      relationship.fromCharacterID == selected.id
      ? relationship.toCharacterID
      : relationship.fromCharacterID
    let otherName = characters.first { $0.id == otherID }?.name ?? "未知人物"
    return HStack(alignment: .top, spacing: 8) {
      Circle()
        .fill(color(for: relationship.kind))
        .frame(width: 8, height: 8)
        .padding(.top, 5)
      VStack(alignment: .leading, spacing: 2) {
        Text("\(relationship.kind.rawValue) · \(otherName)")
          .font(.caption.weight(.semibold))
        Text(relationship.detail)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button {
        var relationships = project.characterRelationships
        relationships.removeAll { $0.id == relationship.id }
        project.characterRelationships = relationships
        save()
      } label: {
        Image(systemName: "trash")
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
    }
    .padding(9)
    .animatedStoryBubble(tint: color(for: relationship.kind), cornerRadius: 24)
  }

  private var aiAdjustmentStudio: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 5) {
          Label("AI人物关系导演", systemImage: "wand.and.stars")
            .font(.headline)
            .foregroundStyle(StudioTheme.mint)
          Text("写明你希望谁更复杂、谁应出现、哪段关系不够有力。AI只提出四套候选，确认后才更新关系图。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        if !project.characterGraphHistory.isEmpty {
          PhaseBadge(text: "保留 \(project.characterGraphHistory.count) 次确认历史")
        }
      }

      TextEditor(text: $graphInstruction)
        .font(.body)
        .scrollContentBackground(.hidden)
        .padding(10)
        .frame(minHeight: 76, maxHeight: 110)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topLeading) {
          if graphInstruction.isEmpty {
            Text("例如：女主和反派的关系太直接。增加一个双方都不愿伤害、却会泄露秘密的中间人物……")
              .font(.callout)
              .foregroundStyle(.tertiary)
              .padding(.horizontal, 15)
              .padding(.vertical, 18)
              .allowsHitTesting(false)
          }
        }

      Button {
        generateGraphOptions()
      } label: {
        if isGenerating {
          HStack {
            ProgressView().controlSize(.small)
            Text("正在设计四套关系变化…")
          }
        } else {
          Label("生成四个关系调整方案", systemImage: "square.grid.2x2.fill")
        }
      }
      .buttonStyle(.borderedProminent)
      .keyboardShortcut(.return, modifiers: [.command])
      .disabled(isGenerating)

      if let result = project.characterGraphOptions {
        Divider()
        if graphOptionsNeedRefresh {
          HStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack.fill")
              .font(.title3)
              .foregroundStyle(StudioTheme.warm)
            VStack(alignment: .leading, spacing: 3) {
              Text("这些方案还没有吸收项目的最新变化")
                .font(.callout.weight(.semibold))
              Text("创意、人物、关系或指令改变后，请先按最新上下文更新四套方案。")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("更新 4 个方案", systemImage: "arrow.clockwise") {
              generateGraphOptions()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGenerating)
          }
          .padding(13)
          .animatedStoryBubble(tint: StudioTheme.warm, cornerRadius: 30)
        }
        VStack(alignment: .leading, spacing: 4) {
          Text(result.question)
            .font(.system(.title3, design: .serif, weight: .semibold))
          Text(result.coachNote)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        BubbleWorkspaceConnector(
          tint: StudioTheme.accent,
          branchCount: max(result.options.count, 1),
          height: 44
        )

        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 310, maximum: 520), spacing: 13)],
          spacing: 13
        ) {
          ForEach(Array(result.options.enumerated()), id: \.element.id) { index, option in
            graphOptionCard(option, index: index)
          }
        }
      }
    }
    .padding(22)
    .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 58, isSelected: true)
  }

  private func graphOptionCard(
    _ option: CharacterGraphAdjustmentOption,
    index: Int
  ) -> some View {
    VStack(alignment: .leading, spacing: 11) {
      HStack {
        Text(["A", "B", "C", "D"][min(index, 3)])
          .font(.caption.monospaced().bold())
          .foregroundStyle(.white)
          .frame(width: 27, height: 27)
          .background(StudioTheme.accent, in: Circle())
        Text(option.title)
          .font(.title3.weight(.semibold))
      }
      Text(option.thesis)
        .font(.callout)

      graphOptionLine(
        "新增人物",
        option.newCharacters.isEmpty
          ? "不新增人物"
          : option.newCharacters.map(\.name).joined(separator: "、"),
        "person.badge.plus"
      )
      graphOptionLine(
        "人物调整",
        option.characterChanges.map {
          "\($0.name)：\($0.adjustment)"
        }.joined(separator: "\n"),
        "person.crop.circle.badge.checkmark"
      )
      graphOptionLine(
        "关系变化",
        option.relationshipChanges.map {
          "\($0.from) → \($0.to)：\($0.type) · \($0.detail)"
        }.joined(separator: "\n"),
        "link"
      )
      graphOptionLine("结构作用", option.structureEffect, "point.3.connected.trianglepath.dotted")
      graphOptionLine("情绪效果", option.emotionalEffect, "waveform.path.ecg")
      graphOptionLine("采用风险", option.risk, "exclamationmark.triangle")

      Button("确认并映射到人物关系图", systemImage: "checkmark.seal.fill") {
        apply(option)
      }
      .buttonStyle(.borderedProminent)
      .tint(StudioTheme.mint)
      .disabled(isGenerating || graphOptionsNeedRefresh)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .animatedStoryBubble(tint: optionTint(index), cornerRadius: 42)
  }

  private func optionTint(_ index: Int) -> Color {
    [StudioTheme.accent, StudioTheme.mint, StudioTheme.warm, StudioTheme.sky][min(index, 3)]
  }

  private func graphOptionLine(
    _ title: String,
    _ text: String,
    _ icon: String
  ) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: icon)
        .foregroundStyle(StudioTheme.accent)
        .frame(width: 18)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.caption2.weight(.bold))
          .foregroundStyle(.secondary)
        Text(text.isEmpty ? "无" : text)
          .font(.caption)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func generateGraphOptions() {
    let requestID = UUID()
    let engine = CharacterGraphEngine(settings: settings)
    let requestedInstruction = graphInstructionForAI
    let requestedFingerprint = engine.contextFingerprint(
      for: project,
      instruction: requestedInstruction
    )
    project.characterGraphRequestToken = requestID
    Task {
      isGenerating = true
      defer {
        if project.characterGraphRequestToken == requestID {
          project.characterGraphRequestToken = nil
        }
        isGenerating = false
      }
      do {
        let result = try await engine.generate(
          for: project,
          instruction: requestedInstruction
        )
        guard project.characterGraphRequestToken == requestID else {
          return
        }
        guard
          engine.contextFingerprint(
            for: project,
            instruction: graphInstructionForAI
          ) == requestedFingerprint
        else {
          errorMessage = "生成期间项目上下文发生了变化。旧响应已丢弃，请按最新状态重新生成。"
          showingError = true
          return
        }
        project.characterGraphOptions = result
        project.characterGraphOptionsFingerprint = requestedFingerprint
        project.characterGraphOptionsGeneratedAt = .now
        project.characterGraphLastInstruction = requestedInstruction
        try ProjectPersistenceStore.savePendingChanges(in: modelContext)
      } catch {
        if project.characterGraphRequestToken == requestID {
          present(error)
        }
      }
    }
  }

  private func apply(_ option: CharacterGraphAdjustmentOption) {
    var history = project.characterGraphHistory
    history.append(
      CharacterGraphRevision(
        optionTitle: option.title,
        authorInstruction: graphInstructionForAI,
        relationshipsBefore: project.characterRelationships
      ))
    project.characterGraphHistory = Array(history.suffix(40))

    for proposal in option.newCharacters {
      guard !proposal.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        project.characters.first(where: {
          $0.name.caseInsensitiveCompare(proposal.name) == .orderedSame
        }) == nil
      else {
        continue
      }
      let character = StoryCharacter(
        name: proposal.name,
        role: CharacterRole(rawValue: proposal.role) ?? .supporting,
        seedText: proposal.seedText,
        externalGoal: proposal.externalGoal,
        secret: proposal.secret,
        project: project
      )
      modelContext.insert(character)
      project.characters.append(character)
    }

    for change in option.characterChanges {
      guard let character = character(named: change.name),
        !change.adjustment.isEmpty
      else {
        continue
      }
      let marker = "【关系图确认 · \(option.title)】"
      character.seedText +=
        character.seedText.isEmpty
        ? "\(marker)\n\(change.adjustment)"
        : "\n\n\(marker)\n\(change.adjustment)"
      character.touch()
    }

    var relationships = project.characterRelationships
    for proposal in option.relationshipChanges {
      guard let from = character(named: proposal.from),
        let to = character(named: proposal.to),
        from.id != to.id
      else {
        continue
      }
      let kind = CharacterRelationshipKind(rawValue: proposal.type) ?? .alliance
      if let index = relationships.firstIndex(where: {
        $0.fromCharacterID == from.id && $0.toCharacterID == to.id
      }) {
        relationships[index].kind = kind
        relationships[index].detail = proposal.detail
        relationships[index].tension = proposal.tension
        relationships[index].isSecret = proposal.isSecret
      } else {
        relationships.append(
          CharacterRelationship(
            fromCharacterID: from.id,
            toCharacterID: to.id,
            kind: kind,
            detail: proposal.detail,
            tension: proposal.tension,
            isSecret: proposal.isSecret
          ))
      }
    }
    project.characterRelationships = relationships
    project.characterGraphOptions = nil
    project.characterGraphOptionsFingerprint = ""
    project.characterGraphOptionsGeneratedAt = nil
    project.characterGraphRequestToken = nil
    project.touch()
    initializeLayout()
    save()
  }

  private func addRelationship(from character: StoryCharacter) {
    guard let targetCharacterID, targetCharacterID != character.id else { return }
    var relationships = project.characterRelationships
    if let index = relationships.firstIndex(where: {
      $0.fromCharacterID == character.id && $0.toCharacterID == targetCharacterID
    }) {
      relationships[index].kind = relationshipKind
      relationships[index].detail = relationshipDetail
      relationships[index].tension = Int(relationshipTension)
      relationships[index].isSecret = relationshipIsSecret
    } else {
      relationships.append(
        CharacterRelationship(
          fromCharacterID: character.id,
          toCharacterID: targetCharacterID,
          kind: relationshipKind,
          detail: relationshipDetail,
          tension: Int(relationshipTension),
          isSecret: relationshipIsSecret
        ))
    }
    project.characterRelationships = relationships
    relationshipDetail = ""
    save()
  }

  private func character(named name: String) -> StoryCharacter? {
    project.characters.first {
      $0.name.caseInsensitiveCompare(name.trimmingCharacters(in: .whitespacesAndNewlines))
        == .orderedSame
    }
  }

  private func initializeLayout() {
    var stored = project.characterGraphLayout
    let count = max(characters.count, 1)
    for (index, character) in characters.enumerated() where stored[character.id] == nil {
      let angle = (Double(index) / Double(count)) * Double.pi * 2 - Double.pi / 2
      let radius = characters.count == 1 ? 0 : 0.34
      stored[character.id] = CharacterGraphLayoutPoint(
        x: 0.5 + cos(angle) * radius,
        y: 0.5 + sin(angle) * radius
      )
    }
    layout = stored.filter { point in
      characters.contains { $0.id == point.key }
    }
    project.characterGraphLayout = layout
  }

  private func point(_ normalized: CharacterGraphLayoutPoint, in size: CGSize) -> CGPoint {
    CGPoint(
      x: max(70, min(size.width - 70, normalized.x * size.width)),
      y: max(70, min(size.height - 70, normalized.y * size.height))
    )
  }

  private func normalized(_ point: CGPoint, in size: CGSize) -> CharacterGraphLayoutPoint {
    CharacterGraphLayoutPoint(
      x: max(0.06, min(0.94, point.x / max(size.width, 1))),
      y: max(0.08, min(0.92, point.y / max(size.height, 1)))
    )
  }

  private func characterBinding(
    _ character: StoryCharacter,
    _ keyPath: ReferenceWritableKeyPath<StoryCharacter, String>
  ) -> Binding<String> {
    Binding(
      get: { character[keyPath: keyPath] },
      set: {
        character[keyPath: keyPath] = $0
        character.touch()
      }
    )
  }

  private func color(for kind: CharacterRelationshipKind) -> Color {
    switch kind {
    case .family: .orange
    case .love: .pink
    case .alliance: StudioTheme.mint
    case .rivalry: .yellow
    case .control: .purple
    case .debt: .brown
    case .mentor: .cyan
    case .secret: .indigo
    case .hostility: .red
    }
  }

  private func roleColor(_ role: CharacterRole) -> Color {
    switch role {
    case .protagonist: StudioTheme.accent
    case .antagonist: .red
    case .ally: StudioTheme.mint
    case .supporting: StudioTheme.mint
    case .mentor: .cyan
    case .loveInterest: .pink
    case .mirror: StudioTheme.warm
    }
  }

  private func roleIcon(_ role: CharacterRole) -> String {
    switch role {
    case .protagonist: "star.fill"
    case .antagonist: "bolt.fill"
    case .ally: "person.2.fill"
    case .supporting: "person.fill"
    case .mentor: "lightbulb.fill"
    case .loveInterest: "heart.fill"
    case .mirror: "circle.lefthalf.filled"
    }
  }

  private func save() {
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

@MainActor
private struct CharacterGraphEngine {
  let settings: AISettingsStore

  func contextFingerprint(
    for project: StoryProject,
    instruction: String
  ) -> String {
    let payload = """
      character-graph-options-v1
      模型：\(settings.model)
      思考模式：\(settings.thinkingEnabled)
      Apple 预处理：\(settings.useApplePreprocessing)
      知识库：\(settings.useKnowledgeBase)
      项目：\(project.title)
      类型：\(project.genre.rawValue)
      结构：\(project.structureTemplate.name)
      \(project.structureRulesForPrompt)
      一句话：\(project.logline)
      主题：\(project.themeText.isEmpty ? project.themeBibleText : project.themeText)
      核心冲突：\(project.coreConflictText.isEmpty ? project.dramaticPromise : project.coreConflictText)
      已确认路径：\(project.storyPathText)
      \(project.protectedCreativeContext(for: nil))
      \(graphContext(project))
      作者指令：\(instruction)
      \(ProjectPreferenceEngine.promptBlock(for: project))
      """
    let digest = SHA256.hash(data: Data(payload.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  func generate(
    for project: StoryProject,
    instruction: String
  ) async throws -> CharacterGraphOptionsResult {
    let graph = graphContext(project)
    let rawContext = """
      项目：\(project.title)
      类型：\(project.genre.rawValue)
      锁定结构：\(project.structureTemplate.name)
      \(project.structureRulesForPrompt)
      一句话：\(project.logline)
      主题：\(project.themeText.isEmpty ? project.themeBibleText : project.themeText)
      核心冲突：\(project.coreConflictText.isEmpty ? project.dramaticPromise : project.coreConflictText)
      项目方向与后来注入：\(project.creativeContext())
      已确认路径：
      \(project.storyPathText)
      """
    let prepared = await AppleTextService.prepareForAnalysis(
      rawContext,
      enabled: settings.useApplePreprocessing
    )
    let protectedProjectContext = """
      \(prepared.text)

      \(project.protectedCreativeContext(for: nil))
      """
    let theory: [TheoryEvidence]
    if settings.useKnowledgeBase {
      theory =
        (try? await TheoryIndexStore.shared.search(
          query: "人物关系 人物网 对手 盟友 背叛 \(instruction) \(graph)",
          route: TheoryRouting.route(for: .characters),
          maximumMatches: 5,
          maximumCharacters: 2_600
        )) ?? []
    } else {
      theory = []
    }
    let completion = try await DeepSeekClient(
      configuration: settings.configuration()
    ).generateCharacterGraphOptions(
      CharacterGraphAIContext(
        projectContext: protectedProjectContext,
        characterGraph: graph,
        authorInstruction: instruction,
        preferenceContext: ProjectPreferenceEngine.promptBlock(for: project),
        theoryContext: theory.map(\.promptBlock).joined(separator: "\n\n")
      )
    )
    return completion.result
  }

  private func graphContext(_ project: StoryProject) -> String {
    let people = project.characters
      .sorted {
        if $0.name == $1.name {
          return $0.id.uuidString < $1.id.uuidString
        }
        return $0.name < $1.name
      }
      .map { character in
        """
        \(character.name)（\(character.role.rawValue)）
        身份：\(character.occupation)
        描述：\(character.seedText)
        目标：\(character.externalGoal)
        需求：\(character.internalNeed)
        秘密：\(character.secret)
        弧线：\(character.arc)
        """
      }.joined(separator: "\n\n")
    let relationships = project.characterRelationships
      .sorted { $0.id.uuidString < $1.id.uuidString }
      .map { relationship in
        let from = project.characters.first { $0.id == relationship.fromCharacterID }?.name ?? "未知"
        let to = project.characters.first { $0.id == relationship.toCharacterID }?.name ?? "未知"
        return
          "\(from) → \(to)：\(relationship.kind.rawValue)，张力\(relationship.tension)，\(relationship.detail)"
      }.joined(separator: "\n")
    return """
      【人物】
      \(people.isEmpty ? "尚无人物。" : people)

      【正式关系】
      \(relationships.isEmpty ? "尚未建立关系边。" : relationships)
      """
  }
}
