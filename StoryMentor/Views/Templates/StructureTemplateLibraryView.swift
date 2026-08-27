import SwiftData
import SwiftUI

struct StructureTemplateLibraryView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var project: StoryProject
    let onNavigate: (WorkspaceSection) -> Void

    @State private var selectedTemplateID = "guided-core"
    @State private var selectedFamily = "全部"
    @State private var pendingTemplateID: String?
    @State private var showingResetConfirmation = false
    @State private var showingSaveError = false
    @State private var saveError = ""

    private let templateIDs = [
        "guided-core",
        "snowflake",
        "three-act",
        "hero-journey",
        "save-the-cat",
        "five-act",
        "eight-sequence",
        "truby-seven",
        "nutshell",
        "tandem-ensemble",
        "seven-point",
        "story-circle",
        "freytag",
        "truby-22",
        "kishotenketsu"
    ]

    private var templates: [StoryStructureTemplate] {
        templateIDs.map { StoryStructureCatalog.template(id: $0) }
    }

    private var families: [String] {
        ["全部"] + Array(Set(templates.map(\.family))).sorted()
    }

    private var filteredTemplates: [StoryStructureTemplate] {
        selectedFamily == "全部"
            ? templates
            : templates.filter { $0.family == selectedFamily }
    }

    private var selectedTemplate: StoryStructureTemplate {
        StoryStructureCatalog.template(id: selectedTemplateID)
    }

    var body: some View {
        ZStack {
            StudioCanvas()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if project.isStructureLocked {
                        lockedBanner
                        templateDetail(project.structureTemplate)
                    } else {
                        familyFilter
                        templateGrid
                        templateDetail(selectedTemplate)
                    }
                }
                .padding(26)
                .frame(maxWidth: 1_100)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationSplitViewColumnWidth(min: 650, ideal: 920)
        .onAppear {
            selectedTemplateID = project.hasSelectedStructureTemplate
                ? project.structureTemplateID
                : StoryStructureCatalog.defaultTemplate.id
        }
        .confirmationDialog(
            "更换并锁定结构？",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("更换并重新开始故事选择", role: .destructive) {
                if let pendingTemplateID {
                    applyTemplate(StoryStructureCatalog.template(id: pendingTemplateID))
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("取消", role: .cancel) {}
                .keyboardShortcut(.cancelAction)
        } message: {
            Text("旧的阶段选择会被重置。确认锁定后，这个项目将不能再更换结构。")
        }
        .alert("没有保存成功", isPresented: $showingSaveError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(saveError)
        }
    }

    private var header: some View {
        StudioCard(padding: 26) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    EyebrowLabel(text: "Structure Playbook", color: StudioTheme.mint)
                    Text(project.isStructureLocked ? "这就是全本故事的骨架" : "先选择，再永久锁定")
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                    Text(project.isStructureLocked
                         ? "后续人物、世界、场景与正式剧本都必须沿这套规则生长。结构快照已经写入项目，AI不能擅自改写。"
                         : "结构像体育规则，会决定节奏、压力与观看快感。请在比较完整路线后作出一次性决定；锁定后不可更换。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 720, alignment: .leading)
                }
                Spacer()
                Image(systemName: "figure.run.square.stack.fill")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [StudioTheme.mint, StudioTheme.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
    }

    private var lockedBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundStyle(StudioTheme.mint)
                .frame(width: 44, height: 44)
                .background(StudioTheme.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text("结构已永久锁定")
                    .font(.headline)
                Text("锁定时间：\(project.structureLockedAt?.formatted(date: .abbreviated, time: .shortened) ?? "旧项目已确认")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("进入剧本工作流", systemImage: "arrow.right") {
                onNavigate(.overview)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .background(StudioTheme.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(StudioTheme.mint.opacity(0.22))
        }
    }

    private var familyFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(families, id: \.self) { family in
                    Button {
                        selectedFamily = family
                    } label: {
                        Text(family)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(
                                selectedFamily == family
                                    ? StudioTheme.accent.opacity(0.14)
                                    : Color.primary.opacity(0.04),
                                in: Capsule()
                            )
                            .foregroundStyle(selectedFamily == family ? StudioTheme.accent : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var templateGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 225, maximum: 310), spacing: 14)
            ],
            spacing: 14
        ) {
            ForEach(filteredTemplates) { template in
                templateCard(template)
            }
        }
    }

    private func templateCard(_ template: StoryStructureTemplate) -> some View {
        let isSelected = selectedTemplateID == template.id
        let isActive = project.structureTemplateID == template.id
        let tint = color(for: template.id)

        return Button {
            if !project.isStructureLocked {
                selectedTemplateID = template.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: template.icon)
                        .font(.title2)
                        .foregroundStyle(tint)
                        .frame(width: 42, height: 42)
                        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 12))
                    Spacer()
                    if isActive {
                        PhaseBadge(text: project.isStructureLocked ? "已锁定" : "待确认")
                    } else {
                        Text("\(template.stages.count) 阶段")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(template.name)
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(template.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(template.experience)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                HStack {
                    Text(template.family)
                    Spacer()
                    Image(systemName: "arrow.down.right")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
            }
            .padding(17)
            .frame(maxWidth: .infinity, minHeight: 205, alignment: .topLeading)
            .background(
                isSelected ? tint.opacity(0.10) : Color.primary.opacity(0.025),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? tint.opacity(0.55) : Color.primary.opacity(0.06), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func templateDetail(_ template: StoryStructureTemplate) -> some View {
        let tint = color(for: template.id)

        return StudioCard(padding: 24) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 18) {
                    Image(systemName: template.icon)
                        .font(.system(size: 30))
                        .foregroundStyle(tint)
                        .frame(width: 58, height: 58)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(template.name)
                            .font(.system(.title, design: .serif, weight: .semibold))
                        Text(template.subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(
                        project.isStructureLocked
                            ? "进入剧本工作流"
                            : (project.structureTemplateID == template.id
                               ? "锁定这套结构"
                               : "采用并锁定")
                    ) {
                        requestTemplate(template)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                }

                HStack(alignment: .top, spacing: 14) {
                    insightCard("它会产生什么", template.experience, "waveform.path.ecg", tint)
                    insightCard("最适合", bestFor(template.id), "target", tint)
                    insightCard("套用风险", template.caution, "exclamationmark.triangle", StudioTheme.warm)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("创作路线", systemImage: "point.3.connected.trianglepath.dotted")
                            .font(.headline)
                        Spacer()
                        Text("\(template.stages.count) 个决定")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    ForEach(Array(template.stages.enumerated()), id: \.element.id) { index, stage in
                        HStack(alignment: .top, spacing: 12) {
                            Text(String(format: "%02d", index + 1))
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(tint)
                                .frame(width: 28, alignment: .leading)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(stage.name)
                                    .font(.callout.weight(.semibold))
                                Text(stage.purpose)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("本轮选择：\(stage.choiceFocus)")
                                    .font(.caption2)
                                    .foregroundStyle(tint)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 7) {
                    EyebrowLabel(text: "来自你的本地编剧书库")
                    Text(sourceNote(template.id))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func insightCard(
        _ title: String,
        _ text: String,
        _ icon: String,
        _ tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 13))
    }

    private func requestTemplate(_ template: StoryStructureTemplate) {
        if project.isStructureLocked {
            onNavigate(.overview)
        } else if project.structureTemplateID == template.id {
            lockCurrentTemplate()
        } else if !project.decisions.isEmpty {
            pendingTemplateID = template.id
            showingResetConfirmation = true
        } else {
            applyTemplate(template)
        }
    }

    private func applyTemplate(_ template: StoryStructureTemplate) {
        if project.structureTemplateID != template.id {
            let oldDecisions = project.decisions
            project.decisions.removeAll()
            oldDecisions.forEach { modelContext.delete($0) }
        }
        project.storyPathText = ""
        project.blueprintText = ""
        project.structureTemplateID = template.id
        project.structureTemplateName = template.name
        project.structureRulesText = ""
        project.structureRulesText = project.structureRulesForPrompt
        project.lockStructure()
        project.touch()

        do {
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            pendingTemplateID = nil
            onNavigate(.overview)
        } catch {
            saveError = error.localizedDescription
            showingSaveError = true
        }
    }

    private func lockCurrentTemplate() {
        project.structureRulesText = project.structureRulesForPrompt
        project.lockStructure()
        do {
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            onNavigate(.overview)
        } catch {
            saveError = error.localizedDescription
            showingSaveError = true
        }
    }

    private func color(for id: String) -> Color {
        switch id {
        case "three-act", "eight-sequence", "snowflake", "seven-point": StudioTheme.accent
        case "hero-journey", "five-act", "story-circle", "freytag": StudioTheme.warm
        case "save-the-cat", "nutshell": Color(red: 0.82, green: 0.30, blue: 0.22)
        case "truby-seven", "truby-22", "guided-core": StudioTheme.mint
        case "tandem-ensemble": Color(red: 0.18, green: 0.55, blue: 0.63)
        default: Color(red: 0.55, green: 0.45, blue: 0.28)
        }
    }

    private func bestFor(_ id: String) -> String {
        switch id {
        case "snowflake": "长篇、全本规划、复杂人物关系，以及有核心想法却不知道如何扩成完整故事的项目。"
        case "three-act": "目标明确、因果推进、希望观众获得稳定满足感的类型故事。"
        case "hero-journey": "成长、冒险、奇幻、身份转变，以及必须离开旧世界的人物。"
        case "save-the-cat": "高概念商业片、喜剧、短剧与需要密集节奏提示的创作。"
        case "five-act": "人物心理转化、悲剧、道德困境与旧信念被反复检验的故事。"
        case "eight-sequence": "悬疑、惊悚、犯罪、动作，以及容易在第二幕失速的长片。"
        case "truby-seven": "从人物欲望自然长出情节、反派与主题的有机型故事。"
        case "nutshell": "缺陷驱动的喜剧、爱情、成长故事与强人物弧线。"
        case "tandem-ensemble": "群像、多主角、多时间线，以及不同人物围绕同一主题碰撞。"
        case "seven-point": "知道高潮或结局，希望从结果反推中段压力与转折的类型故事。"
        case "story-circle": "人物成长、喜剧、动画、剧集单集与紧凑的变化弧线。"
        case "freytag": "舞台剧、悲剧、历史剧与围绕中心高潮组织的单一主冲突。"
        case "truby-22": "复杂长片、道德冲突、人物网和需要完整前期设计的项目。"
        case "kishotenketsu": "日常、诗意、寓言、低对抗叙事，以及依靠意外转义产生余味的作品。"
        default: "还只有碎片、人物或现实材料，希望通过连续选择发现故事的作者。"
        }
    }

    private func sourceNote(_ id: String) -> String {
        switch id {
        case "snowflake":
            "本地书库未收录雪花法专著。本模板采用Randy Ingermanson的标准逐层扩写流程，并以Gulino的梗概/节拍表/卡片方法、Truby的场景织网及Syd Field的treatment与outline理论校正。"
        case "three-act":
            "Syd Field《Screenplay》、Linda Aronson《The 21st Century Screenplay》：结构的作用是控制观众情绪与转折，而不只是按页码切幕。"
        case "hero-journey":
            "Linda Aronson 对召唤、拒绝、导师、门槛、试炼、洞穴、磨难、宝物、归返与复活的专业归纳。"
        case "save-the-cat":
            "Will Storr《The Science of Storytelling》与书库中的场景写作资料，对十五节拍、中点、至暗时刻、开场与终场意象的交叉讨论。"
        case "five-act":
            "Will Storr《The Science of Storytelling》：五幕持续测试、打破并重建人物的控制理论，最终迫使人物选择新旧自我。"
        case "eight-sequence":
            "Paul Joseph Gulino《Screenwriting: The Sequence Approach》：八个序列分别提出、推进并回答局部戏剧问题。"
        case "truby-seven":
            "John Truby《The Anatomy of Story》：弱点与需要、欲望、对手、计划、战斗、自我揭示、新平衡；是脚手架而非公式。"
        case "nutshell":
            "Jill Chamberlain《The Nutshell Technique》：设定欲望、不归点、困局、缺陷、危机、力量、高潮选择与最终一步。"
        case "tandem-ensemble":
            "Linda Aronson《The 21st Century Screenplay》：并行、多主角、断裂并行与连续故事，适合无法被单一英雄三幕容纳的材料。"
        case "seven-point":
            "结合七点结构、Syd Field情节点与Gulino序列法，以高潮答案反推两次转折、两次压力点和中点主动性。"
        case "story-circle":
            "Dan Harmon故事圆环以八个动作追踪人物离开舒适区、得到目标、付出代价并带着变化返回。"
        case "freytag":
            "Freytag戏剧结构强调激发行动、上升行动、中心高潮、下降后果与结局余波。"
        case "truby-22":
            "John Truby《The Anatomy of Story》完整二十二步：人物网、故事世界、欲望、对手、计划、揭示序列、战斗与道德决定。"
        case "kishotenketsu":
            "结合书库中关于非传统结构、转折与观众期待控制的理论，强调“转”对前文意义的重构，而非必须依靠正面冲突。"
        default:
            "综合书库中的人物、欲望、对抗、关系、世界压力、中点、危机、高潮与结尾意象理论，作为最自由的探索入口。"
        }
    }
}
