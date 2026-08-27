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

  static func minimalAssist(
    challenge: GuidedFlowChallenge,
    currentDraft: String,
    project: StoryProject,
    configuration: AIConfiguration
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
        局部上下文：\(challenge.referenceText)
        本级支架要求：\(challenge.minimalAssistInstruction)
        成功契约：\(challenge.successContract.joined(separator: "；"))
        当前作者草稿：\(currentDraft.isEmpty ? "作者尚未输入" : currentDraft)

        只给当前这一步的一个短小建议。不能补下一步，不能写完整场景、大纲、结局或整本剧本。
        """,
      generating: GuidedFlowMinimalAssistDraft.self,
      options: GenerationOptions(
        temperature: 0.28,
        maximumResponseTokens: 300
      )
    )
    let raw = response.content.suggestion
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let limit =
      challenge.phase == .beat && challenge.id.hasSuffix(".text")
      ? min(challenge.maximumCharacters, 260)
      : min(challenge.maximumCharacters, 140)
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

  private static let minimalAssistInstructions = """
    你是最后一级微型支架。作者已经逐级请求帮助，所以可以补一个最小局部答案，
    但作者仍必须继续作决定。严格服从当前挑战的范围和长度。

    禁止：完整人物小传、完整结构节点链、多个后续节拍、完整场景、整集、完整剧本、
    解释性长文、四个以上候选。只返回一个短小、可修改的当前步骤建议。
    """

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
