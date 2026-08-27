import Foundation

/// Network-free fallback and validation for prompted writing. It never grades
/// prose quality; it only identifies concrete material that the author has
/// already placed on the page.
nonisolated enum GuidedFlowContributionAnalyzer {
  static func localReview(
    answer: String,
    challenge: GuidedFlowChallenge
  ) -> GuidedFlowPromptedWritingReview {
    let clean = answer.guidedTrimmed
    let minimum = challenge.minimumCharacters(for: .promptedWriting)
    guard clean.count >= minimum else {
      return GuidedFlowPromptedWritingReview(
        isReady: false,
        feedback: "这篇文字还没有展开到足以看见人物或事件。",
        singleNudge: "再写一个具体时刻：人物正在做什么，谁在场，哪一个细节让局面开始不一样？",
        echo: nil
      )
    }

    let sentences = meaningfulSentences(in: clean)
    let canonical = canonicalDecision(
      from: sentences,
      fallback: clean,
      challenge: challenge
    )
    let preserved = preservedLines(from: sentences, source: clean)
    let discoveries = discoveries(
      from: sentences,
      preservedLines: preserved,
      challenge: challenge
    )
    let echo = GuidedFlowContributionEcho(
      headline: headline(for: challenge.skill),
      impactSummary:
        "你写下的 \(clean.count) 个字已经留下 \(discoveries.count) 个可以继续使用的故事抓手。全文会原样保存；系统只把当前命题提炼成一个下一步可用的决定。",
      canonicalDecision: canonical,
      discoveries: discoveries,
      preservedLines: preserved,
      nextQuestion: nextQuestion(for: challenge)
    )
    return GuidedFlowPromptedWritingReview(
      isReady: true,
      feedback: "这篇文字已经成为项目里的正式创作材料。",
      singleNudge: "",
      echo: echo
    )
  }

  static func canonicalDecision(
    from text: String,
    challenge: GuidedFlowChallenge
  ) -> String {
    canonicalDecision(
      from: meaningfulSentences(in: text),
      fallback: text,
      challenge: challenge
    )
  }

  static func validatedExcerpt(
    _ candidate: String,
    in source: String,
    fallback: String = ""
  ) -> String {
    let clean = candidate.guidedTrimmed
    if !clean.isEmpty, source.contains(clean) {
      return String(clean.prefix(90))
    }
    let fallbackClean = fallback.guidedTrimmed
    if !fallbackClean.isEmpty, source.contains(fallbackClean) {
      return String(fallbackClean.prefix(90))
    }
    return String(meaningfulSentences(in: source).first?.prefix(90) ?? source.prefix(90))
  }

  static func discoveryKind(from rawValue: String) -> GuidedFlowDiscoveryKind {
    let clean = rawValue.guidedTrimmed
    return GuidedFlowDiscoveryKind.allCases.first {
      clean.contains($0.rawValue) || $0.rawValue.contains(clean)
    }
      ?? {
        if clean.contains("人物") { return .character }
        if clean.contains("关系") { return .relationship }
        if clean.contains("画面") || clean.contains("视觉") { return .image }
        if clean.contains("声音") || clean.contains("语言") || clean.contains("对白") {
          return .voice
        }
        if clean.contains("世界") || clean.contains("生活") || clean.contains("环境") {
          return .world
        }
        if clean.contains("主题") || clean.contains("价值") { return .theme }
        return .plot
      }()
  }

  private static func canonicalDecision(
    from sentences: [String],
    fallback: String,
    challenge: GuidedFlowChallenge
  ) -> String {
    let ranked = sentences.enumerated().sorted { lhs, rhs in
      sentenceScore(lhs.element, challenge: challenge, order: lhs.offset)
        > sentenceScore(rhs.element, challenge: challenge, order: rhs.offset)
    }
    let selected =
      ranked.first?.element.guidedTrimmed
      ?? fallback.guidedTrimmed
    return String(selected.prefix(max(challenge.maximumCharacters, 120)))
  }

  private static func meaningfulSentences(in text: String) -> [String] {
    let characters = Array(text)
    let terminals: Set<Character> = ["。", "！", "？", "!", "?", "\n"]
    let closingQuotes: Set<Character> = ["”", "’", "」", "』"]
    var result: [String] = []
    var current = ""
    var index = 0

    while index < characters.count {
      let character = characters[index]
      current.append(character)
      if terminals.contains(character) {
        if character != "\n",
          index + 1 < characters.count,
          closingQuotes.contains(characters[index + 1])
        {
          index += 1
          current.append(characters[index])
        }
        let clean = current.guidedTrimmed
        if clean.count >= 6 { result.append(clean) }
        current = ""
      }
      index += 1
    }
    let remainder = current.guidedTrimmed
    if remainder.count >= 6 { result.append(remainder) }
    return result
  }

  private static func sentenceScore(
    _ sentence: String,
    challenge: GuidedFlowChallenge,
    order: Int
  ) -> Int {
    var score = max(0, 10 - order)
    let causalMarkers = ["决定", "发现", "却", "但是", "因为", "所以", "失去", "得到", "不再", "开始", "只好", "必须"]
    score += causalMarkers.filter(sentence.contains).count * 5
    let actionMarkers = ["走", "拿", "放", "关", "推", "看", "说", "问", "递", "删", "躲", "站", "坐", "回头"]
    score += actionMarkers.filter(sentence.contains).count * 2
    if sentence.contains("他") || sentence.contains("她") || sentence.contains("我") {
      score += 3
    }
    if challenge.skill == .characterCausality,
      sentence.contains("怕") || sentence.contains("想") || sentence.contains("装")
    {
      score += 5
    }
    if sentence.count >= 12 && sentence.count <= 180 { score += 4 }
    return score
  }

  private static func preservedLines(
    from sentences: [String],
    source: String
  ) -> [String] {
    var candidates =
      sentences
      .filter { (12...120).contains($0.count) }
      .sorted {
        vividnessScore($0) == vividnessScore($1)
          ? $0.count > $1.count
          : vividnessScore($0) > vividnessScore($1)
      }
    if candidates.isEmpty {
      candidates = [String(source.prefix(90))]
    }
    var result: [String] = []
    for item in candidates where !result.contains(item) {
      result.append(item)
      if result.count == 3 { break }
    }
    return result
  }

  private static func vividnessScore(_ sentence: String) -> Int {
    let markers = [
      "“", "”", "门", "窗", "灯", "手", "眼", "衣", "杯", "钥匙", "手机", "雨", "夜", "血", "笑", "沉默", "回头", "声音",
    ]
    return markers.filter(sentence.contains).count * 3
      + min(sentence.count / 20, 4)
  }

  private static func discoveries(
    from sentences: [String],
    preservedLines: [String],
    challenge: GuidedFlowChallenge
  ) -> [GuidedFlowDiscovery] {
    let source = preservedLines.first ?? sentences.first ?? ""
    var values: [GuidedFlowDiscovery] = [
      GuidedFlowDiscovery(
        kind: primaryKind(for: challenge.skill),
        finding: primaryFinding(for: challenge.skill),
        sourceExcerpt: String(source.prefix(90))
      )
    ]

    if let causal = sentences.first(where: containsCausalMarker) {
      values.append(
        GuidedFlowDiscovery(
          kind: .plot,
          finding: "这里已经出现了行动、反作用或决定，后续情节可以从这个因果节点继续。",
          sourceExcerpt: String(causal.prefix(90))
        )
      )
    }
    if let relationship = sentences.first(where: containsRelationshipMarker) {
      values.append(
        GuidedFlowDiscovery(
          kind: .relationship,
          finding: "人物不是独自存在；这段文字已经让一段关系开始施加压力。",
          sourceExcerpt: String(relationship.prefix(90))
        )
      )
    }
    if let visual = preservedLines.first {
      values.append(
        GuidedFlowDiscovery(
          kind: .image,
          finding: "这句包含可以被看见、听见或表演出来的具体材料。",
          sourceExcerpt: String(visual.prefix(90))
        )
      )
    }
    if let dialogue = sentences.first(where: containsDialogueMarker) {
      values.append(
        GuidedFlowDiscovery(
          kind: .voice,
          finding: "人物的说话方式或作者的叙述语气已经开始具有辨识度。",
          sourceExcerpt: String(dialogue.prefix(90))
        )
      )
    }
    if let world = sentences.first(where: containsWorldMarker) {
      values.append(
        GuidedFlowDiscovery(
          kind: .world,
          finding: "具体地点、职业或生活物件让故事开始拥有自己的现实质感。",
          sourceExcerpt: String(world.prefix(90))
        )
      )
    }

    var unique: [GuidedFlowDiscovery] = []
    for discovery in values where !unique.contains(where: { $0.kind == discovery.kind }) {
      unique.append(discovery)
      if unique.count == 6 { break }
    }
    return unique
  }

  private static func primaryKind(
    for skill: GuidedFlowSkill
  ) -> GuidedFlowDiscoveryKind {
    switch skill {
    case .ideaDiscovery: .plot
    case .characterCausality: .character
    case .oppositionAndStakes: .plot
    case .structuralReasoning: .plot
    case .sceneConstruction: .image
    case .dramaticStateControl: .plot
    case .dialogueAndAction: .voice
    case .revisionAndContinuity: .theme
    }
  }

  private static func primaryFinding(for skill: GuidedFlowSkill) -> String {
    switch skill {
    case .ideaDiscovery:
      "你没有只给出概念，而是留下了一个值得继续追问的故事吸引点。"
    case .characterCausality:
      "人物已经通过具体处境、欲望或防御动作显露出来，而不再只是资料卡。"
    case .oppositionAndStakes:
      "这段文字已经把人物的行动与可能失去的东西连接起来。"
    case .structuralReasoning:
      "这里已经出现一个会改变后续方向的决定、揭示或代价。"
    case .sceneConstruction:
      "这段文字提供了人物可以实际行动的地点、目标或场面条件。"
    case .dramaticStateControl:
      "局面已经出现从原状态到新状态的变化线索。"
    case .dialogueAndAction:
      "动作、对白或停顿已经可以继续转化为剧本文字。"
    case .revisionAndContinuity:
      "你已经在判断什么必须保留、什么需要改变，这会形成真正的修订方向。"
    }
  }

  private static func headline(for skill: GuidedFlowSkill) -> String {
    switch skill {
    case .characterCausality:
      "你写的不只是设定，一个会行动的人已经开始出现"
    case .sceneConstruction, .dramaticStateControl, .dialogueAndAction:
      "你写的不只是解释，一个可以发生的场面已经开始出现"
    default:
      "你没有只回答问题，这段文字已经让故事向前移动"
    }
  }

  private static func nextQuestion(for challenge: GuidedFlowChallenge) -> String {
    switch challenge.phase {
    case .foundation:
      "接下来会继续追问：这个人现在最想得到什么，又为什么不能轻易得到？"
    case .structure:
      "接下来会继续追问：这个决定直接让人物失去什么，并迫使什么后果发生？"
    case .scene:
      "接下来会继续追问：这场戏结束时，人物具体得到、失去、知道或决定了什么？"
    case .beat:
      "接下来会继续追问：人物的行动遭遇怎样的反作用，局面因此变成什么？"
    case .screenplay, .completed:
      "接下来会带着这篇文字进入局部修订，而不是重新生成整块答案。"
    }
  }

  private static func containsCausalMarker(_ text: String) -> Bool {
    ["却", "但是", "因此", "所以", "决定", "发现", "结果", "只好", "不得不"]
      .contains(where: text.contains)
  }

  private static func containsRelationshipMarker(_ text: String) -> Bool {
    ["母亲", "父亲", "女儿", "儿子", "妻子", "丈夫", "朋友", "同事", "老师", "学生", "姐姐", "哥哥", "弟弟", "妹妹", "恋人"]
      .contains(where: text.contains)
  }

  private static func containsDialogueMarker(_ text: String) -> Bool {
    text.contains("“") || text.contains("”") || text.contains("：")
  }

  private static func containsWorldMarker(_ text: String) -> Bool {
    ["医院", "学校", "公司", "工厂", "厨房", "卧室", "街", "车站", "夜", "清晨", "门", "窗", "手机", "钥匙", "杯子"]
      .contains(where: text.contains)
  }
}
