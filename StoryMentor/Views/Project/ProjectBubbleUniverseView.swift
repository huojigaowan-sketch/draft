import SwiftUI

/// Deterministic story map: animated enough to show flow, stable enough to read.
@MainActor
struct ProjectBubbleUniverseView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @Bindable var project: StoryProject
  let onNavigate: (WorkspaceSection) -> Void

  @State private var haloExpanded = false

  var body: some View {
    GlassEffectContainer(spacing: 28) {
      VStack(spacing: 34) {
        storyNucleus
        screenplayEvidenceNucleus
        majorBeatSection
        satelliteSection
      }
      .frame(maxWidth: .infinity)
    }
    .frame(maxWidth: .infinity)
    .onAppear { haloExpanded = !reduceMotion }
    .onChange(of: reduceMotion) { _, newValue in
      haloExpanded = !newValue
    }
  }

  private var storyNucleus: some View {
    StoryNucleusBubble(
      title: project.title,
      logline: preferredText(
        project.logline,
        fallback: project.projectSummary,
        placeholder: "故事核心尚待形成。"
      ).bubbleExcerpt(limit: 460),
      dramaticQuestion: project.dramaticPromise.bubbleExcerpt(limit: 240),
      structureName: project.isStructureLocked
        ? project.structureTemplate.name
        : (project.hasSelectedStructureTemplate ? "结构待固定" : "结构待选择"),
      haloExpanded: haloExpanded,
      reduceMotion: reduceMotion
    )
  }

  @ViewBuilder
  private var screenplayEvidenceNucleus: some View {
    if let projection = DramaticProjectionEngine.projection(
      .project,
      key: "root",
      in: project
    ) {
      VStack(alignment: .leading, spacing: 9) {
        HStack {
          Label("正文反向归纳", systemImage: "arrow.up.backward.and.arrow.down.forward")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(StudioTheme.mint)
          Spacer()
          Text("\(projection.metrics.effectiveUpdateCount) 次有效更新")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        Text(projection.summary.bubbleExcerpt(limit: 520))
          .font(.system(size: 16, weight: .medium, design: .serif))
          .lineSpacing(4)
          .fixedSize(horizontal: false, vertical: true)
        if !projection.realizationGap.isBubbleBlank {
          Text(projection.realizationGap)
            .font(.caption)
            .foregroundStyle(.orange)
        }
        Text("这是由正文证据生成的提案，不会覆盖作者的一句话故事。")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 24)
      .padding(.vertical, 18)
      .frame(maxWidth: 780, alignment: .leading)
      .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 46)
      .frame(maxWidth: .infinity)
    }
  }

  private var majorBeatSection: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Label("全本因果路径", systemImage: "point.3.connected.trianglepath.dotted")
          .font(.system(size: 22, weight: .semibold, design: .rounded))
        Spacer(minLength: 12)
        if !majorBeats.isEmpty {
          Text("已选择 \(majorBeats.count { $0.status == .resolved }) / \(majorBeats.count)")
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
        }
      }

      if majorBeats.isEmpty {
        MissingStructureBubble { onNavigate(.templates) }
      } else {
        MajorBeatConstellationView(
          beats: majorBeats,
          haloExpanded: haloExpanded,
          reduceMotion: reduceMotion
        ) { stageIndex in
          project.requestedStructureStageIndex = stageIndex
          onNavigate(.journey)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var satelliteSection: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Label("人物 · 世界 · 主题", systemImage: "circle.hexagongrid.fill")
          .font(.system(size: 22, weight: .semibold, design: .rounded))
        Spacer(minLength: 12)
        Text("随每次选择动态同步")
          .font(.system(size: 13.5, weight: .medium))
          .foregroundStyle(.secondary)
      }

      LazyVGrid(
        columns: [
          GridItem(
            .adaptive(minimum: 280, maximum: 430),
            spacing: 18,
            alignment: .top
          )
        ],
        alignment: .center,
        spacing: 18
      ) {
        ForEach(Array(satellites.enumerated()), id: \.element.id) { index, satellite in
          SatelliteBubble(
            model: satellite,
            haloExpanded: haloExpanded,
            reduceMotion: reduceMotion,
            animationDelay: Double(index % 5) * 0.14
          ) {
            project.requestedCharacterID = satellite.characterID
            onNavigate(satellite.route)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var majorBeats: [ProjectMajorBeatBubble] {
    guard project.isStructureLocked else { return [] }

    return project.structureTemplate.stages.enumerated().map { index, stage in
      let decision = project.decisions.first { $0.stageIndex == index }
      let selectedOption = decision?.selectedOption
      let status: ProjectMajorBeatBubble.Status

      if selectedOption != nil {
        status = .resolved
      } else if project.nextStructureStageIndex == index {
        status = .current
      } else {
        status = .pending
      }

      let scenes = project.sceneContracts.filter {
        $0.structureStageIndex == index
      }
      let confirmedSceneCount = scenes.count {
        $0.selectedSceneOptionID != nil
      }
      let microBeats = scenes.flatMap(\.microBeats)
      let confirmedMicroBeatCount = microBeats.count {
        $0.selectedOption != nil
      }
      let realized = DramaticProjectionEngine.projection(
        .stage,
        key: String(index),
        in: project
      )

      return ProjectMajorBeatBubble(
        id: stage.id,
        index: index,
        stageName: stage.name,
        title: selectedOption?.title
          ?? (status == .current ? "等待当前选择" : "尚未选择方案"),
        summary: (realized?.summary ?? selectedOption?.pitch ?? stage.choiceFocus).bubblePlainText,
        sceneProgress: scenes.isEmpty
          ? "场景未展开"
          : "场景 \(confirmedSceneCount)/\(scenes.count)",
        microBeatProgress: realized.map {
          "正文实证 \($0.metrics.effectiveUpdateCount) 次"
        } ?? (microBeats.isEmpty
          ? nil
          : "计划更新 \(confirmedMicroBeatCount)/\(microBeats.count)"),
        status: status
      )
    }
  }

  private var satellites: [ProjectSatelliteBubble] {
    var bubbles = [themeBubble, worldBubble]
    let characters = project.characters.sorted(by: characterOrder)

    if characters.isEmpty {
      bubbles.append(
        ProjectSatelliteBubble(
          id: "characters-empty",
          eyebrow: "人物",
          title: "人物尚待建立",
          body: "人物会围绕故事核心形成各自的欲望、需求与压力。",
          detail: "点击进入人物工作台",
          icon: "person.2.fill",
          tint: StudioTheme.sky,
          characterID: nil,
          route: .characters
        )
      )
    } else {
      bubbles.append(contentsOf: characters.map(characterBubble))
    }

    if let relationshipBubble {
      bubbles.append(relationshipBubble)
    }
    return bubbles
  }

  private var themeBubble: ProjectSatelliteBubble {
    let projection = DramaticProjectionEngine.projection(.theme, key: "root", in: project)
    return ProjectSatelliteBubble(
      id: "theme",
      eyebrow: "主题",
      title: "故事最终要回答什么？",
      body: preferredText(
        projection?.summary ?? "",
        fallback: preferredText(project.themeText, fallback: project.themeBibleText, placeholder: ""),
        placeholder: "主题命题尚待故事回答。"
      ).bubblePlainText,
      detail: projection.map { "正文 \($0.evidenceIDs.count) 条证据" } ?? "贯穿全本的价值判断",
      icon: "scope",
      tint: StudioTheme.warm,
      characterID: nil,
      route: .theme
    )
  }

  private var worldBubble: ProjectSatelliteBubble {
    let projection = DramaticProjectionEngine.projection(.world, key: "root", in: project)
    return ProjectSatelliteBubble(
      id: "world",
      eyebrow: "世界",
      title: "故事受什么规则约束？",
      body: preferredText(
        projection?.summary ?? "",
        fallback: preferredText(project.worldText, fallback: project.worldBibleText, placeholder: ""),
        placeholder: "世界规则尚待建立。"
      ).bubblePlainText,
      detail: projection.map { "正文已建立 \($0.evidenceIDs.count) 条证据" }
        ?? "\(project.canonicalFacts.count) 条动态事实",
      icon: "globe.asia.australia.fill",
      tint: StudioTheme.mint,
      characterID: nil,
      route: .world
    )
  }

  private func characterBubble(_ character: StoryCharacter) -> ProjectSatelliteBubble {
    let projection = DramaticProjectionEngine.projection(
      .character,
      key: character.id.uuidString,
      in: project
    )
    let goal = preferredText(
      character.externalGoal,
      fallback: character.internalNeed,
      placeholder: character.seedText.bubbleExcerpt(limit: 220)
    )
    return ProjectSatelliteBubble(
      id: "character-\(character.id.uuidString)",
      eyebrow: "人物",
      title: character.name,
      body: (projection?.summary ?? (goal.isBubbleBlank ? "人物动机尚待建立。" : goal)).bubblePlainText,
      detail: projection.map { "\(character.role.rawValue) · 正文 \($0.evidenceIDs.count) 条证据" }
        ?? character.role.rawValue,
      icon: character.role == .protagonist
        ? "person.crop.circle.fill"
        : "person.fill",
      tint: characterTint(for: character.role),
      characterID: character.id,
      route: .characters
    )
  }

  private var relationshipBubble: ProjectSatelliteBubble? {
    let relationships = project.characterRelationships
      .sorted { $0.tension > $1.tension }
    let projection = DramaticProjectionEngine.projection(.relationship, key: "root", in: project)
    guard !relationships.isEmpty || projection != nil else { return nil }

    let names = Dictionary(
      uniqueKeysWithValues: project.characters.map {
        ($0.id, $0.name)
      })
    let plannedSummary = relationships.prefix(4).map { relationship in
      let source = names[relationship.fromCharacterID] ?? "未知人物"
      let target = names[relationship.toCharacterID] ?? "未知人物"
      return "\(source) ↔ \(target)：\(relationship.kind.rawValue)"
    }.joined(separator: " · ")

    return ProjectSatelliteBubble(
      id: "relationships",
      eyebrow: "关系",
      title: "人物之间如何彼此施压？",
      body: (projection?.summary ?? plannedSummary).bubbleExcerpt(limit: 300),
      detail: projection.map { "正文 \($0.evidenceIDs.count) 条关系变化证据" }
        ?? "\(relationships.count) 条动态关系",
      icon: "point.3.connected.trianglepath.dotted",
      tint: Color(red: 0.50, green: 0.45, blue: 0.82),
      characterID: nil,
      route: .relationships
    )
  }

  private func preferredText(
    _ value: String,
    fallback: String,
    placeholder: String
  ) -> String {
    if !value.isBubbleBlank { return value }
    if !fallback.isBubbleBlank { return fallback }
    return placeholder
  }

  private func characterOrder(_ lhs: StoryCharacter, _ rhs: StoryCharacter) -> Bool {
    let lhsRank = characterRoleRank(lhs.role)
    let rhsRank = characterRoleRank(rhs.role)
    if lhsRank == rhsRank {
      return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
    return lhsRank < rhsRank
  }

  private func characterRoleRank(_ role: CharacterRole) -> Int {
    switch role {
    case .protagonist: 0
    case .antagonist: 1
    case .loveInterest: 2
    case .ally: 3
    case .mirror: 4
    case .mentor: 5
    case .supporting: 6
    }
  }

  private func characterTint(for role: CharacterRole) -> Color {
    switch role {
    case .protagonist: StudioTheme.warm
    case .antagonist: Color(red: 0.82, green: 0.34, blue: 0.38)
    case .loveInterest: Color(red: 0.78, green: 0.42, blue: 0.65)
    case .ally, .mentor: StudioTheme.mint
    case .mirror: Color(red: 0.50, green: 0.45, blue: 0.82)
    case .supporting: StudioTheme.sky
    }
  }
}

struct ProjectMajorBeatBubble: Identifiable {
  enum Status: Equatable {
    case resolved
    case current
    case pending
  }

  let id: String
  let index: Int
  let stageName: String
  let title: String
  let summary: String
  let sceneProgress: String
  let microBeatProgress: String?
  let status: Status

  var tint: Color {
    switch status {
    case .resolved: StudioTheme.mint
    case .current: StudioTheme.accent
    case .pending: StudioTheme.sky
    }
  }

  var statusLabel: String {
    switch status {
    case .resolved: "已选择"
    case .current: "当前"
    case .pending: "待选择"
    }
  }

  var statusIcon: String {
    switch status {
    case .resolved: "checkmark.circle.fill"
    case .current: "location.fill"
    case .pending: "circle"
    }
  }

  var overviewSummary: String {
    let source =
      summary.isBubbleBlank
      ? "这一大节拍尚待确定主要内容。"
      : summary
    return source.bubbleExcerpt(limit: 60)
  }
}

struct ProjectSatelliteBubble: Identifiable {
  let id: String
  let eyebrow: String
  let title: String
  let body: String
  let detail: String
  let icon: String
  let tint: Color
  let characterID: UUID?
  let route: WorkspaceSection
}
