import SwiftData
import SwiftUI

struct SceneBeatWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AISettingsStore.self) private var aiSettings

    @Bindable var project: StoryProject
    @Bindable var contract: SceneContract
    let onApplyToScreenplay: () -> Void

    @State private var selectedBeatID: UUID?
    @State private var previewOptionID: UUID?
    @State private var isGenerating = false
    @State private var generationProgress = 0.0
    @State private var generationMessage = ""
    @State private var generationProgressTask: Task<Void, Never>?
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var showingReapplyConfirmation = false

    private var beats: [SceneMicroBeat] {
        contract.microBeats.sorted()
    }

    private var selectedBeat: SceneMicroBeat? {
        guard let selectedBeatID else { return beats.first }
        return beats.first { $0.id == selectedBeatID } ?? beats.first
    }

    private var previewOption: SceneBeatChoiceOption? {
        guard let selectedBeat else { return nil }
        return selectedBeat.options.first { $0.id == previewOptionID }
            ?? selectedBeat.selectedOption
            ?? selectedBeat.options.first
    }

    private var confirmedCount: Int {
        beats.count { $0.selectedOption != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.42)

            if beats.isEmpty {
                emptyPlan
            } else {
                HSplitView {
                    beatList
                        .frame(minWidth: 230, idealWidth: 270, maxWidth: 310)
                    beatChoiceWorkspace
                        .frame(minWidth: 650)
                }
            }
        }
        .background(StudioCanvas())
        .task {
            selectFirstIfNeeded()
        }
        .onDisappear {
            generationProgressTask?.cancel()
        }
        .onChange(of: selectedBeatID) {
            syncPreview()
        }
        .alert("场景内情境更新", isPresented: $showingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .confirmationDialog(
            "重新串联这一场？",
            isPresented: $showingReapplyConfirmation,
            titleVisibility: .visible
        ) {
            Button("覆盖本场剧本文本", role: .destructive) {
                onApplyToScreenplay()
            }
            .keyboardShortcut(.defaultAction)
            Button("取消", role: .cancel) {}
                .keyboardShortcut(.cancelAction)
        } message: {
            Text("这会用已确认的情境更新方案重新生成整场正文；当前剧本会先保存为可恢复版本。")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "list.number")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(StudioTheme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("场景内情境更新 · 第 4 层")
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                Text("场 \(contract.sceneIndex) · \(contract.heading) · \(confirmedCount)/\(beats.count) 次计划更新已确认")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if contract.areMicroBeatsConfirmed {
                Button("重新串联本场", systemImage: "arrow.triangle.2.circlepath") {
                    showingReapplyConfirmation = true
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(.thinMaterial)
    }

    private var emptyPlan: some View {
        VStack(spacing: 20) {
            Image(systemName: "list.number")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(StudioTheme.accent)
            VStack(spacing: 7) {
                Text("把场景拆成必要的情境更新")
                    .font(.system(size: 27, weight: .semibold, design: .serif))
                Text("每一项只承担一次不可再分的状态转移，并提供四个可选行动方案。数量不固定；全部确认后按因果顺序串联成剧本文本。")
                    .font(.system(size: 15.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 760)
            }
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                sceneFact("目标", contract.characterGoal)
                sceneFact("阻碍", contract.obstacle)
                sceneFact("转折", contract.turn)
                sceneFact("结果", contract.outcome)
            }
            .padding(16)
            .frame(maxWidth: 720, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))

            Button {
                generatePlan()
            } label: {
                if isGenerating {
                    Label("正在推导必要情境更新…", systemImage: "sparkles")
                } else {
                    Label("生成情境更新与四选一方案", systemImage: "sparkles")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isGenerating || !aiSettings.hasAPIKey)

            if isGenerating {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: generationProgress)
                        .tint(StudioTheme.mint)
                    HStack {
                        Text(generationMessage)
                        Spacer()
                        Text("约 \(Int((generationProgress * 100).rounded()))%")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 620)
            } else if !aiSettings.hasAPIKey {
                Label("需要先在 AI 设置中保存 DeepSeek API Key", systemImage: "key.fill")
                    .font(.caption)
                    .foregroundStyle(StudioTheme.warm)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sceneFact(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(StudioTheme.accent)
                .frame(width: 42, alignment: .leading)
            Text(value)
                .font(.system(size: 15))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var beatList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("情境更新顺序")
                    .font(.system(size: 13.5, weight: .semibold))
                Spacer()
                Text("\(confirmedCount)/\(beats.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)

            Divider()

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(beats) { beat in
                        Button {
                            selectedBeatID = beat.id
                        } label: {
                            HStack(spacing: 10) {
                                Text(String(format: "%02d", beat.ordinal))
                                    .font(.caption.monospacedDigit().weight(.bold))
                                    .foregroundStyle(
                                        beat.selectedOption == nil
                                            ? StudioTheme.warm
                                            : StudioTheme.mint
                                    )
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("更新 \(beat.ordinal)")
                                        .font(.system(size: 13.5, weight: .semibold))
                                    Text(beat.purpose)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Image(
                                    systemName: beat.selectedOption == nil
                                        ? "4.circle"
                                        : "checkmark.circle.fill"
                                )
                                .foregroundStyle(
                                    beat.selectedOption == nil
                                        ? StudioTheme.accent
                                        : StudioTheme.mint
                                )
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .background(
                                selectedBeat?.id == beat.id
                                    ? Color.primary.opacity(0.09)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(7)
            }
        }
        .background(Color.primary.opacity(0.025))
    }

    @ViewBuilder
    private var beatChoiceWorkspace: some View {
        if let beat = selectedBeat {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        EyebrowLabel(text: "SCENE BEAT \(beat.ordinal)", color: StudioTheme.accent)
                        Text(beat.purpose)
                            .font(.system(size: 24, weight: .semibold, design: .serif))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("选择这次状态转移如何发生；四个行动方案都必须兑现同一 before → after 差异。")
                            .font(.system(size: 14.5))
                            .foregroundStyle(.secondary)
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 270), spacing: 11)],
                        spacing: 11
                    ) {
                        ForEach(beat.options) { option in
                            beatOptionCard(option, beat: beat)
                        }
                    }

                    if let previewOption {
                        beatOptionDetail(previewOption, beat: beat)
                    }
                }
                .padding(.horizontal, 21)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func beatOptionCard(
        _ option: SceneBeatChoiceOption,
        beat: SceneMicroBeat
    ) -> some View {
        let selected = previewOption?.id == option.id
        let applied = beat.selectedOptionID == option.id
        return Button {
            guard beat.selectedOption == nil else { return }
            previewOptionID = option.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(option.title)
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                    Spacer()
                    Image(
                        systemName: applied
                            ? "checkmark.seal.fill"
                            : (selected ? "checkmark.circle.fill" : "circle")
                    )
                    .foregroundStyle(applied || selected ? StudioTheme.mint : Color.secondary.opacity(0.35))
                }
                Text(option.dramaticAction)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("转折：\(option.turn)")
                    Text("结果：\(option.outcome)")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 135, alignment: .topLeading)
            .background(
                selected ? StudioTheme.mint.opacity(0.08) : Color.primary.opacity(0.028),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        selected ? StudioTheme.mint.opacity(0.5) : Color.primary.opacity(0.05),
                        lineWidth: selected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private func beatOptionDetail(
        _ option: SceneBeatChoiceOption,
        beat: SceneMicroBeat
    ) -> some View {
        StudioCard(padding: 17) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        EyebrowLabel(text: "SELECTED BEAT", color: StudioTheme.mint)
                        Text(option.title)
                            .font(.system(size: 22, weight: .semibold, design: .serif))
                    }
                    Spacer()
                    if beat.selectedOptionID == option.id {
                        Label("已确认", systemImage: "checkmark.seal.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(StudioTheme.mint)
                    } else {
                        Button("确认这次情境更新", systemImage: "checkmark.seal.fill") {
                            confirm(option, in: beat)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(StudioTheme.mint)
                    }
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 290), spacing: 10)],
                    spacing: 10
                ) {
                    detailFact("戏剧动作", option.dramaticAction, "bolt.fill")
                    detailFact("人物行动", option.characterAction, "figure.walk")
                    detailFact("对抗", option.opposition, "arrow.left.arrow.right")
                    detailFact("转折", option.turn, "arrow.triangle.turn.up.right.diamond.fill")
                    detailFact("结果", option.outcome, "flag.checkered")
                    ForEach(option.stateChanges ?? []) { mutation in
                        detailFact(
                            "\(mutation.dimension.rawValue) · \(mutation.subject)",
                            "\(mutation.beforeValue) → \(mutation.afterValue)",
                            mutation.dimension.symbol
                        )
                    }
                    if let audience = option.audienceUpdate, !audience.isEmpty {
                        detailFact("观众认知更新", audience, "eye.fill")
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Label("串联后进入剧本的文字", systemImage: "text.book.closed.fill")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(StudioTheme.accent)
                    Text(option.screenplayText)
                        .font(.system(size: 16, design: .serif))
                        .lineSpacing(5)
                        .textSelection(.enabled)
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func detailFact(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(StudioTheme.accent)
            Text(value)
                .font(.system(size: 14.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(Color.primary.opacity(0.028), in: RoundedRectangle(cornerRadius: 10))
    }

    private func generatePlan() {
        guard !isGenerating else { return }
        isGenerating = true
        beginGenerationProgress()
        Task {
            defer {
                generationProgressTask?.cancel()
                generationProgressTask = nil
                isGenerating = false
            }
            do {
                contract.microBeats = try await SceneBeatChoiceEngine.generatePlan(
                    for: contract,
                    project: project,
                    configuration: try aiSettings.configuration()
                )
                generationProgress = 0.88
                generationMessage = "方案已返回，正在保存…"
                project.touch()
                try ProjectPersistenceStore.savePendingChanges(in: modelContext)
                generationProgress = 1
                generationMessage = "情境更新计划已经建立"
                selectFirstIfNeeded()
                syncPreview()
            } catch {
                present(error)
            }
        }
    }

    private func beginGenerationProgress() {
        generationProgressTask?.cancel()
        generationProgress = 0.08
        generationMessage = "已提交场景事实，等待 DeepSeek…"
        let startedAt = Date.now
        generationProgressTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                let elapsed = Date.now.timeIntervalSince(startedAt)
                generationProgress = min(0.78, 0.08 + elapsed / 90 * 0.70)
                generationMessage = elapsed < 12
                    ? "DeepSeek 正在推导必要状态转移…"
                    : "DeepSeek 正在生成每次更新的四个行动方案…"
            }
        }
    }

    private func confirm(_ option: SceneBeatChoiceOption, in beat: SceneMicroBeat) {
        do {
            try SceneBeatMappingEngine.confirm(
                option,
                in: beat.id,
                contract: contract,
                project: project
            )
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            previewOptionID = option.id
            if let next = beats.first(where: { $0.selectedOption == nil }) {
                selectedBeatID = next.id
            } else if contract.areMicroBeatsConfirmed {
                onApplyToScreenplay()
            }
        } catch {
            present(error)
        }
    }

    private func selectFirstIfNeeded() {
        if selectedBeat == nil {
            selectedBeatID = beats.first?.id
        }
    }

    private func syncPreview() {
        previewOptionID = selectedBeat?.selectedOptionID
            ?? selectedBeat?.options.first?.id
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
    }
}
