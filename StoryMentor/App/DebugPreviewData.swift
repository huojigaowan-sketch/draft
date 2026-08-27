#if DEBUG
import SwiftData
import SwiftUI

struct DebugPreviewDataModifier: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @State private var hasBootstrapped = false

    func body(content: Content) -> some View {
        content.task {
            guard !hasBootstrapped,
                  CommandLine.arguments.contains("--ui-preview-data") else {
                return
            }
            hasBootstrapped = true
            seedPreviewProjectIfNeeded()
        }
    }

    @MainActor
    private func seedPreviewProjectIfNeeded() {
        let descriptor = FetchDescriptor<StoryProject>()
        guard (try? modelContext.fetchCount(descriptor)) == 0 else { return }

        let project = StoryProject(
            title: "纸月亮",
            genre: .thriller,
            logline: "一名替陌生人保管记忆的档案员，发现最后一份待销毁的记忆属于三天后的自己。",
            notes: "视觉克制，关系比科技设定更重要。",
            sourceTitle: "深夜档案馆的临时想法",
            sourceText: "城市允许公民在痛苦过载时寄存一段记忆，但寄存期限结束后必须永久销毁。",
            sourceFacts: "记忆寄存是一套有排队、授权、复核与销毁见证的公共制度。",
            dramaticPromise: "如果忘记痛苦才能继续生活，一个人还有没有义务保留真相？",
            storyPathText: "",
            structureTemplateID: "guided-core",
            structureTemplateName: "故事核心十问"
        )
        project.creativeDirectionText = "近未来但不炫技；所有奇观都必须落回普通人的具体生活。"
        project.worldText = "记忆只能由本人取回；销毁必须由两名工作人员交叉见证；黑市会伪造授权。"
        project.worldBibleText = "记忆寄存是一项稀缺公共服务，程序本身持续制造时间压力。"
        project.themeText = "逃离痛苦是否也意味着放弃为真相负责？"
        project.themeBibleText = "人无法靠删去痛苦获得完整自由；记住有时是一种对他人的责任。"
        project.coreConflictText = "林默必须在保护妹妹的新生活与保留一桩公共罪行的证据之间选择。"
        project.scenesText = """
        【场景 1】 夜班交接
        【场景 2】 无主记忆
        【场景 3】 妹妹来访
        【场景 4】 第一次越权
        """
        project.storyBibleDigest = """
        【人物小传】
        林默擅长替别人保管痛苦，却一直回避自己的家庭记忆。

        【世界规则】
        记忆寄存是一项稀缺公共服务，程序本身持续制造时间压力。

        【主题命题】
        人无法靠删去痛苦获得完整自由；记住有时是一种对他人的责任。

        【核心冲突】
        林默必须在保护妹妹的新生活与保留一桩公共罪行的证据之间选择。
        """
        project.storyBibleRevision = 5
        project.storyBibleUpdatedAt = .now
        project.storyBibleSyncNote = "样例项目已同步"
        project.lockStructure()

        let protagonist = StoryCharacter(
            name: "林默",
            role: .protagonist,
            age: "34",
            occupation: "记忆档案员",
            seedText: "习惯替别人承担程序责任，却拒绝回看自己的家庭创伤。",
            externalGoal: "在倒计时结束前查明未来记忆的来源",
            internalNeed: "承认记住痛苦也可能是一种责任",
            fear: "自己的选择会再次伤害妹妹",
            secret: "曾亲手批准母亲记忆的销毁",
            project: project
        )
        let sister = StoryCharacter(
            name: "林岚",
            role: .loveInterest,
            age: "29",
            occupation: "社区护士",
            seedText: "林默的妹妹，已经主动删除了事故记忆。",
            externalGoal: "阻止哥哥重新打开家庭旧案",
            internalNeed: "允许自己在安全之外重新选择",
            secret: "她其实记得销毁前最后十秒",
            project: project
        )
        let director = StoryCharacter(
            name: "周启明",
            role: .antagonist,
            age: "52",
            occupation: "记忆管理局主任",
            seedText: "真心相信有些真相不值得社会承担。",
            externalGoal: "按程序销毁异常记忆并保护制度公信力",
            internalNeed: "承认秩序不能替受害者作决定",
            project: project
        )
        let witness = StoryCharacter(
            name: "阿真",
            role: .ally,
            occupation: "黑市修复师",
            seedText: "能恢复被截断的记忆，但每次修复都会丢失自己的一段经历。",
            externalGoal: "找到让黑市客户摆脱控制的原始账本",
            project: project
        )

        for character in [protagonist, sister, director, witness] {
            modelContext.insert(character)
            project.characters.append(character)
        }

        project.characterRelationships = [
            CharacterRelationship(
                fromCharacterID: protagonist.id,
                toCharacterID: sister.id,
                kind: .family,
                detail: "彼此保护，却对是否保留痛苦持相反立场",
                tension: 92,
                isSecret: false
            ),
            CharacterRelationship(
                fromCharacterID: director.id,
                toCharacterID: protagonist.id,
                kind: .control,
                detail: "导师式信任正逐渐变成制度威胁",
                tension: 81,
                isSecret: false
            ),
            CharacterRelationship(
                fromCharacterID: witness.id,
                toCharacterID: sister.id,
                kind: .secret,
                detail: "两人曾共同隐藏事故记忆的最后十秒",
                tension: 74,
                isSecret: true
            )
        ]

        let template = project.structureTemplate
        let resolvedIdeas = [
            (
                "越擅长保存别人，越不敢保存自己",
                "林默会为每份档案建立精确备份，却从不允许系统显示自己的名字。",
                "他把职业能力变成了逃避自我的工具。"
            ),
            (
                "销毁倒计时提前",
                "系统通知未来记忆将在四十八小时后自动销毁，而且授权人正是林默本人。",
                "拖延不再是中立选择。"
            ),
            (
                "相信遗忘是一种公共善",
                "周启明不是掩盖罪行的恶人，他相信大规模记忆公开会再次伤害幸存者。",
                "对手的价值观足以动摇林默。"
            ),
            (
                "妹妹既是需要保护的人，也是唯一证人",
                "林岚要求哥哥停止调查，却在离开时下意识说出记忆里才有的细节。",
                "最亲密的关系同时承担背叛风险。"
            )
        ]

        for (index, seed) in resolvedIdeas.enumerated() {
            let option = StoryChoiceOption(
                title: seed.0,
                pitch: seed.1,
                concreteDetail: seed.1,
                consequence: seed.2,
                futurePressure: "这项选择会在后续大节拍继续提高关系代价。",
                sampleMoment: "安静的档案室里，一个程序动作暴露了人物真正害怕的东西。"
            )
            let decision = StoryDecision(
                stageName: template.stages[index].name,
                stageIndex: index,
                question: template.stages[index].choiceFocus,
                coachNote: template.stages[index].purpose,
                options: [option],
                selectedOptionID: option.id,
                selectedAnswerText: "\(option.title)：\(option.pitch)",
                resolvedAt: .now,
                project: project
            )
            decision.optionsGeneratedAt = .now
            modelContext.insert(decision)
            project.decisions.append(decision)
        }

        let activeIndex = resolvedIdeas.count
        let activeOptions = [
            StoryChoiceOption(
                title: "停电后的双人见证",
                pitch: "备用电源只够维持销毁程序，林默必须请妹妹成为第二见证人。",
                concreteDetail: "见证人的指纹会永久写入公共日志。",
                consequence: "妹妹无法再假装自己与旧案无关。",
                futurePressure: "兄妹必须在同一份记录上留下相反意见。",
                sampleMoment: "应急灯下，两只手同时悬在确认键上。"
            ),
            StoryChoiceOption(
                title: "排队者占领大厅",
                pitch: "系统故障让等待取回记忆的人群失控，林默必须公开决定谁先获得服务。",
                concreteDetail: "每延迟十分钟，就有一份记忆超过可逆期限。",
                consequence: "他第一次亲自决定谁有资格记住。",
                futurePressure: "被放弃的家庭开始追查他的私人记录。",
                sampleMoment: "大厅里的号码牌同时熄灭，只剩人们喊出的名字。"
            ),
            StoryChoiceOption(
                title: "手工复核暴露漏洞",
                pitch: "停电迫使所有人使用纸质复核表，一处长期被软件掩盖的签名矛盾浮现。",
                concreteDetail: "异常签名来自周启明二十年前的旧工号。",
                consequence: "林默必须决定是否当场质疑自己的导师。",
                futurePressure: "周启明开始以保护机构为名收回林默的权限。",
                sampleMoment: "复写纸下显出一个早已停用的工号。"
            ),
            StoryChoiceOption(
                title: "黑市提供违规电源",
                pitch: "阿真带着只能支持一台设备的黑市电源出现，逼林默选择恢复哪份记忆。",
                concreteDetail: "电源一旦接入就会在监管系统留下不可删除的物理痕迹。",
                consequence: "林默必须主动越过职业红线。",
                futurePressure: "阿真要求他用同一权限交换一份被封存的账本。",
                sampleMoment: "三台设备同时倒数，电缆却只有一根。"
            )
        ]
        let activeDecision = StoryDecision(
            stageName: template.stages[activeIndex].name,
            stageIndex: activeIndex,
            question: "哪一条世界规则最能持续向人物施压？",
            coachNote: "选择会制造具体行动与关系代价的环境，不要只增加背景设定。",
            options: activeOptions,
            researchQuery: "记忆公共服务 程序 销毁见证",
            project: project
        )
        activeDecision.optionsGeneratedAt = .now.addingTimeInterval(-60)
        modelContext.insert(activeDecision)
        project.decisions.append(activeDecision)

        _ = project.addCreativeIdea(
            text: "不要增加更大的阴谋，压力来自每个人都在合理地保护某种东西。",
            scope: .project,
            stageIndex: nil
        )
        _ = project.addCreativeIdea(
            text: "让本阶段的新规则迫使林默必须请妹妹替他做见证。",
            scope: .stage,
            stageIndex: activeIndex
        )
        project.touch()
        modelContext.insert(project)
        do {
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
        } catch {
            assertionFailure("Unable to create debug preview data: \(error)")
        }
    }
}

extension View {
    func debugPreviewDataIfRequested() -> some View {
        modifier(DebugPreviewDataModifier())
    }
}
#else
import SwiftUI

extension View {
    func debugPreviewDataIfRequested() -> some View { self }
}
#endif
