import Foundation
import FoundationModels

nonisolated struct GuidedFlowCoachReview: Hashable, Sendable {
  var isReady: Bool
  var feedback: String
  var singleNudge: String
  var acceptedSummary: String
}

@Generable
nonisolated private struct GuidedFlowCoachReviewDraft {
  @Guide(description: "只判断作者当前这一个最小回答是否满足本题成功契约")
  var isReady: Bool

  @Guide(description: "面向新手的一句描述性反馈；最多指出一个最重要问题；不提供完整答案")
  var feedback: String

  @Guide(description: "如果尚未成立，只给一个下一步提示；若已成立则留空；不得续写后续剧情")
  var singleNudge: String

  @Guide(description: "若已成立，用一句话忠实概括作者已经决定的内容；不得增加新事实")
  var acceptedSummary: String
}

@Generable
nonisolated private struct GuidedFlowMinimalAssistDraft {
  @Guide(description: "只补当前最小步骤的一个短小可编辑建议；绝不生成后续步骤、完整场景、大纲或完整剧本")
  var suggestion: String
}

@Generable
nonisolated private struct GuidedFlowContributionDiscoveryDraft {
  @Guide(description: "只能是：活起来的人物、已经发生的情节、关系里的压力、可以拍到的画面、作者声音、世界与生活细节、价值与主题")
  var kind: String

  @Guide(description: "说明作者原文已经为剧本提供了什么具体材料；不评价文笔，不增加原文没有的事实")
  var finding: String

  @Guide(description: "从作者原文逐字复制三到三十个字作为证据；不得改写或伪造")
  var sourceExcerpt: String
}

@Generable
nonisolated private struct GuidedFlowContributionEchoDraft {
  @Guide(description: "这篇命题写作是否已经包含足够材料，可以提炼出当前小挑战所需的决定")
  var isReady: Bool

  @Guide(description: "一句非评判性反馈；若不足，只说明一个最重要缺口")
  var feedback: String

  @Guide(description: "若不足，只给一个继续写下去的具体切口；若成立则留空")
  var singleNudge: String

  @Guide(description: "一句让作者感到自己的文字已经让人物或故事开始发生的标题；不得夸大")
  var headline: String

  @Guide(description: "说明这篇文字已经怎样进入人物、情节、关系或画面；强调原文会保留，不以AI改写替代")
  var impactSummary: String

  @Guide(description: "只提炼当前命题需要的一个可继续使用的决定；忠实于作者原文，不增加新人物、新事实或后续剧情")
  var canonicalDecision: String

  @Guide(description: "二到八项由作者原文直接支持的故事发现；每项必须带逐字原文证据")
  var discoveries: [GuidedFlowContributionDiscoveryDraft]

  @Guide(description: "零到三句值得原样保留的作者原句；必须逐字来自输入")
  var preservedLines: [String]

  @Guide(description: "只写一个从作者原文自然生长出来的下一步问题，不回答它")
  var nextQuestion: String
}

@MainActor
enum GuidedFlowCoachEngine {
  static func review(
    answer: String,
    challenge: GuidedFlowChallenge,
    project: StoryProject,
    configuration: AIConfiguration
  ) async throws -> GuidedFlowCoachReview {
    let session = StoryLanguageRuntime.session(
      configuration: configuration.withThinkingEnabled(false),
      instructions: reviewInstructions
    )
    let response = try await session.respond(
      to: """
        【当前项目，不得改写】
        项目：\(project.title)
        一句话故事：\(project.logline)
        当前故事状态：\(project.projectSummary)
        作者近期命题写作与创意：
        \(recentAuthorWritingContext(project))

        【当前唯一小挑战】
        阶段：\(challenge.phase.rawValue)
        标题：\(challenge.title)
        问题：\(challenge.question)
        为什么现在解决它：\(challenge.whyItMatters)
        已确认的局部上下文：\(challenge.referenceText)
        成功契约：\(challenge.successContract.joined(separator: "；"))
        最大允许长度：\(challenge.maximumCharacters) 字

        【作者当前回答】
        \(answer)

        只检查这一项回答。不得提出第二个问题，不得续写剧情，不得给出完整替代答案。
        """,
      generating: GuidedFlowCoachReviewDraft.self,
      options: GenerationOptions(
        temperature: 0.12,
        maximumResponseTokens: 420
      )
    )
    let draft = response.content
    return GuidedFlowCoachReview(
      isReady: draft.isReady,
      feedback: oneLine(draft.feedback, limit: 100),
      singleNudge: draft.isReady ? "" : oneLine(draft.singleNudge, limit: 100),
      acceptedSummary: draft.isReady
        ? oneLine(draft.acceptedSummary, limit: 140)
        : ""
    )
  }

  static func reflectOnPromptedWriting(
    answer: String,
    challenge: GuidedFlowChallenge,
    project: StoryProject,
    configuration: AIConfiguration
  ) async throws -> GuidedFlowPromptedWritingReview {
    let local = GuidedFlowContributionAnalyzer.localReview(
      answer: answer,
      challenge: challenge
    )
    guard local.isReady else { return local }

    let session = StoryLanguageRuntime.session(
      configuration: configuration.withThinkingEnabled(false),
      instructions: contributionInstructions
    )
    let response = try await session.respond(
      to: """
        【作者已经确认的项目背景，不得推翻】
        项目：\(project.title)
        一句话故事：\(project.logline)
        当前故事状态：\(project.projectSummary)
        当前局部上下文：\(challenge.referenceText)
        作者近期命题写作与创意：
        \(recentAuthorWritingContext(project))

        【本次命题】
        \(challenge.promptedWritingPrompt)
        当前小挑战成功契约：\(challenge.successContract.joined(separator: "；"))

        【作者命题写作原文】
        \(String(answer.prefix(challenge.maximumCharacters(for: .promptedWriting))))

        这不是作文评分。请证明作者的文字已经为剧本提供了什么，并让每项发现都附带一段逐字原文。
        只提炼当前命题需要的一个决定；不得替作者续写后续剧情或把全文改写成AI版本。
        """,
      generating: GuidedFlowContributionEchoDraft.self,
      options: GenerationOptions(
        temperature: 0.18,
        maximumResponseTokens: 1_600
      )
    )
    let draft = response.content
    guard draft.isReady else {
      return GuidedFlowPromptedWritingReview(
        isReady: false,
        feedback: oneLine(draft.feedback, limit: 130),
        singleNudge: oneLine(draft.singleNudge, limit: 140),
        echo: nil
      )
    }

    let fallback = local.echo
    var discoveries: [GuidedFlowDiscovery] = []
    for item in draft.discoveries.prefix(8) {
      let finding = oneLine(item.finding, limit: 160)
      guard !finding.isEmpty else { continue }
      let fallbackExcerpt =
        fallback?.discoveries.first(where: {
          $0.kind == GuidedFlowContributionAnalyzer.discoveryKind(from: item.kind)
        })?.sourceExcerpt ?? ""
      let excerpt = GuidedFlowContributionAnalyzer.validatedExcerpt(
        item.sourceExcerpt,
        in: answer,
        fallback: fallbackExcerpt
      )
      discoveries.append(
        GuidedFlowDiscovery(
          kind: GuidedFlowContributionAnalyzer.discoveryKind(from: item.kind),
          finding: finding,
          sourceExcerpt: excerpt
        )
      )
    }
    if discoveries.isEmpty {
      discoveries = fallback?.discoveries ?? []
    }

    var preservedLines: [String] = []
    for line in draft.preservedLines.prefix(3) {
      let validated = GuidedFlowContributionAnalyzer.validatedExcerpt(
        line,
        in: answer
      )
      if !validated.isEmpty, !preservedLines.contains(validated) {
        preservedLines.append(validated)
      }
    }
    if preservedLines.isEmpty {
      preservedLines = fallback?.preservedLines ?? []
    }

    let fallbackCanonical =
      fallback?.canonicalDecision
      ?? GuidedFlowContributionAnalyzer.canonicalDecision(
        from: answer,
        challenge: challenge
      )
    let canonicalLimit = min(600, max(challenge.maximumCharacters, 180))
    let canonical = oneLine(
      draft.canonicalDecision.guidedTrimmed.isEmpty
        ? fallbackCanonical
        : draft.canonicalDecision,
      limit: canonicalLimit
    )
    let echo = GuidedFlowContributionEcho(
      headline: oneLine(
        draft.headline.guidedTrimmed.isEmpty
          ? (fallback?.headline ?? "你的文字已经让故事开始发生")
          : draft.headline,
        limit: 90
      ),
      impactSummary: oneLine(
        draft.impactSummary.guidedTrimmed.isEmpty
          ? (fallback?.impactSummary ?? "全文会原样保存，并继续影响后续创作。")
          : draft.impactSummary,
        limit: 220
      ),
      canonicalDecision: canonical,
      discoveries: discoveries,
      preservedLines: preservedLines,
      nextQuestion: oneLine(
        draft.nextQuestion.guidedTrimmed.isEmpty
          ? (fallback?.nextQuestion ?? "接下来，这个决定会迫使谁采取行动？")
          : draft.nextQuestion,
        limit: 150
      )
    )
    return GuidedFlowPromptedWritingReview(
      isReady: true,
      feedback: oneLine(
        draft.feedback.guidedTrimmed.isEmpty
          ? "这篇文字已经成为项目里的正式创作材料。"
          : draft.feedback,
        limit: 130
      ),
      singleNudge: "",
      echo: echo
    )
  }

  static func minimalAssist(
    challenge: GuidedFlowChallenge,
    currentDraft: String,
    project: StoryProject,
    configuration: AIConfiguration,
    responseMode: GuidedFlowResponseMode = .focused
  ) async throws -> String {
    let session = StoryLanguageRuntime.session(
      configuration: configuration.withThinkingEnabled(false),
      instructions: minimalAssistInstructions
    )
    let response = try await session.respond(
      to: """
        【当前项目，不得扩写】
        项目：\(project.title)
        一句话故事：\(project.logline)

        【当前唯一小挑战】
        \(challenge.title)
        \(challenge.question)
        当前回答方式：\(responseMode.rawValue)
        命题写作提示：\(responseMode == .promptedWriting ? challenge.promptedWritingPrompt : "不适用")
        局部上下文：\(challenge.referenceText)
        本级支架要求：\(challenge.minimalAssistInstruction)
        成功契约：\(challenge.successContract.joined(separator: "；"))
        当前作者草稿：\(currentDraft.isEmpty ? "作者尚未输入" : currentDraft)

        若是命题写作，只给一个开头、场面切口或继续写下去的问题；不能代写整篇。
        若是聚焦回答，只给当前这一步的一个短小建议。不能补下一步，不能写完整场景、大纲、结局或整本剧本。
        """,
      generating: GuidedFlowMinimalAssistDraft.self,
      options: GenerationOptions(
        temperature: 0.28,
        maximumResponseTokens: 300
      )
    )
    let raw = response.content.suggestion
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let limit: Int
    if responseMode == .promptedWriting {
      limit = 220
    } else if challenge.phase == .beat && challenge.id.hasSuffix(".text") {
      limit = min(challenge.maximumCharacters, 260)
    } else {
      limit = min(challenge.maximumCharacters, 140)
    }
    return String(raw.prefix(max(limit, 1)))
  }

  private static let reviewInstructions = """
    你是剧本创作心流教练，不是代笔者。作者可能完全不懂编剧术语。
    每次只处理界面给出的一个最小挑战。你的工作是判断作者回答是否足以成为
    下一步可复用的故事决定，并给出即时、具体、非评判性的反馈。

    硬性规则：
    1. 不生成完整人物设定、完整结构、大纲、完整场景、整集或完整剧本。
    2. 不替作者同时解决两个问题。
    3. 不把个人审美伪装成客观分数。
    4. 尚未成立时最多指出一个首要缺口，并给一个提示，不给成品答案。
    5. 已成立时只概括作者已经决定的内容，不能增加新人物、新事实、新反转或后续。
    6. 所有面向作者的内容使用简洁、现代的简体中文。
    """

  private static let contributionInstructions = """
    你是作者文字的“创作回声”，不是作文老师，也不是改写者。作者可能不会剧本格式，
    但会写命题作文、小说式片段或长段叙述。你的任务是让作者立即看见：自己写下的
    具体文字已经怎样创造出人物、行动、关系、画面、生活细节和后续因果。

    硬性规则：
    1. 不打分，不用“文笔好坏”“高级低级”评价作者。
    2. 每项发现必须由作者原文中的逐字短句支持；不得伪造引文。
    3. 原文始终是正式创作材料；不能用你的摘要替换原文。
    4. canonicalDecision 只提炼当前命题需要的一个决定，不增加作者没有写出的事实。
    5. 不续写完整人物小传、结构链、后续场景、整集或整本剧本。
    6. 反馈要具体说明“这句话让谁活了”“哪个动作形成情节”“哪个细节可以拍到”。
    7. 只提出一个下一步问题，不回答它。
    """

  private static let minimalAssistInstructions = """
    你是最后一级微型支架。作者已经逐级请求帮助，所以可以补一个最小局部答案或写作切口，
    但作者仍必须继续作决定。严格服从当前挑战的范围和长度。

    禁止：完整人物小传、完整结构节点链、多个后续节拍、完整场景、整集、完整剧本、
    解释性长文、四个以上候选。命题写作模式下也只能给一个开头或切口，不能代写整篇。
    """

  private static func recentAuthorWritingContext(_ project: StoryProject) -> String {
    let lines = project.activeCreativeIdeas
      .prefix(8)
      .map(\.promptLine)
      .joined(separator: "\n\n")
      .guidedTrimmed
    return lines.isEmpty ? "尚无" : String(lines.prefix(6_000))
  }

  private static func oneLine(_ text: String, limit: Int) -> String {
    let clean =
      text
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    return String(clean.prefix(limit))
  }
}
