import Foundation
import FoundationModels

@Generable
nonisolated private struct GuidedCompiledMutationDraft {
  @Guide(description: "只能是：世界事实、认知与信念、目标与策略、关系与权力、承诺与规范、观众认知")
  var dimension: String
  var subject: String
  var holder: String
  var beforeValue: String
  var afterValue: String
}

@Generable
nonisolated private struct GuidedCompiledBeatDraft {
  var purpose: String
  var dramaticAction: String
  var characterAction: String
  var opposition: String
  var turn: String
  var outcome: String

  @Guide(description: "可以直接进入当前 Fountain 场景的连续动作或对白片段，不含场景标题")
  var screenplayText: String

  var mutations: [GuidedCompiledMutationDraft]
  var audienceUpdate: String
}

@Generable
nonisolated private struct GuidedCompiledCharacterDraft {
  var name: String

  @Guide(description: "主人公、对抗者、盟友、配角中的一种")
  var role: String

  var visibleBehavior: String
  var immediateGoal: String
  var fearOrDefense: String
}

@Generable
nonisolated private struct GuidedEchoFindingDraft {
  @Guide(description: "只能是：人物、情节、关系、可拍画面、声音、生活与世界、结构推进")
  var kind: String
  var title: String
  var effect: String

  @Guide(description: "必须逐字摘录作者本轮原文中的短句，不能改写")
  var evidence: String
}

@Generable
nonisolated private struct GuidedSceneCompilationDraft {
  @Guide(description: "完整且可直接进入 Final Draft 工作流的单场 Fountain 正文，必须从中文场景标题开始")
  var fountainText: String

  var heading: String
  var pointOfView: String
  var characterGoal: String
  var obstacle: String
  var turn: String
  var outcome: String
  var nextPressure: String

  @Guide(description: "本场对当前结构阶段真正完成的一个决定或状态变化")
  var stageDecision: String

  @Guide(description: "这个决定造成的直接代价")
  var stageCost: String

  @Guide(description: "正文中证明结构变化已经发生的可见或可听证据")
  var stageEvidence: String

  @Guide(description: "按因果顺序排列的一至十二个必要情境更新")
  var beats: [GuidedCompiledBeatDraft]

  var characters: [GuidedCompiledCharacterDraft]
  var echoHeadline: String

  @Guide(description: "二至六项基于作者原文的创作回声；每项都必须引用逐字证据")
  var echoFindings: [GuidedEchoFindingDraft]

  @Guide(description: "一至六句最值得原样保留的作者原句")
  var preservedQuotes: [String]
}

@MainActor
struct GuidedFinalDraftCompilerEngine {
  let settings: AISettingsStore

  func compile(
    sourceScene: String,
    contract: SceneContract,
    stage: StructureStage,
    project: StoryProject,
    scale: GuidedScriptScale
  ) async throws -> GuidedSceneCompilationResult {
    let scenes = FountainParser.scenes(in: project.screenplayText)
    let sceneIndex = max(0, contract.sceneIndex - 1)
    let previousScene = sceneIndex > 0 && scenes.indices.contains(sceneIndex - 1)
      ? String(scenes[sceneIndex - 1].text.suffix(2_400))
      : "这是全片第一场。"
    let nextScene = scenes.indices.contains(sceneIndex + 1)
      ? String(scenes[sceneIndex + 1].text.prefix(1_800))
      : "这是当前规划中的最后一场。"

    let retrievalQuery = [
      project.title,
      project.genre.rawValue,
      project.structureTemplate.name,
      stage.name,
      stage.purpose,
      stage.choiceFocus,
      contract.scopePurpose,
      sourceScene,
    ]
    .joined(separator: " ")

    let theory: [TheoryEvidence]
    if settings.useKnowledgeBase {
      theory = (try? await TheoryIndexStore.shared.search(
        query: String(retrievalQuery.prefix(3_600)),
        route: TheoryRouting.route(for: .screenplay),
        maximumMatches: 6,
        maximumCharacters: 3_200
      )) ?? []
    } else {
      theory = []
    }
    let storyDNA = StoryDNAService.shared.matches(
      query: retrievalQuery,
      genre: project.genre.rawValue,
      limit: 3
    )

    let session = StoryLanguageRuntime.session(
      configuration: try settings.configuration(),
      instructions: compilerInstructions
    )
    let response = try await session.respond(
      to: """
      【作者已选择并锁定的结构】
      \(project.structureRulesForPrompt)

      【当前结构义务】
      阶段：\(stage.name)
      功能：\(stage.purpose)
      选择焦点：\(stage.choiceFocus)

      【当前场景槽位】
      场 \(contract.sceneIndex) · 本阶段第 \(contract.stageSceneOrdinal) 场
      范围：\(contract.scopeTitle)
      场景职责：\(contract.scopePurpose)
      进入状态：\(contract.scopeEntryState)
      必须到达：\(contract.scopeExitState)

      【项目事实与作者材料】
      项目：\(project.title)
      类型：\(project.genre.rawValue)
      一句话：\(project.logline)
      戏剧问题：\(project.dramaticPromise)
      人物与剧本圣经：
      \(project.storyBibleDigest)
      作者创意：
      \(project.protectedCreativeContext(for: contract.structureStageIndex))
      作者原始创作卡：
      \(project.artifacts
        .filter { $0.status == .integrated }
        .sorted { $0.updatedAt < $1.updatedAt }
        .suffix(10)
        .map { "【\($0.title)】\n\($0.humanInput)" }
        .joined(separator: "\n\n"))

      【上一场】
      \(previousScene)

      【作者在 Final Draft 工作区写下的当前场】
      \(String(sourceScene.prefix(16_000)))

      【下一场】
      \(nextScene)

      【专业编剧知识库】
      \(theory.isEmpty ? "本轮没有命中专门条目。" : theory.map(\.promptBlock).joined(separator: "\n\n"))

      【经典作品功能参考】
      \(storyDNA.isEmpty ? "本轮不使用案例。" : storyDNA.map(\.promptBlock).joined(separator: "\n\n"))

      【篇幅目标】
      \(scale.rawValue)；当前场按 \(scale.defaultSceneLength.prompt)

      将作者当前场整理成一个专业、可拍、完整的 Fountain 场景。必须最大限度保留作者已经写出的具体动作、对白、物件、生活细节和独特语气。小说式心理解释只能转化为可见行动、潜台词、声音或必要对白，不得丢失其人物含义。

      同时只填充本场能够证明的结构、场景与情境更新；不得替作者生成后续结构阶段，不得一次完成全片。创作回声必须用作者原文逐字证据说明作者已经创造出了什么。
      """,
      generating: GuidedSceneCompilationDraft.self,
      options: GenerationOptions(
        temperature: 0.34,
        maximumResponseTokens: maximumTokens(for: scale)
      )
    )

    return try validatedResult(
      response.content,
      sourceScene: sourceScene,
      contract: contract,
      stage: stage,
      knowledgeSources: theory.map(\.sourceLabel)
    )
  }

  static func localResult(
    sourceScene: String,
    contract: SceneContract,
    stage: StructureStage
  ) throws -> GuidedSceneCompilationResult {
    guard ScreenplayDraftOptionPolicy.isProfessionalSceneText(sourceScene) else {
      throw GuidedFinalDraftCompilerError.requiresProfessionalElementsOrAI
    }
    let scene = FountainParser.scenes(in: sourceScene).first
    let heading = scene?.heading ?? contract.heading
    let bodyLines = sourceScene
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && !FountainParser.isSceneHeading($0) }
    let evidence = bodyLines.first ?? "当前场景已经形成可拍摄正文"
    let outcome = bodyLines.last ?? evidence
    let mutation = GuidedCompiledMutation(
      dimensionRawValue: DramaticStateDimension.world.rawValue,
      subject: stage.name,
      holder: contract.pointOfView,
      beforeValue: contract.scopeEntryState.isEmpty ? "进入本场前" : contract.scopeEntryState,
      afterValue: outcome
    )
    return GuidedSceneCompilationResult(
      fountainText: sourceScene,
      heading: heading,
      pointOfView: contract.pointOfView.isEmpty ? "当前视点人物" : contract.pointOfView,
      characterGoal: contract.characterGoal.isEmpty ? stage.choiceFocus : contract.characterGoal,
      obstacle: contract.obstacle.isEmpty ? "由正文中的反作用力形成" : contract.obstacle,
      turn: contract.turn.isEmpty ? outcome : contract.turn,
      outcome: contract.outcome.isEmpty ? outcome : contract.outcome,
      nextPressure: contract.nextPressure.isEmpty ? "承接下一场结构义务" : contract.nextPressure,
      stageDecision: contract.outcome.isEmpty ? outcome : contract.outcome,
      stageCost: contract.obstacle.isEmpty ? "人物为当前行动承担后果" : contract.obstacle,
      stageEvidence: evidence,
      beats: [
        GuidedCompiledBeat(
          purpose: stage.purpose,
          dramaticAction: evidence,
          characterAction: evidence,
          opposition: contract.obstacle.isEmpty ? "正文中的直接反作用" : contract.obstacle,
          turn: outcome,
          outcome: outcome,
          screenplayText: bodyLines.joined(separator: "\n"),
          mutations: [mutation],
          audienceUpdate: outcome
        )
      ],
      characters: [],
      echoHeadline: "你的文字已经成为一场正式剧本。",
      echoFindings: [
        GuidedScreenplayEchoFinding(
          kind: .image,
          title: "可拍摄内容已经成立",
          effect: "这句文字已经直接进入正式场景，而不是被当作提示词丢弃。",
          evidence: evidence
        )
      ],
      preservedQuotes: [evidence],
      knowledgeSources: []
    )
  }

  private func validatedResult(
    _ draft: GuidedSceneCompilationDraft,
    sourceScene: String,
    contract: SceneContract,
    stage: StructureStage,
    knowledgeSources: [String]
  ) throws -> GuidedSceneCompilationResult {
    let fountain = FountainParser.localizingSceneHeadings(
      in: draft.fountainText
    )
    guard FountainParser.scenes(in: fountain).count == 1,
          ScreenplayDraftOptionPolicy.isProfessionalSceneText(fountain) else {
      throw GuidedFinalDraftCompilerError.invalidProfessionalScene
    }

    let source = sourceScene.trimmingCharacters(in: .whitespacesAndNewlines)
    let preserved = draft.preservedQuotes
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && source.contains($0) }
    var findings = draft.echoFindings.compactMap { item -> GuidedScreenplayEchoFinding? in
      let evidence = item.evidence.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !evidence.isEmpty, source.contains(evidence) else { return nil }
      return GuidedScreenplayEchoFinding(
        kind: echoKind(item.kind),
        title: item.title,
        effect: item.effect,
        evidence: evidence
      )
    }
    if findings.isEmpty, let quote = preserved.first {
      findings = [
        GuidedScreenplayEchoFinding(
          kind: .voice,
          title: "作者原句已经进入正式场景",
          effect: "系统保留了你的具体表达，并让它承担可拍摄的戏剧功能。",
          evidence: quote
        )
      ]
    }

    let beats = Array(draft.beats.prefix(12)).map { beat in
      GuidedCompiledBeat(
        purpose: beat.purpose,
        dramaticAction: beat.dramaticAction,
        characterAction: beat.characterAction,
        opposition: beat.opposition,
        turn: beat.turn,
        outcome: beat.outcome,
        screenplayText: beat.screenplayText,
        mutations: beat.mutations.map {
          GuidedCompiledMutation(
            dimensionRawValue: dimension($0.dimension).rawValue,
            subject: $0.subject,
            holder: $0.holder,
            beforeValue: $0.beforeValue,
            afterValue: $0.afterValue
          )
        },
        audienceUpdate: beat.audienceUpdate
      )
    }
    guard !beats.isEmpty else {
      throw GuidedFinalDraftCompilerError.missingDramaticUpdates
    }

    let characters = draft.characters.prefix(12).map {
      GuidedCompiledCharacter(
        name: $0.name,
        roleRawValue: $0.role,
        visibleBehavior: $0.visibleBehavior,
        immediateGoal: $0.immediateGoal,
        fearOrDefense: $0.fearOrDefense
      )
    }

    return GuidedSceneCompilationResult(
      fountainText: fountain,
      heading: draft.heading.isEmpty
        ? (FountainParser.scenes(in: fountain).first?.heading ?? contract.heading)
        : draft.heading,
      pointOfView: draft.pointOfView,
      characterGoal: draft.characterGoal,
      obstacle: draft.obstacle,
      turn: draft.turn,
      outcome: draft.outcome,
      nextPressure: draft.nextPressure,
      stageDecision: draft.stageDecision.isEmpty ? draft.outcome : draft.stageDecision,
      stageCost: draft.stageCost.isEmpty ? draft.obstacle : draft.stageCost,
      stageEvidence: draft.stageEvidence.isEmpty ? draft.turn : draft.stageEvidence,
      beats: beats,
      characters: characters,
      echoHeadline: draft.echoHeadline.isEmpty
        ? "你的文字已经推动了“\(stage.name)”。"
        : draft.echoHeadline,
      echoFindings: Array(findings.prefix(6)),
      preservedQuotes: Array(preserved.prefix(6)),
      knowledgeSources: knowledgeSources
    )
  }

  private func maximumTokens(for scale: GuidedScriptScale) -> Int {
    switch scale {
    case .shortDrama: 4_200
    case .shortFilm: 5_800
    case .feature: 7_200
    }
  }

  private func echoKind(_ value: String) -> GuidedScreenplayEchoKind {
    GuidedScreenplayEchoKind.allCases.first {
      value.contains($0.rawValue) || $0.rawValue.contains(value)
    } ?? .plot
  }

  private func dimension(_ value: String) -> DramaticStateDimension {
    DramaticStateDimension.allCases.first {
      value.contains($0.rawValue) || $0.rawValue.contains(value)
    } ?? .world
  }

  private static let compilerInstructions = """
  你是 StoryMentor 的专业剧本编译器。作者可能不懂编剧术语，但他在 Final Draft 元素工作区写下的每一个具体句子都有作者权重。

  你的职责不是另写一个更像 AI 的故事，而是把作者当前场已经创造的材料整理成严格、完整、可拍摄的单场 Fountain 正文，并从正文中填充后台结构、场景和情境更新义务。

  硬规则：
  1. 一次只能处理当前这一场，不得生成后续场景、完整大纲或全本剧本。
  2. 优先保留作者原句、动作、对白、物件、生活细节和叙述节奏；只有不可拍摄的心理解释才转译为行动、潜台词或声音。
  3. 不得新增会改变全片方向的人物、秘密、世界规则或反转。
  4. 必须严格执行锁定结构阶段的功能，但结构术语不得写进正文。
  5. Fountain 场景标题使用“内. 地点 - 日/夜”“外. 地点 - 日/夜”；人物提示使用“@人物名”；动作使用现在时。
  6. 场景必须具备即时目标、直接阻力、策略变化、转折和离场后的新局面。
  7. 情境更新必须具有 before → after 差异，并区分世界事实、人物认知与观众认知。
  8. 创作回声不是评价文笔。每项必须逐字引用作者本轮原文，并说明这句话已经创造出了什么。
  9. 专业知识库和经典案例只能改善执行，不能覆盖作者的事实与选择。
  10. 返回 Foundation Models 强类型结果。
  """
}

enum GuidedFinalDraftCompilerError: LocalizedError {
  case requiresProfessionalElementsOrAI
  case invalidProfessionalScene
  case missingDramaticUpdates

  var errorDescription: String? {
    switch self {
    case .requiresProfessionalElementsOrAI:
      "当前文字尚未形成完整的标准场景。请配置 AI 编译器，或继续使用场景标题、动作、人物和对白元素完成本场。"
    case .invalidProfessionalScene:
      "AI 没有返回一个完整、合法的单场 Fountain 正文。作者原文未被覆盖，请重试本轮编译。"
    case .missingDramaticUpdates:
      "当前场景没有形成可验证的情境变化。请继续写到人物行动遭遇反作用并改变局面。"
    }
  }
}
