import Foundation

struct DeepSeekClient {
    let configuration: AIConfiguration

    fileprivate static let simplifiedChinesePolicy = """
    所有面向作者的中文自然语言内容必须使用现代标准简体中文。禁止使用繁体中文；
    如果输入资料中含有繁体中文，理解其含义后也必须用简体中文输出。JSON 字段名和
    结构规则保持不变。
    """

    func cultivateStorySeed(
        _ context: StoryCultivationContext
    ) async throws -> DeepSeekStoryCultivationCompletion {
        let systemPrompt = """
        你是“正念故事实验室”的导航员，不是代写编剧。
        你的职责是分析、追问、建模、推演和提出实验；作者负责价值判断、审美选择与最终创造。
        禁止续写完整故事、场景或剧本，禁止用单一分数评价审美价值。
        回答必须先形成“发现”和“隐藏问题”，再给恰好三个单变量条件实验。
        每个实验只能包含一个变量；可以改变地点、时间、时间速度、人物背景、年龄、信息差、真伪状态、动机、关系、权力结构或冲突条件。
        三个实验应改变不同条件，不能只是改名字、职业或措辞。每个变量提供2到4个互斥选项，选项必须短而具体。
        当作者刚完成一次选择时，必须比较原版与变体：说明结构、人物、台词、情绪的变化，列出不变项，并提出三个具体问题；不要替作者判断哪个版本更好。
        人类需求只能使用：生存、安全、归属、尊严、自我实现。故事原子类型只能使用：人物、情绪、画面、事件、世界规则、对白、关系、未知、选择。
        只输出合法 JSON，不使用 Markdown，不输出 JSON 之外的文字。

        JSON 格式：
        {
          "atoms":[{"content":"原始输入中的具体原子","type":"人物/情绪/画面/事件/世界规则/对白/关系/未知/选择","importance":0.8}],
          "characters":["人物概念"],
          "humanNeeds":["安全","归属"],
          "desires":["可见欲望"],
          "fears":["具体恐惧"],
          "contradictions":["人物内部矛盾"],
          "valueConflicts":["价值A vs 价值B"],
          "dramaticQuestions":["必须由行动回答的问题"],
          "themes":["主题假设，不是结论"],
          "psychology":[{"character":"人物","need":"归属","desire":"欲望","fear":"恐惧","wound":"创伤或尚待发现","belief":"错误信念或尚待发现","defense":"否认/投射/合理化/压抑/反向形成/尚待发现","contradiction":"矛盾"}],
          "discovery":"不超过90字：你现在创造的是什么",
          "hiddenQuestion":"不超过90字：表面问题下面真正需要作者决定什么",
          "experiments":[
            {
              "axis":"人物实验/冲突实验/世界实验/主题实验/结局实验",
              "title":"实验名",
              "hypothesis":"如果改变什么，会检验什么",
              "whyItMatters":"它为什么能验证故事生命力",
              "variables":[{"name":"唯一变量名","question":"改变这个条件后要观察什么","options":["选项A","选项B","选项C"]}]
            }
          ],
          "evaluation":{"strengths":["当前优势"],"gaps":["当前缺口"],"nextStep":"下一步只测试什么"},
          "crystal":{"coreIdea":"当前故事核心","characterInsight":"人物洞察","conflict":"不可两全的冲突","theme":"主题假设","whyInteresting":"为什么值得继续追随"},
          "comparison":{
            “conditionChange":"本轮唯一改变的条件",
            "structureChange":"结构与冲突如何改变；未改变则明确说明",
            "characterChange":"人物选择与稳定特征如何改变；未改变则明确说明",
            "dialogueChange":"哪些表达会失效或必须改变；没有台词时明确说明",
            "emotionChange":"情绪与节奏如何改变；未改变则明确说明",
            "invariants":["仍然成立的故事特征"],
            "questions":["帮助作者看见隐含假设的问题1","条件化问题2","关于自身惯性的问题3"]
          }
        }
        必须返回恰好三个 experiments，且每个 experiment 必须恰好包含一个 variable。信息不够时写“尚待实验”，不要擅自补成事实。
        """

        let userPrompt = """
        【原始创意】
        \(context.rawIdea)

        【作者特别想探索】
        \(context.authorIntent.isEmpty ? "尚未指定。" : context.authorIntent)

        【此前培养状态】
        \(context.previousState.isEmpty ? "这是第一轮培养。" : context.previousState)

        【作者刚完成的实验选择】
        \(context.authorChoice.isEmpty ? "尚无。" : context.authorChoice)

        【相关故事理论】
        \(context.theoryContext.isEmpty ? "本轮没有命中理论片段。" : context.theoryContext)

        只把作者明确选择的一个条件作为本轮变量，其他条件保持不变。从作者已经选择的内容继续培养，但不要替作者决定答案。只输出严格 JSON。
        """

        let response = try await complete(
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            maxTokens: 3_600,
            jsonMode: true,
            temperature: 0.62,
            thinkingEnabled: false
        )
        guard let data = response.content.extractedJSONObject.data(using: .utf8) else {
            throw DeepSeekError.invalidJSON
        }
        do {
            let result = try JSONDecoder().decode(StoryCultivationAIResult.self, from: data)
            guard result.experiments.count == 3,
                  result.experiments.allSatisfy({ $0.variables.count == 1 }) else {
                throw DeepSeekError.decoding("故事培养必须返回三个实验，且每个实验只能包含一个变量。")
            }
            return DeepSeekStoryCultivationCompletion(result: result, usage: response.usage)
        } catch let error as DeepSeekError {
            throw error
        } catch {
            throw DeepSeekError.decoding(error.localizedDescription)
        }
    }

    func generateJourneyDecision(
        _ context: StoryJourneyContext
    ) async throws -> DeepSeekJourneyDecisionCompletion {
        let systemPrompt = """
        你是一位让作者对故事产生好奇心的互动编剧导师。
        你的工作不是诊断缺少什么，也不是布置抽象作业，而是把下一步变成一次令人想点击的故事选择。
        一次只解决一个高杠杆问题。必须给出4个具体、互不重复、会真正改变后续剧情的选项。
        每个选项必须来自当前项目，包含可拍摄的具体细节、选择代价、下一层压力和一个能让作者看见电影画面的瞬间。
        四个方向应分别具有不同的情感动力或叙事风险；至少一个大胆但合理，至少一个从关系出发，不能只是替换职业、地点或名字。
        如果提供了现实资料包，四个方向必须分别从人物关系、制度机制、历史回声、地域或物质细节四组不同证据生长。
        每个方向至少使用两条明确证据和一个可拍摄的职业、流程、地点或物件细节；只能计算资料包中真实存在的独立来源。
        如果项目提供“本阶段节奏与情绪硬约束”，四个选项必须全部服从，并在paceEffect、emotionShift、eventScale中具体说明实现方式。
        不使用“完善人物”“增加冲突”“补充背景”一类空洞措辞。
        不承诺爆款，不复制参考作品的情节和表达，不替作者一次写完整剧本。
        输出严格合法 JSON，不使用 Markdown，不输出 JSON 之外的文字。

        JSON 格式：
        {
          "question":"具体而有诱惑力的选择问题",
          "coachNote":"不超过80字，解释这次选择会改变故事的什么",
          "options":[
            {
              "title":"8到16字、能记住的选项名",
              "pitch":"这个方向具体发生什么，80到140字",
              "concreteDetail":"一个人物、物件、秘密、期限或地点细节",
              "consequence":"选择它必须付出的代价",
              "futurePressure":"它会为下一阶段制造什么麻烦",
              "sampleMoment":"一句可视化的场面预告，不写完整场景",
              "evidenceBasis":["实际使用的事实，保留[S编号]，2到4条"],
              "sourceCount":3,
              "realityTexture":"最能让这个方向可信的职业、流程、地点或物件细节",
              "paceEffect":"它如何兑现本阶段速度要求",
              "emotionShift":"观众情绪从什么变为什么",
              "eventScale":"本轮实际发生的是新人物、危机、揭示、关系加深或局部结算"
            }
          ]
        }
        """

        let userPrompt = """
        【本项目采用的结构规则】
        模板：\(context.templateName)
        \(context.templateRules)

        当前阶段：\(context.stageName)
        本阶段目标：\(context.stagePurpose)
        本轮选择焦点：\(context.choiceFocus)

        【当前故事】
        \(context.projectContext)

        【现实资料包】
        \(context.realityContext.isEmpty ? "当前项目没有独立的现实研究资料包。" : context.realityContext)

        【相关理论】
        \(context.theoryContext.isEmpty ? "没有命中理论片段。" : context.theoryContext)

        【可比较的经典功能】
        \(context.storyDNAContext.isEmpty ? "没有匹配案例。" : context.storyDNAContext)

        请基于作者已经选择的内容继续向前，不要推翻已确定事实。输出4个细节充分的选项。
        """

        let response = try await complete(
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            maxTokens: 2_800,
            jsonMode: true,
            temperature: 0.82
        )
        guard let data = response.content.extractedJSONObject.data(using: .utf8) else {
            throw DeepSeekError.invalidJSON
        }
        do {
            let result = try JSONDecoder().decode(JourneyDecisionResult.self, from: data)
            guard result.options.count == 4 else {
                throw DeepSeekError.decoding("AI没有返回恰好四个完整选项。")
            }
            return DeepSeekJourneyDecisionCompletion(result: result, usage: response.usage)
        } catch let error as DeepSeekError {
            throw error
        } catch {
            throw DeepSeekError.decoding(error.localizedDescription)
        }
    }

    func regenerateJourneyOption(
        _ context: JourneyOptionRefinementContext
    ) async throws -> DeepSeekJourneyOptionCompletion {
        let systemPrompt = """
        你是一位执行精确局部重做的专业影视编剧。
        本轮只能重做作者指定的一个候选项，其他三个候选、已确认事实、锁定结构和此前阶段一律不动。
        必须具体回应作者的自然语言指导，同时保持本阶段的结构功能。除非作者明确要求，否则不要把它改成另一个候选的同义版本。
        重做后的选项仍须服从当前阶段的速度、情绪强度和事件尺度约束。
        现实资料只用于增加可信的制度、职业、历史、地域和物质细节，不得把推测伪装成事实。
        输出严格合法JSON，不使用Markdown，不输出JSON之外的文字。

        JSON格式：
        {
          "option":{
            "title":"8到16字的选项名",
            "pitch":"重做后的具体方向，80到160字",
            "concreteDetail":"一个人物、物件、秘密、期限或地点细节",
            "consequence":"选择它必须承担的代价",
            "futurePressure":"它给下一阶段制造的压力",
            "sampleMoment":"一句可视化场面预告",
            "evidenceBasis":["实际使用的资料依据，0到4条"],
            "sourceCount":0,
            "realityTexture":"一个可信的流程、空间、物件或风俗细节",
            "paceEffect":"如何兑现当前速度要求",
            "emotionShift":"观众情绪变化",
            "eventScale":"实际事件尺度"
          }
        }
        """
        let userPrompt = """
        【锁定结构】
        \(context.templateName)
        \(context.templateRules)

        【当前结构阶段】
        \(context.stageName)
        目标：\(context.stagePurpose)
        选择焦点：\(context.choiceFocus)

        【项目与此前选择】
        \(context.projectContext)

        【只能重做的当前选项】
        \(context.currentOption)

        【保持不动的另外三个选项】
        \(context.siblingOptions)

        【作者本轮唯一指导】
        \(context.authorInstruction)

        【本阶段专项调查】
        \(context.researchContext.isEmpty ? "尚无专项调查。" : context.researchContext)

        【本项目本地偏好画像】
        \(context.preferenceContext)

        只返回重做后的这一个option。
        """
        let response = try await complete(
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            maxTokens: 1_400,
            jsonMode: true,
            temperature: 0.72,
            thinkingEnabled: false
        )
        guard let data = response.content.extractedJSONObject.data(using: .utf8) else {
            throw DeepSeekError.invalidJSON
        }
        do {
            let result = try JSONDecoder().decode(
                JourneyOptionRefinementResult.self,
                from: data
            )
            return DeepSeekJourneyOptionCompletion(option: result.option, usage: response.usage)
        } catch {
            throw DeepSeekError.decoding(error.localizedDescription)
        }
    }


    func generateCharacterGraphOptions(
        _ context: CharacterGraphAIContext
    ) async throws -> DeepSeekCharacterGraphCompletion {
        let systemPrompt = """
        你是专业影视剧的人物关系设计师。你不写泛泛的人物小传，而是调整人物之间可持续制造选择、秘密、背叛、亏欠和价值冲突的关系网。
        必须尊重锁定结构和已经确认的故事阶段。每个方案都要说明它如何映射到后续结构，不得为热闹随意增加无功能人物。
        生成恰好4个实质不同的调整方案。可以新增0到2个人物、调整现有人物，或建立/替换关系。
        关系类型只能优先使用：亲属、爱恋、同盟、竞争、控制、亏欠、师徒、秘密关联、敌对。
        tension为0到100。涉及秘密时isSecret为true。
        输出严格合法JSON，不使用Markdown，不输出JSON之外的文字。

        JSON格式：
        {
          "question":"本轮真正要决定的人物关系问题",
          "coachNote":"不超过100字，说明为什么现在调整",
          "options":[
            {
              "title":"方案名",
              "thesis":"这套关系网的核心戏剧机制",
              "newCharacters":[
                {"name":"姓名","role":"主人公/反派/配角等","seedText":"人物功能与矛盾","externalGoal":"目标","secret":"秘密"}
              ],
              "characterChanges":[
                {"name":"现有人物名","adjustment":"只写需要追加或改变的具体内容"}
              ],
              "relationshipChanges":[
                {"from":"人物名","to":"人物名","type":"关系类型","detail":"双方如何互相影响","tension":70,"isSecret":false}
              ],
              "structureEffect":"会改变或强化哪些后续结构阶段",
              "emotionalEffect":"观众会获得的情绪效果",
              "risk":"采用后必须处理的复杂度或风险"
            }
          ]
        }
        """
        let userPrompt = """
        【项目与锁定结构】
        \(context.projectContext)

        【当前人物与关系图】
        \(context.characterGraph)

        【作者本轮指导】
        \(context.authorInstruction)

        【本项目已经学习的偏好】
        \(context.preferenceContext)

        【私人编剧理论命中】
        \(context.theoryContext.isEmpty ? "本轮无命中。" : context.theoryContext)

        只提出候选方案。未确认前不得宣布已修改项目。
        """
        let response = try await complete(
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            maxTokens: 3_600,
            jsonMode: true,
            temperature: 0.76
        )
        guard let data = response.content.extractedJSONObject.data(using: .utf8) else {
            throw DeepSeekError.invalidJSON
        }
        do {
            let result = try JSONDecoder().decode(CharacterGraphOptionsResult.self, from: data)
            guard result.options.count == 4 else {
                throw DeepSeekError.decoding("AI没有返回恰好四个人物关系方案。")
            }
            return DeepSeekCharacterGraphCompletion(result: result, usage: response.usage)
        } catch let error as DeepSeekError {
            throw error
        } catch {
            throw DeepSeekError.decoding(error.localizedDescription)
        }
    }

    func dramatize(
        _ context: DramatizationContext,
        progress: ((Double, String) -> Void)? = nil
    ) async throws -> DeepSeekDramatizationCompletion {
        let systemPrompt = """
        你是一位擅长把现实材料转化为原创戏剧的编剧导师。
        你的目标是帮助作者发现戏剧性、提供有差异的改编道路，并让作者愿意亲自继续写。
        严格区分事实与虚构：factualSummary 只能复述材料明确提供的事实；不确定内容必须标明。
        不把真实人物的动机猜测写成事实。涉及仍在世人物时，在 fictionalizationNote 中建议改名、合并人物、改变可识别细节并核验事实。
        不直接生成完整剧本。每个方向必须拥有不同的主人公选择、对抗力量、类型承诺和价值问题。
        如果材料包含“现实资料包”，四个方向必须分别从人物关系、制度机制、历史回声、地域或物质细节生长，不能只是换职业、地点或名字。
        每个方向至少使用两条带[S编号]的明确证据，并给出一个真实流程、物件、空间或生活细节。sourceCount只能计算实际使用的独立来源。
        参考案例只比较叙事功能，不复制具体情节、对白或独特表达。
        输出必须是合法 JSON 对象，不要使用 Markdown，不要输出 JSON 之外的文字。

        JSON 格式：
        {
          "factualSummary": "只包含来源明确事实的简洁摘要",
          "dramaticCore": "这份材料最值得改编的核心矛盾，不超过100字",
          "dramaticElements": [
            {"label":"欲望/阻碍/代价/秘密/关系/反转之一","finding":"基于材料的具体发现"}
          ],
          "directions": [
            {
              "title":"改编方向名称",
              "genre":"类型",
              "protagonist":"最适合承担故事的人及其处境",
              "desire":"可见且具体的目标",
              "antagonistForce":"阻止目标的个人、制度、关系或内心力量",
              "stakes":"失败将失去什么",
              "dramaticQuestion":"故事最终要用行动回答的问题",
              "logline":"包含主角、目标、阻力和代价的一句话故事",
              "fictionalizationNote":"事实与虚构边界及安全改编建议",
              "nextTaskTitle":"作者下一道命题标题",
              "nextTaskPrompt":"100至500字即可完成、有明确约束的写作任务",
              "evidenceBasis":["该方向实际使用的事实，保留[S编号]，2到4条"],
              "sourceCount":3,
              "realityTexture":"一个具体的职业流程、地点、物件或生活细节"
            }
          ],
          "questions":["还需核实或最值得作者决定的问题"]
        }
        生成4个真正不同的 directions，dramaticElements 生成5到7项。
        信息要饱满但避免重复：除 nextTaskPrompt 外，单个字段不超过90字；nextTaskPrompt 控制在100到180字；
        每个 direction 的全部字段合计不超过650字，确保四条路线能一次完整返回。
        """

        let userPrompt = """
        素材类型：\(context.sourceType)
        素材标题：\(context.title)
        作者想探索：\(context.authorIntent.isEmpty ? "尚未指定，请从材料本身发现可能性。" : context.authorIntent)

        【素材权威与版权规则】
        - 网页新闻、资料 Markdown 与 TXT：明确来源内容可进入事实层，推测必须标出。
        - 小说 Markdown：把原作人物、世界和事件视为改编原作的 canon，不假装成现实事实；指出允许改编的边界。
        - 参考剧本 Markdown：只能提取结构功能、冲突机制、节奏和观看体验，禁止复现具体情节、对白、人物或独特表达。
        - 临时想法：作者输入拥有最高创意权威，不要擅自把含糊处补成事实。
        只应用与当前“素材类型”相符的规则。

        【现实材料】
        \(context.sourceMaterial)

        【编剧理论检索】
        \(context.theoryContext.isEmpty ? "没有命中片段。" : context.theoryContext)

        【经典故事DNA】
        \(context.storyDNAContext.isEmpty ? "没有匹配案例。" : context.storyDNAContext)

        请把事实层与虚构提案清楚分开，输出严格 JSON。
        """

        progress?(0.70, "阶段 4/5 · DeepSeek 正在生成四条故事路线")
        let response = try await complete(
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            maxTokens: 4_200,
            jsonMode: true,
            temperature: 0.72,
            thinkingEnabled: false
        )

        progress?(0.84, "阶段 5/5 · 校验四条故事路线")
        if let result = try? decodeDramatizationResult(response.content) {
            return DeepSeekDramatizationCompletion(result: result, usage: response.usage)
        }

        // A long, research-backed response can occasionally be cut off or carry a
        // malformed field. Retry once with a compact contract and no reasoning tokens.
        progress?(0.86, "首次结果不完整，正在精简重试")
        let recoveryResponse = try await complete(
            messages: [
                .init(
                    role: "system",
                    content: """
                    \(systemPrompt)

                    上一次输出未能被程序完整读取。现在重新生成：只输出一个完整 JSON 对象，
                    必须包含四个 directions。所有字段保持简洁，绝不使用 Markdown、注释或 JSON 之外的文字。
                    """
                ),
                .init(role: "user", content: userPrompt)
            ],
            maxTokens: 4_800,
            jsonMode: true,
            temperature: 0.38,
            thinkingEnabled: false
        )
        progress?(0.92, "阶段 5/5 · 校验重试结果")

        do {
            let result = try decodeDramatizationResult(recoveryResponse.content)
            return DeepSeekDramatizationCompletion(result: result, usage: recoveryResponse.usage)
        } catch {
            throw DeepSeekError.incompleteStoryRoutes
        }
    }

    private func decodeDramatizationResult(_ content: String) throws -> DramatizationResult {
        guard let data = content.extractedJSONObject.data(using: .utf8) else {
            throw DeepSeekError.invalidJSON
        }
        let result = try JSONDecoder().decode(DramatizationResult.self, from: data)
        guard result.directions.count >= 4 else {
            throw DeepSeekError.incompleteStoryRoutes
        }
        return result
    }

    func generateProjectModuleOptions(
        _ context: ProjectModuleAIContext
    ) async throws -> DeepSeekProjectModuleCompletion {
        let systemPrompt = """
        你是一位与人类作者共同工作的专业编剧编辑。
        人类作者拥有最终决定权。你不能覆盖作者原始灵感，也不能把候选内容直接视为正式剧本。
        你的任务是基于当前项目，为一个明确模块提出4个真正不同、可以选择和继续编辑的方向。
        必须保留“不可改动的决定”。四个方向要在人物选择、关系动力、叙事风险或戏剧效果上有实质差异，不能只替换名字、职业或地点。
        每个方向都要给出一份可以直接进入人工审阅的完整草稿，并明确它会怎样改变故事、作者要接受什么取舍。
        当存在审阅意见时，先理解作者真正不满意的原因，再让四个方向用四种不同设计策略回应；不得只做措辞改写。
        只吸收理论片段中与本模块直接相关的原则，不堆砌术语，不复制经典作品的具体情节与表达。
        如果作者给了额外命令，把它作为本轮候选的局部约束。
        输出严格合法 JSON，不使用 Markdown，不输出 JSON 之外的文字。

        JSON格式：
        {
          "guidance":"不超过100字，说明本轮最值得作者决定的核心分歧",
          "options":[
            {
              "title":"8到16字的方向名",
              "oneLine":"一句话说明这个方向",
              "draftText":"可直接审阅和修改的完整模块草稿，具体、连贯、不过度扩写",
              "storyEffect":"它会为人物、结构、情绪或类型带来什么效果",
              "tradeoff":"采用它必须放弃、承担或随后解决什么",
              "preservedIdeas":["明确保留的用户灵感或已确认事实"],
              "responseToFeedback":"这个方向具体如何回应作者最新审阅意见"
            }
          ]
        }
        必须返回恰好4个完整options。
        """
        let userPrompt = """
        【项目】
        标题：\(context.projectTitle)
        类型：\(context.genre)
        项目整体创作方向：\(context.projectCreativeDirection.isEmpty ? "尚未设定。" : context.projectCreativeDirection)
        结构规则：
        \(context.structureRules)

        【当前模块】
        类型：\(context.moduleKind)
        名称：\(context.moduleTitle)
        专业目标：\(context.moduleFocus)

        【用户原始灵感，必须保留并显性回应】
        \(context.humanInput.isEmpty ? "用户尚未输入。" : context.humanInput)

        【不可改动的决定】
        \(context.lockedIdeas.isEmpty ? "没有额外锁定项。" : context.lockedIdeas)

        【历次审阅形成的作者偏好】
        \(context.authorGuidance.isEmpty ? "尚未积累。" : context.authorGuidance)

        【当前审阅稿】
        \(context.currentDraft.isEmpty ? "尚无草稿。" : context.currentDraft)

        【本轮命令】
        \(context.authorCommand.isEmpty ? "生成四个有实质差异的方向。" : context.authorCommand)

        【项目内已经确认的上下文】
        \(context.projectContext)

        【私人编剧书库依据】
        \(context.theoryContext.isEmpty ? "本轮没有命中理论片段。" : context.theoryContext)

        【可比较的经典叙事功能】
        \(context.storyDNAContext.isEmpty ? "本轮不使用经典案例。" : context.storyDNAContext)

        【为当前模块专项调查的现实资料】
        \(context.researchContext.isEmpty ? "尚未进行专项调查。" : context.researchContext)

        最新审阅意见的优先级高于一般建议。四个方向必须在responseToFeedback中说明回应方式。
        只提出候选，不宣布任何内容已经进入正式剧本。输出严格JSON。
        """
        let response = try await complete(
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            maxTokens: 4_200,
            jsonMode: true,
            temperature: 0.78
        )
        guard let data = response.content.extractedJSONObject.data(using: .utf8) else {
            throw DeepSeekError.invalidJSON
        }
        do {
            let result = try JSONDecoder().decode(ProjectModuleOptionsResult.self, from: data)
            guard result.options.count == 4 else {
                throw DeepSeekError.decoding("AI没有返回四个完整方向。")
            }
            return DeepSeekProjectModuleCompletion(result: result, usage: response.usage)
        } catch let error as DeepSeekError {
            throw error
        } catch {
            throw DeepSeekError.decoding(error.localizedDescription)
        }
    }

    func refineProjectModule(
        _ context: ProjectModuleRefinementContext
    ) async throws -> DeepSeekProjectModuleRefinementCompletion {
        let systemPrompt = """
        你是一位执行精确局部修改的专业剧本编辑。
        只执行作者本轮明确提出的微调，不主动扩写新支线，不改变核心事实，不推翻用户原始灵感和锁定决定。
        未被命令涉及的内容尽量原样保留。如果命令与锁定决定冲突，保留锁定决定，并在changeSummary中简洁说明。
        理论依据只用于提高修改质量，不要在稿件里讲解理论。
        输出严格合法 JSON，不使用 Markdown，不输出 JSON 之外的文字。

        JSON格式：
        {
          "revisedText":"完成局部修改后的完整文本",
          "changeSummary":"不超过80字，准确说明改了什么、什么保持不变",
          "preservedIdeas":["本次明确保留的用户想法和已确认事实"]
        }
        """
        let userPrompt = """
        项目：\(context.projectTitle)
        类型：\(context.genre)
        项目整体创作方向：\(context.projectCreativeDirection.isEmpty ? "尚未设定。" : context.projectCreativeDirection)
        模块：\(context.moduleKind) · \(context.moduleTitle)
        模块目标：\(context.moduleFocus)

        【用户原始灵感】
        \(context.humanInput)

        【绝对不可改动】
        \(context.lockedIdeas.isEmpty ? "没有额外锁定项。" : context.lockedIdeas)

        【历次审阅形成的作者偏好】
        \(context.authorGuidance.isEmpty ? "尚未积累。" : context.authorGuidance)

        【当前文本】
        \(context.currentDraft)

        【唯一修改命令】
        \(context.authorCommand)

        【项目已确认上下文】
        \(context.projectContext)

        【相关专业依据】
        \(context.theoryContext.isEmpty ? "无。" : context.theoryContext)

        【当前模块专项调查】
        \(context.researchContext.isEmpty ? "尚无专项资料。" : context.researchContext)

        只做命令要求的最小必要改动，输出修改后的完整文本。
        """
        let response = try await complete(
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            maxTokens: 3_200,
            jsonMode: true,
            temperature: 0.28,
            thinkingEnabled: false
        )
        guard let data = response.content.extractedJSONObject.data(using: .utf8) else {
            throw DeepSeekError.invalidJSON
        }
        do {
            let result = try JSONDecoder().decode(ProjectModuleRefinementResult.self, from: data)
            guard !result.revisedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DeepSeekError.emptyContent
            }
            return DeepSeekProjectModuleRefinementCompletion(
                result: result,
                usage: response.usage
            )
        } catch let error as DeepSeekError {
            throw error
        } catch {
            throw DeepSeekError.decoding(error.localizedDescription)
        }
    }

    func analyze(_ context: RemoteAnalysisContext) async throws -> DeepSeekCompletion {
        let systemPrompt = """
        你是一位严格、具体、尊重作者主体性的商业影视编剧导师。
        你的任务是诊断和提出可执行命题，不是替作者续写，也不承诺作品会成为爆款。
        只依据用户提供的材料、结构化案例摘要和检索到的理论片段判断。
        缺少信息时明确说“尚未建立”，不要自行补全事实。
        参考案例只能比较叙事功能和模式，不能要求模仿具体情节。
        理论片段是约束判断的证据，不是要求堆砌的引文。只有在理论片段实际支持时，才能在 theoryBasis 中写出对应的书名和章节；不得编造书名、章节或页码。
        先判断作者材料，再以证据解释“为什么这个缺口重要”。每条建议必须能被作者通过写作行动验证。
        输出必须是一个合法 JSON 对象，不要使用 Markdown，不要输出 JSON 之外的文字。

        不得输出“故事得分”“成熟度总分”或任何把审美、因果、类型与偏好压成单一数字的字段。
        JSON 格式必须包含以下键：
        {
          "summary": "不超过120字的核心判断",
          "strengths": ["已有且有证据的优势"],
          "gaps": ["按优先级排列的缺口"],
          "recommendations": ["具体可执行的改进方向"],
          "commercialPatterns": ["可比较的成功叙事模式及差异"],
          "theoryBasis": ["理论依据；有资料时标注文档与页码"],
          "antagonistSuggestion": "人物诊断时给出反派功能、信念、关系和威胁；其他模块可为空字符串",
          "nextTaskTitle": "下一道命题标题",
          "nextTaskPrompt": "有约束、可直接动笔完成的创作任务",
          "questions": ["最值得作者自己回答的2到4个问题"]
        }
        """

        let userPrompt = """
        诊断模块：\(context.sectionName)
        项目类型：\(context.genre)

        【本次专业诊断框架】
        \(context.theoryFocus)

        【作者材料】
        \(context.authorMaterial)

        【Story DNA 案例摘要】
        \(context.storyDNAContext.isEmpty ? "没有匹配案例。" : context.storyDNAContext)

        【私人编剧知识库检索】
        \(context.knowledgeContext.isEmpty ? "本次没有检索到相关片段。" : context.knowledgeContext)

        只报告可定位的优势、缺口、证据与可执行选择，不计算总分。
        请输出严格 JSON。
        """

        let response = try await complete(
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            maxTokens: 2_800,
            jsonMode: true
        )

        guard let jsonData = response.content.extractedJSONObject.data(using: .utf8) else {
            throw DeepSeekError.invalidJSON
        }
        do {
            let result = try JSONDecoder().decode(AIAnalysisResult.self, from: jsonData)
            return DeepSeekCompletion(result: result, usage: response.usage)
        } catch {
            throw DeepSeekError.decoding(error.localizedDescription)
        }
    }

    func testConnection() async throws -> String {
        let response = try await complete(
            messages: [
                .init(role: "system", content: "只输出合法 JSON。"),
                .init(role: "user", content: "请输出 {\"ok\":true} 用于连接测试。")
            ],
            maxTokens: 40,
            jsonMode: true
        )
        guard response.content.contains("true") else {
            throw DeepSeekError.invalidResponse
        }
        return response.model
    }

    private func complete(
        messages: [ChatMessage],
        maxTokens: Int,
        jsonMode: Bool,
        temperature: Double = 0.35,
        thinkingEnabled: Bool? = nil
    ) async throws -> RawCompletion {
        let endpoint = configuration.chatCompletionsEndpoint
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")

        let payload = ChatRequest(
            model: configuration.model,
            messages: messages.appendingSimplifiedChinesePolicy,
            thinking: configuration.provider.supportsDeepSeekThinking
                ? .init(
                    type: (thinkingEnabled ?? configuration.thinkingEnabled)
                        ? "enabled"
                        : "disabled"
                )
                : nil,
            maxTokens: maxTokens,
            temperature: temperature,
            responseFormat: jsonMode ? .init(type: "json_object") : nil,
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw DeepSeekError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            let message = envelope?.error?.message
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(httpResponse.statusCode)"
            throw DeepSeekError.api(status: httpResponse.statusCode, message: message)
        }

        let decoded: ChatResponse
        do {
            decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw DeepSeekError.decoding(error.localizedDescription)
        }
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw DeepSeekError.emptyContent
        }
        return RawCompletion(
            content: content.simplifiedChinese,
            model: decoded.model,
            usage: decoded.usage ?? .zero
        )
    }
}

private extension Array where Element == ChatMessage {
    var appendingSimplifiedChinesePolicy: [ChatMessage] {
        var adjusted = self
        if let systemIndex = adjusted.firstIndex(where: { $0.role == "system" }) {
            let existing = adjusted[systemIndex]
            adjusted[systemIndex] = ChatMessage(
                role: existing.role,
                content: "\(existing.content)\n\n\(DeepSeekClient.simplifiedChinesePolicy)"
            )
        } else {
            adjusted.insert(
                ChatMessage(role: "system", content: DeepSeekClient.simplifiedChinesePolicy),
                at: 0
            )
        }
        return adjusted
    }
}

struct ProjectModuleAIContext {
    let projectTitle: String
    let genre: String
    let projectCreativeDirection: String
    let structureRules: String
    let moduleKind: String
    let moduleFocus: String
    let moduleTitle: String
    let humanInput: String
    let lockedIdeas: String
    let authorGuidance: String
    let currentDraft: String
    let authorCommand: String
    let projectContext: String
    let theoryContext: String
    let storyDNAContext: String
    let researchContext: String
}

struct StoryCultivationContext {
    let rawIdea: String
    let authorIntent: String
    let previousState: String
    let authorChoice: String
    let theoryContext: String
}

struct DeepSeekStoryCultivationCompletion {
    let result: StoryCultivationAIResult
    let usage: TokenUsage
}

struct ProjectModuleRefinementContext {
    let projectTitle: String
    let genre: String
    let projectCreativeDirection: String
    let moduleKind: String
    let moduleFocus: String
    let moduleTitle: String
    let humanInput: String
    let lockedIdeas: String
    let authorGuidance: String
    let currentDraft: String
    let authorCommand: String
    let projectContext: String
    let theoryContext: String
    let researchContext: String
}

struct DeepSeekProjectModuleCompletion {
    let result: ProjectModuleOptionsResult
    let usage: TokenUsage
}

struct DeepSeekProjectModuleRefinementCompletion {
    let result: ProjectModuleRefinementResult
    let usage: TokenUsage
}

struct DramatizationContext {
    let sourceType: String
    let title: String
    let sourceMaterial: String
    let authorIntent: String
    let theoryContext: String
    let storyDNAContext: String
}

struct DeepSeekDramatizationCompletion {
    let result: DramatizationResult
    let usage: TokenUsage
}

struct StoryJourneyContext {
    let templateName: String
    let templateRules: String
    let stageName: String
    let stagePurpose: String
    let choiceFocus: String
    let projectContext: String
    let theoryContext: String
    let storyDNAContext: String
    let realityContext: String
}

struct JourneyOptionRefinementContext {
    let templateName: String
    let templateRules: String
    let stageName: String
    let stagePurpose: String
    let choiceFocus: String
    let projectContext: String
    let currentOption: String
    let siblingOptions: String
    let authorInstruction: String
    let researchContext: String
    let preferenceContext: String
}

struct CharacterGraphAIContext {
    let projectContext: String
    let characterGraph: String
    let authorInstruction: String
    let preferenceContext: String
    let theoryContext: String
}

struct DeepSeekJourneyDecisionCompletion {
    let result: JourneyDecisionResult
    let usage: TokenUsage
}

struct DeepSeekJourneyOptionCompletion {
    let option: StoryChoiceOption
    let usage: TokenUsage
}

struct DeepSeekCharacterGraphCompletion {
    let result: CharacterGraphOptionsResult
    let usage: TokenUsage
}

struct DeepSeekBlueprintCompletion {
    let blueprint: JourneyBlueprint
    let usage: TokenUsage
}

struct RemoteAnalysisContext {
    let sectionName: String
    let genre: String
    let authorMaterial: String
    let theoryFocus: String
    let storyDNAContext: String
    let knowledgeContext: String
}

struct DeepSeekCompletion {
    let result: AIAnalysisResult
    let usage: TokenUsage
}

struct AIAnalysisResult: Decodable {
    let score: Int
    let summary: String
    let strengths: [String]
    let gaps: [String]
    let recommendations: [String]
    let commercialPatterns: [String]
    let theoryBasis: [String]
    let antagonistSuggestion: String
    let nextTaskTitle: String
    let nextTaskPrompt: String
    let questions: [String]

    private enum CodingKeys: String, CodingKey {
        case score
        case summary
        case strengths
        case gaps
        case recommendations
        case commercialPatterns
        case theoryBasis
        case antagonistSuggestion
        case nextTaskTitle
        case nextTaskPrompt
        case questions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Retained as a zero-valued compatibility field for legacy SwiftData
        // reports. New analysis never requests or displays a total story score.
        score = 0
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? "本次诊断没有生成摘要。"
        strengths = try container.decodeIfPresent([String].self, forKey: .strengths) ?? []
        gaps = try container.decodeIfPresent([String].self, forKey: .gaps) ?? []
        recommendations = try container.decodeIfPresent([String].self, forKey: .recommendations) ?? []
        commercialPatterns = try container.decodeIfPresent([String].self, forKey: .commercialPatterns) ?? []
        theoryBasis = try container.decodeIfPresent([String].self, forKey: .theoryBasis) ?? []
        antagonistSuggestion = try container.decodeIfPresent(String.self, forKey: .antagonistSuggestion) ?? ""
        nextTaskTitle = try container.decodeIfPresent(String.self, forKey: .nextTaskTitle) ?? "继续探索"
        nextTaskPrompt = try container.decodeIfPresent(String.self, forKey: .nextTaskPrompt) ?? ""
        questions = try container.decodeIfPresent([String].self, forKey: .questions) ?? []
    }
}

struct TokenUsage: Decodable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int

    static let zero = TokenUsage(promptTokens: 0, completionTokens: 0, totalTokens: 0)

    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let thinking: Thinking?
    let maxTokens: Int
    let temperature: Double
    let responseFormat: ResponseFormat?
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case thinking
        case maxTokens = "max_tokens"
        case temperature
        case responseFormat = "response_format"
        case stream
    }
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct Thinking: Codable {
    let type: String
}

private struct ResponseFormat: Codable {
    let type: String
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }

    let choices: [Choice]
    let model: String
    let usage: TokenUsage?
}

private struct APIErrorEnvelope: Decodable {
    struct Body: Decodable {
        let message: String
    }
    let error: Body?
}

private struct RawCompletion {
    let content: String
    let model: String
    let usage: TokenUsage
}

enum DeepSeekError: LocalizedError {
    case network(String)
    case api(status: Int, message: String)
    case invalidResponse
    case emptyContent
    case invalidJSON
    case decoding(String)
    case outputTruncated
    case incompleteStoryRoutes

    var errorDescription: String? {
        switch self {
        case .network(let message):
            "网络请求失败：\(message)"
        case .api(let status, let message):
            "模型接口返回错误（\(status)）：\(message)"
        case .invalidResponse:
            "模型接口返回了无法识别的响应。"
        case .emptyContent:
            "模型接口没有返回内容，请重试。"
        case .invalidJSON:
            "诊断结果不是有效 JSON。"
        case .decoding(let message):
            "无法解析诊断结果：\(message)"
        case .outputTruncated:
            "模型接口的结构化输出达到长度上限。系统已自动扩大容量重试，但结果仍不完整。"
        case .incompleteStoryRoutes:
            "故事路线没有完整生成。系统已自动重试一次，请再试一次。"
        }
    }
}

private extension String {
    var extractedJSONObject: String {
        var start: Index?
        var depth = 0
        var insideString = false
        var escaped = false

        for index in indices {
            let character = self[index]

            if insideString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    insideString = false
                }
                continue
            }

            if character == "\"" {
                insideString = true
            } else if character == "{" {
                if start == nil {
                    start = index
                }
                depth += 1
            } else if character == "}", start != nil {
                depth -= 1
                if depth == 0, let start {
                    return String(self[start...index])
                }
            }
        }

        return self
    }
}
