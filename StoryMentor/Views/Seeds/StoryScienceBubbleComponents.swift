import SwiftUI

extension StorySciencePhase {
    var tint: Color {
        switch self {
        case .incubator: StudioTheme.mint
        case .laboratory: StudioTheme.accent
        case .compiler: StudioTheme.warm
        }
    }
}

extension StoryExperimentAxis {
    var tint: Color {
        switch self {
        case .character: StudioTheme.warm
        case .conflict: Color(red: 0.82, green: 0.35, blue: 0.42)
        case .world: StudioTheme.sky
        case .theme: Color(red: 0.55, green: 0.45, blue: 0.86)
        case .ending: StudioTheme.mint
        }
    }
}

struct StorySciencePhaseRail: View {
    let phase: StorySciencePhase
    let canEnterLaboratory: Bool
    let hasProductionProject: Bool
    let onSelect: (StorySciencePhase) -> Void

    var body: some View {
        HStack(spacing: 16) {
            Label("正念式 AI 剧本创作", systemImage: "eye.fill")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(StudioTheme.mint)

            Spacer(minLength: 20)

            ForEach(Array(StorySciencePhase.allCases.enumerated()), id: \.element.id) { index, item in
                Button {
                    onSelect(item)
                } label: {
                    Label("\(index + 1)  \(item.shortName)", systemImage: item.systemImage)
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .frame(minWidth: 120)
                        .background(
                            item == phase ? item.tint.opacity(0.16) : Color.primary.opacity(0.04),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .stroke(item == phase ? item.tint.opacity(0.52) : Color.clear)
                        }
                }
                .buttonStyle(.plain)
                .disabled(item == .laboratory && !canEnterLaboratory)
                .opacity(item == .laboratory && !canEnterLaboratory ? 0.42 : 1)
                .help(helpText(for: item))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .animatedStoryBubble(tint: phase.tint, cornerRadius: 26, isSelected: true)
    }

    private func helpText(for item: StorySciencePhase) -> String {
        switch item {
        case .incubator: "从任意创意碎片发现人物、需求与隐藏问题"
        case .laboratory: canEnterLaboratory ? "一次只改变一个条件，观察变化与不变项" : "先完成一次故事潜能分析"
        case .compiler: hasProductionProject ? "进入结构与 Final Draft 正文生产" : "查看或创建生产项目"
        }
    }
}

struct StoryScienceHeaderBubble: View {
    let phase: StorySciencePhase
    let round: Int
    let seedCount: Int

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: phase.systemImage)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(
                    LinearGradient(
                        colors: [phase.tint, phase.tint.opacity(0.62)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )
                .shadow(color: phase.tint.opacity(0.32), radius: 14, y: 7)

            VStack(alignment: .leading, spacing: 4) {
                EyebrowLabel(
                    text: phase == .incubator ? "STORY INCUBATOR" : "STORY LABORATORY",
                    color: phase.tint
                )
                Text(phase.rawValue)
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if round > 0 {
                Label("第 \(round) 轮", systemImage: "arrow.triangle.2.circlepath")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(phase.tint)
                    .contentTransition(.numericText())
            }
            Label("\(seedCount) 颗种子", systemImage: "leaf.circle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .animatedStoryBubble(tint: phase.tint, cornerRadius: 38)
    }

    private var subtitle: String {
        switch phase {
        case .incubator:
            "先写下自己的材料；AI 帮助你看见、比较和提出问题。"
        case .laboratory:
            "改变一个变量，观察人物、冲突与主题是否真的产生生命力。"
        case .compiler:
            "把作者确认的发现转为结构、场景与标准剧本。"
        }
    }
}

struct StoryDiscoveryBubbles: View {
    let discovery: String
    let hiddenQuestion: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            insightBubble(
                eyebrow: "发现",
                icon: "sparkles",
                text: discovery,
                tint: StudioTheme.mint
            )
            insightBubble(
                eyebrow: "隐藏问题",
                icon: "questionmark.bubble.fill",
                text: hiddenQuestion,
                tint: StudioTheme.warm
            )
        }
    }

    private func insightBubble(
        eyebrow: String,
        icon: String,
        text: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(eyebrow, systemImage: icon)
                .font(.callout.weight(.bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .animatedStoryBubble(tint: tint, cornerRadius: 42)
    }
}

struct StoryAtomConstellation: View {
    let atoms: [StoryAtom]

    private let columns = [
        GridItem(.adaptive(minimum: 220), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("故事原子", systemImage: "circle.hexagongrid.fill")
                .font(.title3.weight(.semibold))
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(atoms) { atom in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: atom.type.systemImage)
                            .foregroundStyle(tint(for: atom.type))
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(atom.type.rawValue)
                                .font(.callout.weight(.bold))
                                .foregroundStyle(tint(for: atom.type))
                            Text(atom.content)
                                .font(.body)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                    .background(
                        tint(for: atom.type).opacity(atom.importance > 0.85 ? 0.12 : 0.07),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(tint(for: atom.type).opacity(0.22))
                    }
                }
            }
        }
        .padding(20)
        .animatedStoryBubble(tint: StudioTheme.sky, cornerRadius: 38)
    }

    private func tint(for type: StoryAtomType) -> Color {
        switch type {
        case .character, .relationship: StudioTheme.warm
        case .emotion: Color.pink
        case .image, .worldRule: StudioTheme.sky
        case .event, .choice: StudioTheme.accent
        case .dialogue: Color.purple
        case .unknown: StudioTheme.mint
        }
    }
}

struct StoryPotentialBubble: View {
    let evaluation: StoryPotentialEvaluation

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("故事潜能观察", systemImage: "waveform.path.ecg.rectangle.fill")
                .font(.title3.weight(.semibold))

            HStack(alignment: .top, spacing: 16) {
                listColumn(
                    title: "当前优势",
                    icon: "checkmark.circle.fill",
                    items: evaluation.strengths,
                    tint: StudioTheme.mint
                )
                listColumn(
                    title: "当前缺口",
                    icon: "circle.dashed",
                    items: evaluation.gaps,
                    tint: StudioTheme.warm
                )
                VStack(alignment: .leading, spacing: 8) {
                    Label("下一步", systemImage: "arrow.right.circle.fill")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(StudioTheme.accent)
                    Text(evaluation.nextStep)
                        .font(.body.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(
                    StudioTheme.accent.opacity(0.075),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(StudioTheme.accent.opacity(0.22))
                }
            }
        }
        .padding(20)
        .animatedStoryBubble(tint: StudioTheme.accent, cornerRadius: 40)
    }

    private func listColumn(
        title: String,
        icon: String,
        items: [String],
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.callout.weight(.bold))
                .foregroundStyle(tint)
            ForEach(items.prefix(3), id: \.self) { item in
                Text("• \(item)")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            tint.opacity(0.075),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(0.22))
        }
    }
}

struct StoryExperimentBubble: View {
    let experiment: StoryExperiment
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(experiment.axis.rawValue, systemImage: experiment.axis.systemImage)
                        .font(.callout.weight(.bold))
                        .foregroundStyle(experiment.axis.tint)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "arrow.up.right")
                        .foregroundStyle(isSelected ? experiment.axis.tint : Color.secondary)
                }

                Text(experiment.title)
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(experiment.hypothesis)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(experiment.whyItMatters)
                    .font(.body)
                    .foregroundStyle(experiment.axis.tint)
                    .lineLimit(3)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            .animatedStoryBubble(
                tint: experiment.axis.tint,
                cornerRadius: 30,
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(experiment.axis.rawValue)，\(experiment.title)，\(experiment.hypothesis)")
    }
}

struct StoryExperimentControlBubble: View {
    let experiment: StoryExperiment
    @Binding var selections: [UUID: String]
    @Binding var choiceOrigin: StoryExperimentChoiceOrigin?
    @Binding var customValue: String
    @Binding var authorObservation: String
    let isRunning: Bool
    let onRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    EyebrowLabel(text: "单变量条件实验", color: experiment.axis.tint)
                    Text(experiment.title)
                        .font(.system(.title2, design: .serif, weight: .semibold))
                }
                Spacer()
                Text("一次只锁定一个条件，其余保持不变")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            ForEach(experiment.variables) { variable in
                StoryExperimentVariablePicker(
                    variable: variable,
                    tint: experiment.axis.tint,
                    selection: selections[variable.id],
                    choiceOrigin: choiceOrigin,
                    customValue: $customValue,
                    isRunning: isRunning
                ) { option, origin in
                    withAnimation(.snappy(duration: 0.22)) {
                        selections = [variable.id: option]
                        choiceOrigin = origin
                    }
                }
            }

            TextField(
                "实验前注意：你为什么想改变这个条件？（可选）",
                text: $authorObservation,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(2...4)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                StudioTheme.mint.opacity(0.075),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(StudioTheme.mint.opacity(0.22))
            }

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        ready ? "本轮选择会随对照保存" : "请选择或设计一个条件",
                        systemImage: ready ? "checkmark.circle.fill" : "circle.dashed"
                    )
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(ready ? StudioTheme.mint : Color.secondary)
                    if let selectedValue {
                        Text(selectedValue)
                            .font(.body)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if let selectedChoiceOrigin {
                    Label(selectedChoiceOrigin.rawValue, systemImage: selectedChoiceOrigin.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(experiment.axis.tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(experiment.axis.tint.opacity(0.1), in: Capsule())
                }
                Button {
                    onRun()
                } label: {
                    if isRunning {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("建立对照中")
                        }
                    } else {
                        Label("创建对照分支", systemImage: "arrow.triangle.branch")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(experiment.axis.tint)
                .keyboardShortcut(.defaultAction)
                .disabled(!ready || isRunning)
            }
        }
        .padding(22)
        .animatedStoryBubble(tint: experiment.axis.tint, cornerRadius: 42, isSelected: true)
    }

    private var ready: Bool {
        selections.count == 1 && selectedValue != nil && choiceOrigin != nil
    }

    private var selectedValue: String? {
        guard let value = selections.values.first?.storyScienceTrimmed,
              !value.isEmpty else { return nil }
        return value
    }

    private var selectedChoiceOrigin: StoryExperimentChoiceOrigin? {
        guard selectedValue != nil else { return nil }
        return choiceOrigin
    }
}

private struct StoryExperimentVariablePicker: View {
    let variable: StoryExperimentVariable
    let tint: Color
    let selection: String?
    let choiceOrigin: StoryExperimentChoiceOrigin?
    @Binding var customValue: String
    let isRunning: Bool
    let onSelect: (String, StoryExperimentChoiceOrigin) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(variable.name)
                    .font(.callout.weight(.bold))
                Text(variable.question)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("AI 提供的观察选项", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 130), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(variable.options, id: \.self) { option in
                        Button(option) {
                            customValue = ""
                            onSelect(option, .aiSuggestion)
                        }
                        .buttonStyle(.plain)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(selection == option ? Color.white : Color.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(
                            selection == option ? tint : Color.primary.opacity(0.045),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule().stroke(tint.opacity(0.26))
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("你的设计", systemImage: "pencil.and.outline")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(tint)
                    Text("不必受 AI 选项限制")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    TextField(
                        "写下你真正想测试的条件",
                        text: $customValue,
                        axis: .vertical
                    )
                        .textFieldStyle(.plain)
                        .lineLimit(1...3)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                        .onSubmit(commitCustomValue)
                    Button("采用我的设计", systemImage: "checkmark") {
                        commitCustomValue()
                    }
                    .buttonStyle(.bordered)
                    .disabled(customValue.storyScienceTrimmed.isEmpty || isRunning)
                }

                if isCustomSelection {
                    Label("已采用你的条件；系统会按作者自定记录", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.caption)
                        .foregroundStyle(StudioTheme.mint)
                }
            }
        }
        .padding(16)
        .background(
            tint.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(0.22))
        }
        .disabled(isRunning)
    }

    private var isCustomSelection: Bool {
        selection != nil && choiceOrigin == .authorDesigned
    }

    private func commitCustomValue() {
        let value = customValue.storyScienceTrimmed
        guard !value.isEmpty else { return }
        customValue = value
        onSelect(value, .authorDesigned)
    }
}

struct MindfulExperimentReviewBubble: View {
    let candidate: StoryExperimentCandidate
    @Binding var disposition: MindfulReviewDisposition
    @Binding var choiceReason: String
    @Binding var authorRevision: String
    @Binding var newDiscovery: String
    let isSaving: Bool
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            MindfulReviewHeader(
                title: candidate.decision.experimentTitle,
                condition: candidate.comparison.conditionChange
            )

            HStack(alignment: .top, spacing: 14) {
                StoryVersionSummaryCard(
                    title: "原版",
                    subtitle: "实验前的故事状态",
                    crystal: candidate.baseline.crystal,
                    tint: StudioTheme.sky
                )
                StoryVersionSummaryCard(
                    title: "对照分支",
                    subtitle: "只改变选中条件后的状态",
                    crystal: candidate.proposal.crystal,
                    tint: StudioTheme.accent
                )
            }

            MindfulComparisonGrid(comparison: candidate.comparison)
            MindfulQuestionList(questions: candidate.comparison.questions)

            VStack(alignment: .leading, spacing: 14) {
                Text("由作者拍板")
                    .font(.title3.weight(.semibold))
                Picker("处理方式", selection: $disposition) {
                    ForEach(MindfulReviewDisposition.allCases) { item in
                        Label(item.rawValue, systemImage: item.systemImage)
                            .tag(item)
                    }
                }
                .pickerStyle(.segmented)

                TextField(
                    "为什么这样选择？请记录判断依据",
                    text: $choiceReason,
                    axis: .vertical
                )
                .lineLimit(2...5)

                if disposition == .modified {
                    TextField(
                        "你的修改意见（会进入下一轮生成）",
                        text: $authorRevision,
                        axis: .vertical
                    )
                    .lineLimit(2...6)
                }

                TextField(
                    "本轮新发现：你注意到了什么以前没有看到的东西？",
                    text: $newDiscovery,
                    axis: .vertical
                )
                .lineLimit(2...5)

                HStack {
                    Label(
                        canCommit ? "理由与新发现已记录" : completionHint,
                        systemImage: canCommit ? "checkmark.circle.fill" : "circle.dashed"
                    )
                    .font(.callout)
                    .foregroundStyle(canCommit ? StudioTheme.mint : Color.secondary)
                    Spacer()
                    Button {
                        onCommit()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("确认并进入下一轮", systemImage: "arrow.right.circle.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StudioTheme.mint)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCommit || isSaving)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                StudioTheme.mint.opacity(0.075),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(StudioTheme.mint.opacity(0.24))
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animatedStoryBubble(tint: StudioTheme.accent, cornerRadius: 34, isSelected: true)
    }

    private var canCommit: Bool {
        !choiceReason.storyScienceTrimmed.isEmpty
            && !newDiscovery.storyScienceTrimmed.isEmpty
            && (disposition != .modified || !authorRevision.storyScienceTrimmed.isEmpty)
    }

    private var completionHint: String {
        if choiceReason.storyScienceTrimmed.isEmpty { return "请先写下选择理由" }
        if disposition == .modified && authorRevision.storyScienceTrimmed.isEmpty {
            return "请写下修改意见"
        }
        return "请写下本轮新发现"
    }
}

private struct MindfulReviewHeader: View {
    let title: String
    let condition: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "rectangle.split.2x1.fill")
                .font(.title2)
                .foregroundStyle(StudioTheme.accent)
            VStack(alignment: .leading, spacing: 4) {
                EyebrowLabel(text: "待审阅对照", color: StudioTheme.accent)
                Text(title)
                    .font(.system(.title2, design: .serif, weight: .semibold))
                Label(condition, systemImage: "slider.horizontal.3")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("不会自动覆盖原版")
                .font(.callout.weight(.semibold))
                .foregroundStyle(StudioTheme.warm)
        }
    }
}

private struct StoryVersionSummaryCard: View {
    let title: String
    let subtitle: String
    let crystal: StoryCrystal
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "doc.text")
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
            Divider()
            summaryRow("人物", crystal.characterInsight)
            summaryRow("冲突", crystal.conflict)
            summaryRow("主题", crystal.theme)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            tint.opacity(0.075),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(tint.opacity(0.24))
        }
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout.weight(.bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MindfulComparisonGrid: View {
    let comparison: StoryExperimentComparison

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("变化与不变项", systemImage: "arrow.left.arrow.right")
                .font(.title3.weight(.semibold))

            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    MindfulChangeCard(title: "结构 / 冲突", text: comparison.structureChange)
                    MindfulChangeCard(title: "人物", text: comparison.characterChange)
                }
                HStack(alignment: .top, spacing: 12) {
                    MindfulChangeCard(title: "台词", text: comparison.dialogueChange)
                    MindfulChangeCard(title: "情绪 / 节奏", text: comparison.emotionChange)
                }
                MindfulChangeCard(
                    title: "仍然可以保持",
                    text: comparison.invariants.formatted(),
                    tint: StudioTheme.mint
                )
            }
        }
    }
}

private struct MindfulChangeCard: View {
    let title: String
    let text: String
    var tint: Color = StudioTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.callout.weight(.bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(
            tint.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(0.22))
        }
    }
}

private struct MindfulQuestionList: View {
    let questions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI 只负责扩大观察", systemImage: "questionmark.bubble.fill")
                .font(.title3.weight(.semibold))
            ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.callout.monospacedDigit().weight(.bold))
                        .foregroundStyle(StudioTheme.warm)
                        .frame(width: 24, height: 24)
                        .background(StudioTheme.warm.opacity(0.14), in: Circle())
                    Text(question)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            StudioTheme.warm.opacity(0.075),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(StudioTheme.warm.opacity(0.24))
        }
    }
}

struct StoryMindfulPatternBubble: View {
    let decisions: [StoryExperimentDecision]

    private var recorded: [StoryExperimentDecision] {
        decisions
    }

    private var reviewed: [StoryExperimentDecision] {
        decisions.filter { $0.reviewDisposition != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("选择记录与创作偏向", systemImage: "chart.bar.xaxis")
                    .font(.title3.weight(.semibold))
                Spacer()
                Label("自动保存在当前种子", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(StudioTheme.mint)
            }

            if recorded.isEmpty {
                Text("完成一次对照并写下理由后，这里会保存你的具体选择、选择来源与判断理由，并逐渐显示创作偏向。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    EyebrowLabel(text: "当前偏向", color: StudioTheme.mint)
                    Text(preferenceSummary)
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(sampleNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StudioTheme.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180), spacing: 10)],
                    spacing: 10
                ) {
                    preferenceMetric(
                        "最常探索",
                        frequentAxis?.rawValue ?? "尚未形成",
                        detail: axisCounts.isEmpty ? "新记录开始统计" : "按实验类型统计",
                        tint: frequentAxis?.tint ?? StudioTheme.accent
                    )
                    preferenceMetric(
                        "作者自定",
                        sourceMetricValue,
                        detail: sourceMetricDetail,
                        tint: StudioTheme.warm
                    )
                    preferenceMetric(
                        "常用判断",
                        frequentDisposition?.rawValue ?? "尚未形成",
                        detail: dispositionDetail,
                        tint: StudioTheme.sky
                    )
                }

                if !axisCounts.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("实验类型分布")
                            .font(.callout.weight(.semibold))
                        ForEach(axisCounts, id: \.axis) { item in
                            HStack(spacing: 10) {
                                Label(item.axis.rawValue, systemImage: item.axis.systemImage)
                                    .frame(width: 110, alignment: .leading)
                                ProgressView(
                                    value: Double(item.count),
                                    total: Double(axisRecordedCount)
                                )
                                .tint(item.axis.tint)
                                Text("\(item.count)")
                                    .font(.callout.monospacedDigit().weight(.semibold))
                                    .frame(width: 24, alignment: .trailing)
                            }
                        }
                    }
                    .font(.callout)
                    .padding(14)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
                }

                HStack {
                    Label("最近选择", systemImage: "clock.arrow.circlepath")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text(sourceCountSummary)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ForEach(recorded.suffix(3).reversed()) { decision in
                    MindfulDecisionHistoryRow(decision: decision)
                }

                if recorded.count > 3 {
                    DisclosureGroup("查看更早的 \(recorded.count - 3) 条选择记录") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(recorded.dropLast(3).reversed()) { decision in
                                MindfulDecisionHistoryRow(decision: decision)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .font(.callout.weight(.semibold))
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 34)
    }

    private func count(_ disposition: MindfulReviewDisposition) -> Int {
        reviewed.count { $0.reviewDisposition == disposition }
    }

    private var authorDesignedCount: Int {
        recorded.count { $0.choiceRecord?.source == .authorDesigned }
    }

    private var aiSuggestionCount: Int {
        recorded.count { $0.choiceRecord?.source == .aiSuggestion }
    }

    private var legacySourceCount: Int {
        recorded.count { $0.choiceRecord == nil }
    }

    private var knownSourceCount: Int {
        authorDesignedCount + aiSuggestionCount
    }

    private var authorDesignedPercent: Int {
        guard knownSourceCount > 0 else { return 0 }
        return Int((Double(authorDesignedCount) / Double(knownSourceCount) * 100).rounded())
    }

    private var axisCounts: [(axis: StoryExperimentAxis, count: Int)] {
        Dictionary(grouping: recorded.compactMap { $0.choiceRecord?.axis }, by: { $0 })
            .map { (axis: $0.key, count: $0.value.count) }
            .sorted {
                $0.count == $1.count
                    ? $0.axis.rawValue < $1.axis.rawValue
                    : $0.count > $1.count
            }
    }

    private var frequentAxis: StoryExperimentAxis? {
        axisCounts.first?.axis
    }

    private var frequentDisposition: MindfulReviewDisposition? {
        guard !reviewed.isEmpty else { return nil }
        return MindfulReviewDisposition.allCases.max { lhs, rhs in
            let lhsCount = count(lhs)
            let rhsCount = count(rhs)
            return lhsCount == rhsCount ? lhs.rawValue > rhs.rawValue : lhsCount < rhsCount
        }
    }

    private var dispositionDetail: String {
        guard let frequentDisposition else { return "新记录开始统计" }
        return "\(count(frequentDisposition)) / \(reviewed.count) 次复盘"
    }

    private var sampleNote: String {
        if reviewed.isEmpty {
            return "已保留当前种子的 \(recorded.count) 次历史选择；完成下一次带理由的复盘后，开始汇总判断偏向。"
        }
        let basis = "基于 \(recorded.count) 次选择中的 \(reviewed.count) 次已复盘实验"
        return reviewed.count < 3
            ? "\(basis)；样本尚少，偏向正在形成。"
            : "\(basis)汇总，不替你判断好坏。"
    }

    private var sourceMetricValue: String {
        guard knownSourceCount > 0 else { return "从新记录开始" }
        return "\(authorDesignedCount) 次 · \(authorDesignedPercent)%"
    }

    private var sourceMetricDetail: String {
        legacySourceCount > 0
            ? "另有 \(legacySourceCount) 条旧记录未标记来源"
            : "跳出 AI 候选，自行设计条件"
    }

    private var sourceCountSummary: String {
        var parts = ["AI 建议 \(aiSuggestionCount)", "作者自定 \(authorDesignedCount)"]
        if legacySourceCount > 0 {
            parts.append("历史未标记 \(legacySourceCount)")
        }
        return parts.joined(separator: " · ")
    }

    private var preferenceSummary: String {
        var parts: [String] = []
        if let frequentAxis {
            parts.append("你更常从「\(frequentAxis.rawValue)」观察故事")
        }
        if knownSourceCount == 0 {
            parts.append("旧选择已保留，来源会从新记录开始区分")
        } else if authorDesignedCount == 0 {
            parts.append("目前都从 AI 候选开始")
        } else if authorDesignedCount == knownSourceCount {
            parts.append("每次都采用了自己设计的条件")
        } else {
            parts.append("其中 \(authorDesignedCount) 次跳出 AI 候选，采用自己的设计")
        }
        if let frequentDisposition {
            parts.append("复盘时最常「\(frequentDisposition.rawValue)」")
        } else {
            parts.append("判断方式尚待下一次复盘记录")
        }
        return parts.joined(separator: "；") + "。"
    }

    private var axisRecordedCount: Int {
        max(axisCounts.reduce(0) { $0 + $1.count }, 1)
    }

    private func preferenceMetric(
        _ title: String,
        _ value: String,
        detail: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(2)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct MindfulDecisionHistoryRow: View {
    let decision: StoryExperimentDecision

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: decision.reviewDisposition?.systemImage ?? "circle")
                .foregroundStyle(StudioTheme.mint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(decision.experimentTitle)
                        .font(.callout.weight(.semibold))
                    Spacer()
                    if let record = decision.choiceRecord {
                        Label(record.source.rawValue, systemImage: record.source.systemImage)
                            .foregroundStyle(
                                record.source == .authorDesigned
                                    ? StudioTheme.warm
                                    : StudioTheme.accent
                            )
                    } else {
                        Label("历史未标记", systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption.weight(.semibold))

                HStack(spacing: 10) {
                    if let record = decision.choiceRecord {
                        Label(record.axis.rawValue, systemImage: record.axis.systemImage)
                    }
                    Text(recordedAt, format: .dateTime.year().month().day())
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let prompt = decision.choiceRecord?.prompt,
                   !prompt.storyScienceTrimmed.isEmpty {
                    Text(prompt)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }

                Label(
                    decision.selectedValues.map { "\($0.key)：\($0.value)" }.formatted(),
                    systemImage: "arrow.triangle.branch"
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let reason = decision.choiceReason, !reason.storyScienceTrimmed.isEmpty {
                    Text("理由：\(reason)")
                        .font(.callout)
                }
                if let discovery = decision.newDiscovery, !discovery.storyScienceTrimmed.isEmpty {
                    Text("新发现：\(discovery)")
                        .font(.callout)
                        .foregroundStyle(StudioTheme.mint)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var recordedAt: Date {
        decision.choiceRecord?.selectedAt
            ?? decision.reviewedAt
            ?? decision.createdAt
    }
}

struct StoryCrystalBubble: View {
    let crystal: StoryCrystal
    let decisions: [StoryExperimentDecision]
    let onCompile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("故事结晶", systemImage: "diamond.fill")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(StudioTheme.warm)
                Spacer()
                Text("\(decisions.count) 次实验")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            crystalRow("故事核心", crystal.coreIdea)
            crystalRow("人物洞察", crystal.characterInsight)
            crystalRow("不可两全", crystal.conflict)
            crystalRow("主题假设", crystal.theme)

            HStack(alignment: .center, spacing: 14) {
                Text(crystal.whyInteresting)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("进入剧本生产", systemImage: "arrow.right.circle.fill") {
                    onCompile()
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.warm)
                .disabled(!crystal.isReadyForProduction)
            }
        }
        .padding(24)
        .animatedStoryBubble(tint: StudioTheme.warm, cornerRadius: 54, isSelected: true)
    }

    private func crystalRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.callout.weight(.bold))
                .foregroundStyle(StudioTheme.warm)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct StoryScienceEmptyBubble: View {
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "flask.fill")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(StudioTheme.accent)
            Text(title)
                .font(.system(.title2, design: .serif, weight: .semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Button(buttonTitle, systemImage: "arrow.left") { action() }
                .buttonStyle(.borderedProminent)
        }
        .padding(38)
        .frame(maxWidth: 660)
        .animatedStoryBubble(tint: StudioTheme.accent, cornerRadius: 56)
        .frame(maxWidth: .infinity)
    }
}
