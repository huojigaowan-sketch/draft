import Foundation

@MainActor
extension GuidedFlowCoordinator {

  static func foundationChallenge(
    index: Int,
    stretch: Int
  ) -> GuidedFlowChallenge? {
    let commonDifficulty = GuidedFlowDifficultyProfile(
      openness: stretch == 0 ? 0 : 1,
      constraintLoad: 0,
      causalHorizon: index >= 3 ? 1 : 0,
      stateComplexity: index >= 4 ? 1 : 0,
      executionLoad: 0
    )
    switch index {
    case 0:
      return GuidedFlowChallenge(
        id: "foundation.spark",
        phase: .foundation,
        title: "先抓住真正吸引你的东西",
        question: "你脑中最先出现的是什么？只写一个：一个人、一段关系、一个画面、一件怪事，或一种说不清的感觉。",
        whyItMatters: "故事先从好奇心开始，不需要先懂结构。",
        placeholder: "例如：一个每天假装不认识女儿的母亲……",
        referenceText: "",
        skill: .ideaDiscovery,
        answerKind: .freeText,
        options: [
          "一个人：",
          "一段关系：",
          "一个画面：",
          "一件怪事：",
          "一种感觉：",
        ],
        minimumCharacters: 4,
        maximumCharacters: 120,
        reframe: "不要想完整故事。只写你愿意多看一分钟的东西。",
        ruleHint: "这一轮只保留一个吸引点，不解释背景。",
        mechanismHints: [
          "一个人正在隐藏某件事",
          "两个人彼此需要却不能信任",
          "一个日常画面里出现不对劲的细节",
        ],
        sentenceStarter: "我想看一个……",
        minimalAssistInstruction: "根据作者已经输入的几个词，只补成一个不超过 35 字的故事种子；不得增加人物关系、结局或完整情节。",
        successContract: ["只有一个核心吸引点", "不是完整大纲"],
        difficulty: commonDifficulty
      )
    case 1:
      return GuidedFlowChallenge(
        id: "foundation.protagonist",
        phase: .foundation,
        title: "找到我们主要跟随的人",
        question: "这个故事主要跟着谁？用“身份 + 当前处境”描述，不写完整小传。",
        whyItMatters: "观众需要通过一个具体的人进入故事。",
        placeholder: "例如：刚被调到急诊室、害怕犯错的年轻护士。",
        referenceText: "",
        skill: .characterCausality,
        answerKind: .freeText,
        options: [],
        minimumCharacters: 6,
        maximumCharacters: 120,
        reframe: "先回答：他现在是什么人，正处在什么麻烦里？",
        ruleHint: "不要罗列年龄、星座和爱好；处境必须能影响行动。",
        mechanismHints: [
          "一个被低估、急于证明自己的人",
          "一个正在失去控制、仍假装一切正常的人",
          "一个必须保护别人、却藏着秘密的人",
        ],
        sentenceStarter: "这是一个正在……的……",
        minimalAssistInstruction: "只把作者已有想法压成“身份 + 当前处境”的一句话，不添加目标、反派、结局。",
        successContract: ["能看见一个具体人物", "包含当前处境"],
        difficulty: commonDifficulty
      )
    case 2:
      return GuidedFlowChallenge(
        id: "foundation.desire",
        phase: .foundation,
        title: "让人物现在就想得到一件事",
        question: "他或她现在最想得到什么可以被看见、被判断成败的结果？",
        whyItMatters: "可见目标让人物开始行动，故事才会向前。",
        placeholder: "例如：在今晚十二点前拿回被弟弟卖掉的房契。",
        referenceText: "",
        skill: .characterCausality,
        answerKind: .freeText,
        options: [],
        minimumCharacters: 6,
        maximumCharacters: 120,
        reframe: "观众只看画面，怎样知道他成功还是失败？",
        ruleHint: "“想幸福”“想被爱”太抽象；先写一件可以完成或失败的事。",
        mechanismHints: [
          "拿到、找到或保住某样东西",
          "说服、阻止或救出某个人",
          "在期限前完成一次公开行动",
        ],
        sentenceStarter: "他必须在……之前……",
        minimalAssistInstruction: "只把作者输入改成一个可判断成败的外部目标，不添加阻碍和后续剧情。",
        successContract: ["结果可见", "可以判断成功或失败"],
        difficulty: commonDifficulty
      )
    case 3:
      return GuidedFlowChallenge(
        id: "foundation.stakes",
        phase: .foundation,
        title: "让拖延马上产生代价",
        question: "如果现在得不到这个结果，他会立刻失去什么具体东西、关系、身份或机会？",
        whyItMatters: "代价让故事必须发生在现在，而不是以后。",
        placeholder: "例如：唯一愿意替她作证的朋友会在天亮前离开。",
        referenceText: "",
        skill: .oppositionAndStakes,
        answerKind: .freeText,
        options: [],
        minimumCharacters: 6,
        maximumCharacters: 140,
        reframe: "先不想最惨的后果，只想今天不行动会损失什么。",
        ruleHint: "代价必须落到人物身上，不能只写“事情会更严重”。",
        mechanismHints: [
          "失去一个人最后的信任",
          "失去合法身份、工作或住所",
          "让一个秘密变成无法收回的公开事实",
        ],
        sentenceStarter: "如果他今天做不到，就会……",
        minimalAssistInstruction: "只根据当前目标补一个眼前代价，不添加新的支线、反派或结局。",
        successContract: ["代价具体", "为什么必须现在"],
        difficulty: commonDifficulty
      )
    case 4:
      return GuidedFlowChallenge(
        id: "foundation.contradiction",
        phase: .foundation,
        title: "找到会制造情节的错误办法",
        question: "这个人习惯用什么办法保护自己，而这个办法现在怎样伤害自己或别人？",
        whyItMatters: "人物不是因为资料完整而有戏，而是因为自己的办法不断制造后果。",
        placeholder: "例如：她凡事先撒谎来避免冲突，结果最亲近的人再也不信她。",
        referenceText: "",
        skill: .characterCausality,
        answerKind: .freeText,
        options: [],
        minimumCharacters: 10,
        maximumCharacters: 170,
        reframe: "先写“他总是会……”，再写“所以现在……”。",
        ruleHint: "不要只写“自卑、善良、冲动”等形容词，要写会反复发生的行为。",
        mechanismHints: [
          "用控制保护关系，结果把人推远",
          "用逃避避免失败，结果失去最后机会",
          "用取悦换取安全，结果无法说出真相",
        ],
        sentenceStarter: "他一直相信只有……才安全，所以总会……，结果……",
        minimalAssistInstruction: "把作者已有描述压成“保护方式 → 当前伤害”的因果句，不补完整人物弧。",
        successContract: ["包含可见行为", "行为会制造后果"],
        difficulty: commonDifficulty
      )
    case 5:
      return GuidedFlowChallenge(
        id: "foundation.logline",
        phase: .foundation,
        title: "把目前的决定压成一句故事",
        question: "用一句话写清：谁为了什么，必须面对什么，否则会失去什么？",
        whyItMatters: "这不是宣传文案，而是后续每个小挑战共同服从的方向。",
        placeholder: "例如：一名害怕冲突的护士必须在天亮前揭发导师伪造病历，否则唯一证人将被迫离院。",
        referenceText: "",
        skill: .structuralReasoning,
        answerKind: .freeText,
        options: [],
        minimumCharacters: 18,
        maximumCharacters: 180,
        reframe: "依次写：主人公、目标、主要阻力、失败代价。",
        ruleHint: "一句话只保留一条主线；暂时不要写中点、高潮和结局。",
        mechanismHints: [
          "谁 + 必须完成什么",
          "但什么力量持续阻止",
          "否则失去什么",
        ],
        sentenceStarter: "一个……的人必须……，但……，否则……",
        minimalAssistInstruction: "只把已经确认的主人公、目标和代价压成一句话，不新增反转、高潮或结局。",
        successContract: ["主人公明确", "目标明确", "阻力或代价明确"],
        difficulty: commonDifficulty
      )
    default:
      return nil
    }
  }

  static func structureChallenge(
    session: GuidedFlowSession,
    project: StoryProject
  ) -> GuidedFlowChallenge? {
    let template = project.structureTemplate
    guard template.stages.indices.contains(session.itemIndex) else { return nil }
    let stage = template.stages[session.itemIndex]
    let prefix = "structure.\(stage.id)"
    let prior =
      project.decisions
      .filter { $0.selectedOptionID != nil && $0.stageIndex < session.itemIndex }
      .sorted { $0.stageIndex < $1.stageIndex }
      .last?.selectedAnswerText ?? project.logline
    let reference = """
      当前框架：\(template.name)
      这一阶段的功能：\(stage.purpose)
      上一步已经确认：\(prior.guidedTrimmed.isEmpty ? "故事核心已经建立" : prior)
      """
    let difficulty = GuidedFlowDifficultyProfile(
      openness: min(3, 1 + session.targetStretch),
      constraintLoad: min(3, session.itemIndex / 3 + session.targetStretch / 2),
      causalHorizon: min(4, 1 + session.itemIndex / 3),
      stateComplexity: min(3, 1 + session.targetStretch / 2),
      executionLoad: 1
    )

    switch session.stepIndex {
    case 0:
      return GuidedFlowChallenge(
        id: "\(prefix).decision",
        phase: .structure,
        title: "第 \(session.itemIndex + 1) 步 · \(stage.name)",
        question: stage.choiceFocus,
        whyItMatters: stage.purpose,
        placeholder: "只写这一次决定，不写后续所有剧情。",
        referenceText: reference,
        skill: .structuralReasoning,
        answerKind: .freeText,
        options: [],
        minimumCharacters: 10,
        maximumCharacters: 220,
        reframe: "这一阶段结束时，主人公做了什么决定，或知道了什么，从而不能继续原来的状态？",
        ruleHint: "一个结构节点必须改变行动方向、关系、认知或承诺，不能只是发生热闹事件。",
        mechanismHints: mechanismHints(for: stage),
        sentenceStarter: "这一步，主人公因为……，决定……",
        minimalAssistInstruction: "只根据当前框架阶段和已确认故事，补一个不超过 60 字的阶段决定；不得生成下一阶段、完整大纲或结局。",
        successContract: ["只解决当前阶段", "包含一个不可忽略的决定或变化"],
        difficulty: difficulty
      )
    case 1:
      return GuidedFlowChallenge(
        id: "\(prefix).cost",
        phase: .structure,
        title: "让这一步付出代价",
        question: "刚才的决定必须让主人公具体付出什么，并给后面制造什么压力？",
        whyItMatters: "没有代价的决定不会形成持续因果。",
        placeholder: "例如：她拿到证据，却让唯一盟友误以为自己被利用。",
        referenceText: reference + "\n当前决定：\(session.answer(for: "\(prefix).decision"))",
        skill: .oppositionAndStakes,
        answerKind: .freeText,
        options: [],
        minimumCharacters: 10,
        maximumCharacters: 180,
        reframe: "先写“得到什么”，再写“因此失去什么”。",
        ruleHint: "代价应直接来自刚才的行动，而不是突然出现的无关灾难。",
        mechanismHints: [
          "成功暴露了自己",
          "保护了秘密却伤害了关系",
          "解决眼前问题却让对手学会反击",
        ],
        sentenceStarter: "他虽然……，却因此……，接下来不得不……",
        minimalAssistInstruction: "只为当前决定补一个直接代价和下一步压力，不新增支线或后续完整情节。",
        successContract: ["代价来自当前决定", "产生下一步压力"],
        difficulty: difficulty
      )
    case 2:
      return GuidedFlowChallenge(
        id: "\(prefix).evidence",
        phase: .structure,
        title: "让观众看见变化已经发生",
        question: "写一个可以被看见或听见的瞬间，证明这一步已经改变了局面。",
        whyItMatters: "结构不是标签，必须最终落到可拍摄的证据。",
        placeholder: "例如：她把备用钥匙交给对手，却在对方转身后删除了唯一副本。",
        referenceText: reference
          + "\n当前决定：\(session.answer(for: "\(prefix).decision"))"
          + "\n当前代价：\(session.answer(for: "\(prefix).cost"))",
        skill: .dramaticStateControl,
        answerKind: .freeText,
        options: [],
        minimumCharacters: 10,
        maximumCharacters: 220,
        reframe: "摄像机能拍到什么动作、物件、沉默或一句话？",
        ruleHint: "不要写“她意识到”“关系恶化”；写出让观众得出这个结论的证据。",
        mechanismHints: [
          "一个不可收回的动作",
          "一个只有观众注意到的细节",
          "一句改变承诺或权力关系的话",
        ],
        sentenceStarter: "观众看到……，从这一刻起……",
        minimalAssistInstruction: "只把当前决定转成一个可拍摄瞬间，不生成完整场景、对白段落或后续节拍。",
        successContract: ["可见或可听", "证明 before → after 已发生"],
        difficulty: difficulty
      )
    default:
      return nil
    }
  }

  static func sceneChallenge(
    session: GuidedFlowSession,
    project: StoryProject
  ) -> GuidedFlowChallenge? {
    let scenes = orderedScenes(in: project)
    guard scenes.indices.contains(session.itemIndex) else { return nil }
    let contract = scenes[session.itemIndex]
    let prefix = "scene.\(contract.id.uuidString)"
    let reference = """
      场景范围：\(contract.scopeTitle)
      这场必须完成：\(contract.scopePurpose)
      进入状态：\(contract.scopeEntryState)
      离开状态：\(contract.scopeExitState)
      """
    let difficulty = GuidedFlowDifficultyProfile(
      openness: min(3, 1 + session.targetStretch),
      constraintLoad: 2,
      causalHorizon: 2,
      stateComplexity: min(3, 1 + session.targetStretch / 2),
      executionLoad: 2
    )

    let definitions:
      [(String, String, String, String, GuidedFlowSkill, String, String, [String], String)] = [
        (
          "heading",
          "先给这场一个可拍摄地点",
          "这场发生在什么具体地点、什么时间？",
          "地点会决定人物能做什么、不能做什么。",
          .sceneConstruction,
          "例如：内. 夜班药房 - 凌晨",
          "只写一个地点和时间，不描述整场。",
          ["公开场所迫使人物克制", "封闭空间让退路消失", "工作场所带来制度限制"],
          "内/外. 具体地点 - 时间"
        ),
        (
          "pov",
          "确定观众跟着谁经历",
          "观众主要通过谁经历这一场？只写一个人物。",
          "单一视点让信息和情绪更清楚。",
          .sceneConstruction,
          "例如：女主",
          "谁在这场里承受最重要的变化？",
          ["最想得到结果的人", "最晚知道真相的人", "必须做决定的人"],
          "观众跟着……"
        ),
        (
          "goal",
          "给人物一个眼前目标",
          "这个人物在本场结束前，立刻想取得什么具体结果？",
          "场景目标让动作和对白具有方向。",
          .sceneConstruction,
          "例如：在经理回来前拿到药柜钥匙。",
          "只写本场能完成或失败的结果。",
          ["拿到信息或物件", "让对方答应一件事", "阻止某件事发生"],
          "他想在本场结束前……"
        ),
        (
          "obstacle",
          "让目标遭遇具体阻力",
          "谁、什么规则、信息差或物理条件正在阻止这个目标？",
          "阻力迫使人物改变策略，而不是简单等待。",
          .oppositionAndStakes,
          "例如：值班主管必须亲自核对身份，而女主正在冒用同事工牌。",
          "阻力必须能主动产生反作用。",
          ["另一个人有相反目标", "制度要求暴露身份", "人物掌握的信息不对称"],
          "他本想……，但……"
        ),
        (
          "turn",
          "确定场景转折",
          "发生什么可见事件，使人物原来的策略失效或必须改变？",
          "转折让场景从一种局面进入另一种局面。",
          .dramaticStateControl,
          "例如：主管主动把钥匙递给她，却叫出了她同事的真名。",
          "转折必须改变策略、认知、关系或承诺。",
          ["对方知道得比预想更多", "人物得到目标却暴露自己", "一个承诺突然改变权力"],
          "就在他以为……时，……"
        ),
        (
          "outcome",
          "锁定离场结果",
          "这场结束时，人物具体得到、失去、决定或知道了什么？",
          "离场状态必须与入场状态不同。",
          .dramaticStateControl,
          "例如：女主拿到钥匙，但确认主管已经识破她。",
          "结果不是情绪形容词，而是新成立的事实。",
          ["得到目标并付出代价", "失去退路并作出决定", "知道真相却不能公开"],
          "这场结束时……"
        ),
        (
          "pressure",
          "让下一场被迫发生",
          "这个结果接下来立刻逼谁做什么？",
          "下一场压力把场景连接成因果链。",
          .structuralReasoning,
          "例如：主管必须在交班前检查监控，女主只剩十分钟处理录音。",
          "只写最直接的下一步，不展开完整后续。",
          ["对手开始检查", "盟友要求解释", "期限突然缩短"],
          "因此，接下来……"
        ),
      ]
    guard definitions.indices.contains(session.stepIndex) else { return nil }
    let item = definitions[session.stepIndex]
    return GuidedFlowChallenge(
      id: "\(prefix).\(item.0)",
      phase: .scene,
      title: "场 \(contract.sceneIndex) · \(item.1)",
      question: item.2,
      whyItMatters: item.3,
      placeholder: item.5,
      referenceText: reference,
      skill: item.4,
      answerKind: .freeText,
      options: [],
      minimumCharacters: item.0 == "pov" ? 1 : 4,
      maximumCharacters: item.0 == "pov" ? 40 : 180,
      reframe: item.6,
      ruleHint: item.6,
      mechanismHints: item.7,
      sentenceStarter: item.8,
      minimalAssistInstruction: "只补当前场景字段“\(item.1)”，不得生成完整场景、对白、后续场景或整块答案。",
      successContract: ["只完成当前场景字段", "不提前解决后续步骤"],
      difficulty: difficulty
    )
  }

  static func beatChallenge(
    session: GuidedFlowSession,
    project: StoryProject
  ) -> GuidedFlowChallenge? {
    let scenes = orderedScenes(in: project)
    guard scenes.indices.contains(session.itemIndex) else { return nil }
    let contract = scenes[session.itemIndex]
    let ordinal = contract.microBeats.count + 1
    let prefix = "beat.\(contract.id.uuidString).\(session.subitemIndex)"
    let previousOutcome =
      contract.microBeats.sorted().last?.selectedOption?.outcome
      ?? contract.scopeEntryState
    let reference = """
      场 \(contract.sceneIndex)：\(contract.heading)
      本场目标：\(contract.characterGoal)
      本场阻碍：\(contract.obstacle)
      本场转折：\(contract.turn)
      本场必须到达：\(contract.outcome)
      当前已经到达：\(previousOutcome)
      """
    let difficulty = GuidedFlowDifficultyProfile(
      openness: min(3, 1 + session.targetStretch),
      constraintLoad: 2,
      causalHorizon: 1,
      stateComplexity: min(3, 1 + session.targetStretch / 2),
      executionLoad: session.stepIndex == 4 ? 3 : 2
    )

    switch session.stepIndex {
    case 0:
      return GuidedFlowChallenge(
        id: "\(prefix).purpose",
        phase: .beat,
        title: "场 \(contract.sceneIndex) · 第 \(ordinal) 次变化",
        question: "这一小步结束时，具体什么必须不同？只写一个变化。",
        whyItMatters: "一次只处理一个不可再分的情境更新，场景才不会失控。",
        placeholder: "例如：女主从相信主管没有察觉，变为怀疑自己已经暴露。",
        referenceText: reference,
        skill: .dramaticStateControl,
        answerKind: .freeText,
        options: [],
        minimumCharacters: 8,
        maximumCharacters: 160,
        reframe: "用“原来……，现在……”描述一个状态差异。",
        ruleHint: "不要写多个事件；只写这一次碰撞最终改变什么。",
        mechanismHints: ["知道了新事实", "改变了策略", "关系或权力发生变化"],
        sentenceStarter: "原来……，这一步之后……",
        minimalAssistInstruction: "只根据当前场景契约补一个 before → after 变化，不写动作、对白或后续。",
        successContract: ["只有一个变化", "before 与 after 不同"],
        difficulty: difficulty
      )
    case 1:
      return GuidedFlowChallenge(
        id: "\(prefix).action",
        phase: .beat,
        title: "人物先采取行动",
        question: "为了造成这次变化，视点人物先做什么，或说出什么具有目的的话？",
        whyItMatters: "人物行动，而不是作者解释，推动场景。",
        placeholder: "例如：女主故意把错误日期说出口，观察主管是否纠正。",
        referenceText: reference + "\n本次目标变化：\(session.answer(for: "\(prefix).purpose"))",
        skill: .dialogueAndAction,
        answerKind: .freeText,
        options: [],
        minimumCharacters: 6,
        maximumCharacters: 180,
        reframe: "他为了得到本场目标，能做的最小测试是什么？",
        ruleHint: "动作或台词必须带有目的，不能只写情绪。",
        mechanismHints: ["试探", "隐瞒", "交换", "威胁", "请求"],
        sentenceStarter: "为了……，他……",
        minimalAssistInstruction: "只补一个人物行动或一句具有目的的话，不写反作用、转折和完整段落。",
        successContract: ["人物主动", "行动服务于目标"],
        difficulty: difficulty
      )
    case 2:
      return GuidedFlowChallenge(
        id: "\(prefix).opposition",
        phase: .beat,
        title: "让现实立即反作用",
        question: "对方、规则或现实条件立刻怎样反作用，使这次行动不能顺利完成？",
        whyItMatters: "行动与反作用的碰撞才产生戏剧。",
        placeholder: "例如：主管没有纠正日期，反而反问她从哪里看到病历。",
        referenceText: reference + "\n人物行动：\(session.answer(for: "\(prefix).action"))",
        skill: .oppositionAndStakes,
        answerKind: .freeText,
        options: [],
        minimumCharacters: 6,
        maximumCharacters: 180,
        reframe: "这个行动最可能触发什么直接而具体的回击？",
        ruleHint: "反作用必须由当前行动触发，不能是无关事件。",
        mechanismHints: ["对方反问", "规则要求证明", "空间或物件暴露了行动"],
        sentenceStarter: "但对方立刻……",
        minimalAssistInstruction: "只补当前行动的一个直接反作用，不写转折、结果或下一步。",
        successContract: ["由当前行动触发", "形成具体阻力"],
        difficulty: difficulty
      )
    case 3:
      return GuidedFlowChallenge(
        id: "\(prefix).turn",
        phase: .beat,
        title: "确认碰撞后的新局面",
        question: "行动与反作用碰撞后，出现了什么新事实、决定或关系变化？",
        whyItMatters: "这一步必须留下可以进入下一步的新状态。",
        placeholder: "例如：女主确认主管早已看过录音，却仍不知道他为何装作不知情。",
        referenceText: reference
          + "\n人物行动：\(session.answer(for: "\(prefix).action"))"
          + "\n直接反作用：\(session.answer(for: "\(prefix).opposition"))",
        skill: .dramaticStateControl,
        answerKind: .freeText,
        options: [],
        minimumCharacters: 8,
        maximumCharacters: 180,
        reframe: "完成这一步以后，人物或观众多知道、少拥有或新决定了什么？",
        ruleHint: "结果必须能够用 before → after 表达。",
        mechanismHints: ["确认一个怀疑", "失去一个选择", "作出一个不能收回的决定"],
        sentenceStarter: "碰撞之后……",
        minimalAssistInstruction: "只补这次碰撞产生的一个新状态，不写剧本文字或后续更新。",
        successContract: ["形成新状态", "能推动下一小步"],
        difficulty: difficulty
      )
    case 4:
      return GuidedFlowChallenge(
        id: "\(prefix).text",
        phase: .beat,
        title: "把这一小步写进剧本",
        question: "把刚才这一次变化写成 1—6 行可直接进入剧本的动作或对白。",
        whyItMatters: "AI 不代写整场；正文由你已经确认的小决定逐段组成。",
        placeholder: "只写当前动作与对白，不重复场景标题，不解释人物心理。",
        referenceText: reference
          + "\n人物行动：\(session.answer(for: "\(prefix).action"))"
          + "\n反作用：\(session.answer(for: "\(prefix).opposition"))"
          + "\n新局面：\(session.answer(for: "\(prefix).turn"))",
        skill: .dialogueAndAction,
        answerKind: .freeText,
        options: [],
        minimumCharacters: 8,
        maximumCharacters: 420,
        reframe: "先写人物能被拍到的动作，再决定是否需要一句话。",
        ruleHint: "不要写分析、镜头或整场；只兑现当前这一项情境更新。",
        mechanismHints: ["一个动作 + 对方反应", "一句试探 + 一次回避", "沉默 + 物件状态改变"],
        sentenceStarter: "人物做了什么。\n\n人物名\n一句带目的的话。",
        minimalAssistInstruction: "只把已确认的行动、反作用和结果转成不超过 6 行 Fountain 动作或对白；不得补场景标题、下一小节拍或完整场景。",
        successContract: ["只兑现当前更新", "可直接进入 Fountain 正文"],
        difficulty: difficulty
      )
    case 5:
      let options =
        contract.microBeats.count >= 12
        ? ["这一场已经完成"]
        : ["还需要一次变化", "这一场已经完成"]
      return GuidedFlowChallenge(
        id: "\(prefix).gate",
        phase: .beat,
        title: "只决定是否继续这一场",
        question: "现在是否已经完成本场目标、转折和离场结果？",
        whyItMatters: "场景只保留必要的变化，不为凑长度增加内容。",
        placeholder: "选择一个即可。",
        referenceText: reference,
        skill: .revisionAndContinuity,
        answerKind: .choice,
        options: options,
        minimumCharacters: 2,
        maximumCharacters: 30,
        reframe: "检查当前状态是否已经等于本场离场结果。",
        ruleHint: "如果目标、转折或结果还没有兑现，就继续一次；否则立即结束。",
        mechanismHints: options,
        sentenceStarter: "",
        minimalAssistInstruction: "只判断当前场景是否已经满足既定目标和离场结果；不得续写内容。",
        successContract: ["只作继续或完成判断"],
        difficulty: difficulty
      )
    default:
      return nil
    }
  }

  static func screenplayChallenge(
    session: GuidedFlowSession,
    project: StoryProject
  ) -> GuidedFlowChallenge? {
    let scenes = orderedScenes(in: project)
    guard scenes.indices.contains(session.itemIndex) else { return nil }
    let contract = scenes[session.itemIndex]
    let sceneText = (try? SceneBeatMappingEngine.screenplayScene(for: contract)) ?? ""
    return GuidedFlowChallenge(
      id: "screenplay.verify.\(contract.id.uuidString)",
      phase: .screenplay,
      title: "确认第 \(contract.sceneIndex) 场",
      question: "只检查一个问题：这场结束时是否实现了“\(contract.outcome)”？成立就选择“确认这一场”；不成立只写一个需要修复的问题。",
      whyItMatters: "先逐场确认，再形成完整剧本；不一次性重写全本。",
      placeholder: "确认这一场；或写：还缺少……",
      referenceText: sceneText,
      skill: .revisionAndContinuity,
      answerKind: .confirmation,
      options: ["确认这一场"],
      minimumCharacters: 2,
      maximumCharacters: 160,
      reframe: "只比较场景离场结果与实际正文，不评价所有写作问题。",
      ruleHint: "如果不成立，只指出一个最关键缺口，系统会把它变成下一项小挑战。",
      mechanismHints: ["确认这一场", "还缺少一个明确的离场决定", "观众尚未看见关键状态变化"],
      sentenceStarter: "还缺少……",
      minimalAssistInstruction: "只判断当前场景是否兑现离场结果，并指出最多一个缺口；不得重写场景或全本。",
      successContract: ["只确认当前场", "一次最多指出一个缺口"],
      difficulty: GuidedFlowDifficultyProfile(
        openness: 1,
        constraintLoad: 2,
        causalHorizon: 2,
        stateComplexity: 2,
        executionLoad: 1
      )
    )
  }

}
