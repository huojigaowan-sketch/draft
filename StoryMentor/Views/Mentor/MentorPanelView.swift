import SwiftUI

private struct LocalMentorPanelPrototype: View {
    let project: StoryProject
    let section: WorkspaceSection

    private var activeCharacter: StoryCharacter? {
        project.characters.max { $0.updatedAt < $1.updatedAt }
    }

    private var localStrengths: [String] {
        guard let character = activeCharacter else { return [] }
        var items: [String] = []
        if !character.seedText.trimmed.isEmpty { items.append("已经有自由人物素材") }
        if !character.externalGoal.trimmed.isEmpty { items.append("外部目标可被识别") }
        if !character.internalNeed.trimmed.isEmpty { items.append("内在需求已经出现") }
        if !character.falseBelief.trimmed.isEmpty { items.append("存在可被挑战的信念") }
        return items
    }

    private var localGaps: [String] {
        guard let character = activeCharacter else {
            return ["尚未创建人物"]
        }

        var items: [String] = []
        if character.seedText.trimmed.isEmpty { items.append("写下一段自由人物描述") }
        if character.externalGoal.trimmed.isEmpty { items.append("缺少可见的外部目标") }
        if character.internalNeed.trimmed.isEmpty { items.append("缺少与目标错位的内在需求") }
        if character.fear.trimmed.isEmpty { items.append("核心恐惧还没有具体化") }
        if character.falseBelief.trimmed.isEmpty { items.append("尚未定义错误信念") }
        if character.arc.trimmed.isEmpty { items.append("人物变化空间仍为空白") }
        return items
    }

    private var nextAssignment: (title: String, prompt: String) {
        guard let character = activeCharacter else {
            return ("创建主人公", "写 100 字：这个人最想隐藏的矛盾是什么？")
        }
        if character.seedText.trimmed.isEmpty {
            return ("先不要填表", "用 100 到 300 字自由描述 \(character.name)，只写你真正好奇的部分。")
        }
        if character.externalGoal.trimmed.isEmpty {
            return ("让欲望可见", "写一个具体结果：观众只看画面，也能判断 \(character.name) 是否得到它。")
        }
        if character.falseBelief.trimmed.isEmpty {
            return ("设计错误信念", "补完这句话：\(character.name) 一直相信“____”，所以总会选择“____”。")
        }
        if character.internalNeed.trimmed.isEmpty {
            return ("制造目标错位", "写出他真正需要的东西，并让它与外部目标发生冲突。")
        }
        return ("准备进入对抗", "下一阶段将根据这个人物建议反派功能，而不是随机生成一个坏人。")
    }

    var body: some View {
        ZStack {
            StudioCanvas()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    panelHeader
                    readinessCard

                    if section == .characters || section == .overview {
                        localDiagnosis
                        assignmentCard
                    } else {
                        modulePreview
                    }

                    knowledgeStatus
                }
                .padding(18)
            }
        }
        .navigationSplitViewColumnWidth(min: 290, ideal: 330, max: 390)
    }

    private var panelHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(StudioTheme.accent)
                Text("导师台")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                Spacer()
                PhaseBadge(text: "LOCAL")
            }

            Text("当前只进行本地结构检查，不冒充 AI 判断。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var readinessCard: some View {
        StudioCard(padding: 16) {
            HStack(spacing: 16) {
                ProgressRing(value: project.completionFraction, lineWidth: 7, diameter: 62)

                VStack(alignment: .leading, spacing: 4) {
                    Text("项目准备度")
                        .font(.headline)
                    Text("根据已填写字段计算，不代表商业潜力评分。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var localDiagnosis: some View {
        StudioCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Label(
                    activeCharacter?.name ?? "人物检查",
                    systemImage: "stethoscope"
                )
                .font(.headline)

                if !localStrengths.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        EyebrowLabel(text: "已具备", color: StudioTheme.mint)
                        ForEach(localStrengths.prefix(3), id: \.self) {
                            LocalCheckRow(text: $0, state: .present)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    EyebrowLabel(text: "待探索", color: StudioTheme.warm)
                    ForEach(localGaps.prefix(4), id: \.self) {
                        LocalCheckRow(text: $0, state: .missing)
                    }

                    if localGaps.isEmpty {
                        LocalCheckRow(text: "基础维度已齐，可以进入 AI 深度诊断。", state: .present)
                    }
                }
            }
        }
    }

    private var assignmentCard: some View {
        StudioCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                EyebrowLabel(text: "下一道命题", color: StudioTheme.sky)
                Text(nextAssignment.title)
                    .font(.system(.title3, design: .serif, weight: .semibold))
                Text(nextAssignment.prompt)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("AI 诊断将在 Phase 2 接入", systemImage: "wand.and.stars") {}
                    .buttonStyle(.bordered)
                    .disabled(true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var modulePreview: some View {
        StudioCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Label(section.rawValue, systemImage: section.systemImage)
                    .font(.headline)
                Text("该模块会复用同一套诊断报告与创作任务协议，避免每个页面各自生成无关联的建议。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var knowledgeStatus: some View {
        StudioCard(padding: 16) {
            VStack(alignment: .leading, spacing: 11) {
                EyebrowLabel(text: "知识层")
                LocalCheckRow(text: "Story DNA：尚未接入", state: .neutral)
                LocalCheckRow(text: "编剧理论 RAG：尚未接入", state: .neutral)
                LocalCheckRow(text: "Foundation Models：尚未接入", state: .neutral)
                LocalCheckRow(text: "DeepSeek：尚未接入", state: .neutral)
            }
        }
    }
}

struct MentorEmptyView: View {
    var body: some View {
        ZStack {
            StudioCanvas()
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title)
                    .foregroundStyle(StudioTheme.accent)
                Text("导师台")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                Text("创建一个故事后，这里会显示诊断和下一道创作命题。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
        }
        .navigationSplitViewColumnWidth(min: 290, ideal: 330, max: 390)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
