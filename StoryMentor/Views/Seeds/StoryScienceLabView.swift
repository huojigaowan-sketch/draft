import SwiftData
import SwiftUI

struct StoryScienceLabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AISettingsStore.self) private var settings
    @Query(sort: \StorySeed.updatedAt, order: .reverse)
    private var seeds: [StorySeed]

    let projectID: UUID
    let phase: StorySciencePhase
    @Binding var selectedSeedID: UUID?
    let onChangePhase: (StorySciencePhase) -> Void
    let onCompile: (StorySeed, StoryCrystal) -> Void

    @State private var seedTitle = ""
    @State private var rawIdea = ""
    @State private var authorIntent = ""
    @State private var selectedExperimentID: UUID?
    @State private var selectedVariableValues: [UUID: String] = [:]
    @State private var selectedChoiceOrigin: StoryExperimentChoiceOrigin?
    @State private var customVariableValue = ""
    @State private var authorObservation = ""
    @State private var reviewDisposition: MindfulReviewDisposition = .accepted
    @State private var choiceReason = ""
    @State private var authorRevision = ""
    @State private var newDiscovery = ""
    @State private var isRunning = false
    @State private var progress = 0.0
    @State private var progressMessage = ""
    @State private var errorMessage = ""
    @State private var showingError = false

    private var projectSeeds: [StorySeed] {
        seeds.filter { $0.belongs(to: projectID) }
    }

    private var selectedSeed: StorySeed? {
        guard let selectedSeedID else { return nil }
        return projectSeeds.first { $0.id == selectedSeedID }
    }

    private var snapshot: StoryCultivationSnapshot {
        selectedSeed?.cultivationSnapshot ?? .empty(rawIdea: rawIdea)
    }

    private var selectedExperiment: StoryExperiment? {
        guard let selectedExperimentID else { return snapshot.experiments.first }
        return snapshot.experiments.first { $0.id == selectedExperimentID }
    }

    private var pendingCandidate: StoryExperimentCandidate? {
        selectedSeed?.pendingExperimentCandidate
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StoryScienceHeaderBubble(
                    phase: phase,
                    round: snapshot.round,
                    seedCount: projectSeeds.count
                )

                if phase == .incubator {
                    incubatorContent
                } else if snapshot.hasAnalysis {
                    laboratoryContent
                } else {
                    StoryScienceEmptyBubble(
                        title: "实验需要一颗经过分析的种子",
                        message: "先回到培养舱，把一个人物、情绪、画面、事件、世界规则、经历、梦或一句对白放进去。",
                        buttonTitle: "返回培养舱",
                        action: { onChangePhase(.incubator) }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
        .controlSize(.large)
        .task {
            restoreInitialSeedIfNeeded()
        }
        .onChange(of: selectedSeedID) { _, _ in
            restoreSelectedSeed()
        }
        .onChange(of: projectID) { _, _ in
            restoreInitialSeedIfNeeded()
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .laboratory, selectedExperimentID == nil {
                selectedExperimentID = snapshot.experiments.first?.id
            }
        }
        .alert("正念故事实验室", isPresented: $showingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var incubatorContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            ideaInputBubble

            if isRunning {
                progressBubble
            }

            if snapshot.hasAnalysis {
                StoryDiscoveryBubbles(
                    discovery: snapshot.discovery,
                    hiddenQuestion: snapshot.hiddenQuestion
                )
                StoryAtomConstellation(atoms: snapshot.atoms)
                seedDimensionsBubble

                HStack {
                    Text(snapshot.provenanceNote)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("带着单变量问题进入实验室", systemImage: "flask.fill") {
                        selectedExperimentID = snapshot.experiments.first?.id
                        selectedVariableValues = [:]
                        selectedChoiceOrigin = nil
                        customVariableValue = ""
                        withAnimation(.spring(response: 0.48, dampingFraction: 0.84)) {
                            onChangePhase(.laboratory)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StudioTheme.accent)
                }
                .padding(16)
                .animatedStoryBubble(tint: StudioTheme.accent, cornerRadius: 30)
            } else {
                firstSeedPrompt
            }
        }
    }

    private var ideaInputBubble: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    EyebrowLabel(text: "任意创意输入", color: StudioTheme.mint)
                    Text("不必先知道它是什么故事")
                        .font(.title3.weight(.semibold))
                }
                Spacer()
                seedHistoryMenu
                Button("新种子", systemImage: "plus") {
                    newSeed()
                }
                .buttonStyle(.bordered)
            }

            TextField("种子名称（可选）", text: $seedTitle)
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 24)

            ZStack(alignment: .topLeading) {
                if rawIdea.storyScienceTrimmed.isEmpty {
                    Text("例如：一个女人每天给死去丈夫发短信。\n也可以是一种情绪、一个梦、一句对白、一个世界规则或一段真实经历。")
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $rawIdea)
                    .font(.system(.title3, design: .serif))
                    .scrollContentBackground(.hidden)
                    .frame(height: 190)
                    .padding(8)
            }
            .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 34, isSelected: true)

            HStack(spacing: 12) {
                TextField("我特别想探索……（可选）", text: $authorIntent)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .animatedStoryBubble(tint: StudioTheme.sky, cornerRadius: 24)

                Button {
                    runCultivation()
                } label: {
                    Label(
                        snapshot.hasAnalysis ? "重新观察潜能" : "发现故事生命力",
                        systemImage: "sparkles"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(StudioTheme.mint)
                .disabled(rawIdea.storyScienceTrimmed.isEmpty || isRunning)
                .keyboardShortcut(.defaultAction)
            }

            HStack(spacing: 14) {
                Label("AI：分析 · 追问 · 建模 · 验证", systemImage: "cpu")
                Label("作者：判断 · 选择 · 想象 · 创造", systemImage: "person.crop.circle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(22)
        .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 46)
    }

    private var seedHistoryMenu: some View {
        Menu {
            if projectSeeds.isEmpty {
                Text("当前项目还没有故事种子")
            } else {
                ForEach(projectSeeds.prefix(18)) { seed in
                    Button {
                        selectedSeedID = seed.id
                    } label: {
                        Label(
                            seed.title,
                            systemImage: seed.id == selectedSeedID
                                ? "checkmark.circle.fill"
                                : "leaf"
                        )
                    }
                }
            }
        } label: {
            Label("种子库", systemImage: "tray.full.fill")
        }
        .menuStyle(.borderlessButton)
    }

    private var progressBubble: some View {
        HStack(spacing: 14) {
            ProgressView(value: progress)
                .progressViewStyle(.circular)
            VStack(alignment: .leading, spacing: 4) {
                Text("正在培养故事种子")
                    .font(.callout.weight(.semibold))
                Text(progressMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .contentTransition(.interpolate)
            }
            Spacer()
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.callout.monospacedDigit().weight(.bold))
                .foregroundStyle(StudioTheme.mint)
                .contentTransition(.numericText())
        }
        .padding(17)
        .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 30, isSelected: true)
    }

    private var firstSeedPrompt: some View {
        HStack(spacing: 18) {
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(StudioTheme.mint)
            VStack(alignment: .leading, spacing: 5) {
                Text("先寻找生命力，不急着生成故事")
                    .font(.system(.title3, design: .serif, weight: .semibold))
                Text("系统会分离故事原子，寻找人物需求与价值冲突，然后只提出三个单变量实验。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(24)
        .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 42)
    }

    private var seedDimensionsBubble: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("当前故事种子", systemImage: "point.3.filled.connected.trianglepath.dotted")
                .font(.title3.weight(.semibold))

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260), spacing: 14)],
                spacing: 12
            ) {
                dimensionBubble("人物", values: snapshot.characters, tint: StudioTheme.warm)
                dimensionBubble("人的需求", values: snapshot.humanNeeds.map(\.rawValue), tint: StudioTheme.mint)
                dimensionBubble("欲望", values: snapshot.desires, tint: StudioTheme.sky)
                dimensionBubble("恐惧", values: snapshot.fears, tint: Color.pink)
                dimensionBubble("人物矛盾", values: snapshot.contradictions, tint: Color.orange)
                dimensionBubble("价值冲突", values: snapshot.valueConflicts, tint: StudioTheme.accent)
                dimensionBubble("戏剧问题", values: snapshot.dramaticQuestions, tint: Color.purple)
                dimensionBubble("主题假设", values: snapshot.themes, tint: StudioTheme.warm)
            }
        }
        .padding(20)
        .animatedStoryBubble(tint: StudioTheme.mint, cornerRadius: 40)
    }

    private func dimensionBubble(
        _ title: String,
        values: [String],
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.callout.weight(.bold))
                .foregroundStyle(tint)
            if values.isEmpty {
                Text("尚待实验")
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(values.prefix(3), id: \.self) { value in
                    Text(value)
                        .lineLimit(2)
                }
            }
        }
        .font(.body)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(tint.opacity(0.22))
        }
    }

    private var laboratoryContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            StoryDiscoveryBubbles(
                discovery: snapshot.discovery,
                hiddenQuestion: snapshot.hiddenQuestion
            )
            StoryPotentialBubble(evaluation: snapshot.evaluation)
            StoryMindfulPatternBubble(decisions: snapshot.decisions)

            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        EyebrowLabel(text: "三个观察方向", color: StudioTheme.accent)
                        Text("选择或设计一个条件，建立可解释的对照")
                            .font(.system(.title2, design: .serif, weight: .semibold))
                    }
                    Spacer()
                    Text("AI 建议只是起点，本轮只改变一个条件")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 18, alignment: .top),
                        GridItem(.flexible(), spacing: 18, alignment: .top),
                        GridItem(.flexible(), alignment: .top)
                    ],
                    alignment: .leading,
                    spacing: 18
                ) {
                    ForEach(snapshot.experiments) { experiment in
                        StoryExperimentBubble(
                            experiment: experiment,
                            isSelected: selectedExperiment?.id == experiment.id
                        ) {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                                selectedExperimentID = experiment.id
                                selectedVariableValues = [:]
                                selectedChoiceOrigin = nil
                                customVariableValue = ""
                                authorObservation = ""
                            }
                        }
                        .disabled(isRunning || pendingCandidate != nil)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let pendingCandidate {
                MindfulExperimentReviewBubble(
                    candidate: pendingCandidate,
                    disposition: $reviewDisposition,
                    choiceReason: $choiceReason,
                    authorRevision: $authorRevision,
                    newDiscovery: $newDiscovery,
                    isSaving: isRunning,
                    onCommit: resolvePendingExperiment
                )
            } else if let selectedExperiment {
                StoryExperimentControlBubble(
                    experiment: selectedExperiment,
                    selections: $selectedVariableValues,
                    choiceOrigin: $selectedChoiceOrigin,
                    customValue: $customVariableValue,
                    authorObservation: $authorObservation,
                    isRunning: isRunning,
                    onRun: runExperiment
                )
            }

            if isRunning {
                progressBubble
            }

            StoryCrystalBubble(
                crystal: snapshot.crystal,
                decisions: snapshot.decisions
            ) {
                guard let selectedSeed else { return }
                onCompile(selectedSeed, snapshot.crystal)
            }
        }
    }

    private func restoreInitialSeedIfNeeded() {
        if selectedSeed == nil {
            selectedSeedID = projectSeeds.first(where: { $0.cultivationSnapshot.hasAnalysis })?.id
                ?? projectSeeds.first?.id
        }
        restoreSelectedSeed()
    }

    private func restoreSelectedSeed() {
        guard let selectedSeed else {
            newSeed()
            return
        }
        seedTitle = selectedSeed.title
        rawIdea = selectedSeed.sourceText
        authorIntent = selectedSeed.authorIntent
        selectedExperimentID = selectedSeed.cultivationSnapshot.experiments.first?.id
        selectedVariableValues = [:]
        selectedChoiceOrigin = nil
        customVariableValue = ""
        authorObservation = ""
        restoreReviewDraft(from: selectedSeed.pendingExperimentCandidate)
    }

    private func newSeed() {
        selectedSeedID = nil
        seedTitle = ""
        rawIdea = ""
        authorIntent = ""
        selectedExperimentID = nil
        selectedVariableValues = [:]
        selectedChoiceOrigin = nil
        customVariableValue = ""
        authorObservation = ""
        restoreReviewDraft(from: nil)
        progressMessage = ""
    }

    private func restoreReviewDraft(from candidate: StoryExperimentCandidate?) {
        reviewDisposition = candidate?.decision.reviewDisposition ?? .accepted
        choiceReason = candidate?.decision.choiceReason ?? ""
        authorRevision = candidate?.decision.authorRevision ?? ""
        newDiscovery = candidate?.decision.newDiscovery ?? ""
    }

    private func saveSeedDraft() throws -> StorySeed {
        let seed: StorySeed
        if let selectedSeed {
            seed = selectedSeed
        } else {
            seed = StorySeed(sourceType: .freeIdea, projectID: projectID)
            modelContext.insert(seed)
            selectedSeedID = seed.id
        }
        let cleanTitle = seedTitle.storyScienceTrimmed
        seed.title = cleanTitle.isEmpty
            ? String(rawIdea.storyScienceTrimmed.prefix(24))
            : cleanTitle
        seed.sourceType = .freeIdea
        seed.sourceText = rawIdea.storyScienceTrimmed
        seed.authorIntent = authorIntent.storyScienceTrimmed
        seed.updatedAt = .now
        try ProjectPersistenceStore.save(
            seed: seed,
            under: projectID,
            in: modelContext
        )
        return seed
    }

    private func runCultivation() {
        Task {
            isRunning = true
            progress = 0
            progressMessage = "准备培养舱"
            defer { isRunning = false }

            do {
                let seed = try saveSeedDraft()
                let previous = seed.cultivationSnapshot.hasAnalysis
                    ? seed.cultivationSnapshot
                    : nil
                let outcome = try await StoryCultivationEngine(settings: settings).cultivate(
                    rawIdea: seed.sourceText,
                    authorIntent: seed.authorIntent,
                    previous: previous
                ) { value, message in
                    withAnimation(.easeInOut(duration: 0.22)) {
                        progress = value
                        progressMessage = message
                    }
                }
                seed.cultivationSnapshot = outcome.snapshot
                seed.pendingExperimentCandidate = nil
                seed.promptTokens = outcome.usage.promptTokens
                seed.completionTokens = outcome.usage.completionTokens
                seed.dramaticCore = outcome.snapshot.crystal.conflict
                seed.questionsText = outcome.snapshot.dramaticQuestions.joined(separator: "\n")
                try ProjectPersistenceStore.save(
                    seed: seed,
                    under: projectID,
                    in: modelContext
                )
                selectedExperimentID = outcome.snapshot.experiments.first?.id
                selectedVariableValues = [:]
                selectedChoiceOrigin = nil
                customVariableValue = ""
            } catch {
                present(error)
            }
        }
    }

    private func runExperiment() {
        guard let selectedSeed,
              let selectedExperiment,
              let selectedChoiceOrigin,
              selectedVariableValues.count == 1,
              let selection = selectedVariableValues.first,
              let variable = selectedExperiment.variables.first(where: { $0.id == selection.key })
        else { return }

        let finalValue = selection.value.storyScienceTrimmed
        guard !finalValue.isEmpty else { return }
        let selectedOptionIndex = selectedChoiceOrigin == .aiSuggestion
            ? variable.options.firstIndex(of: finalValue)
            : nil
        guard selectedChoiceOrigin != .aiSuggestion || selectedOptionIndex != nil else { return }

        let previous = selectedSeed.cultivationSnapshot
        let selectedAt = Date.now
        let choiceRecord = StoryExperimentChoiceRecord(
            round: max(previous.round, 1),
            axis: selectedExperiment.axis,
            variableID: variable.id,
            variableName: variable.name,
            prompt: variable.question,
            aiCandidates: variable.options,
            finalValue: finalValue,
            source: selectedChoiceOrigin,
            selectedCandidateIndex: selectedOptionIndex,
            selectedAt: selectedAt
        )
        let decision = StoryExperimentDecision(
            experimentID: selectedExperiment.id,
            experimentTitle: selectedExperiment.title,
            selectedValues: [variable.name: finalValue],
            authorObservation: authorObservation.storyScienceTrimmed,
            selectedVariableName: variable.name,
            selectedOptionIndex: selectedOptionIndex,
            choiceRecord: choiceRecord,
            createdAt: selectedAt
        )

        Task {
            isRunning = true
            progress = 0
            progressMessage = "锁定唯一变量，固定其余条件"
            defer { isRunning = false }

            do {
                let outcome = try await StoryCultivationEngine(settings: settings).cultivate(
                    rawIdea: selectedSeed.sourceText,
                    authorIntent: selectedSeed.authorIntent,
                    previous: previous,
                    decision: decision
                ) { value, message in
                    withAnimation(.easeInOut(duration: 0.22)) {
                        progress = value
                        progressMessage = message
                    }
                }
                let comparison = outcome.comparison
                    ?? StoryExperimentComparison.comparing(
                        baseline: previous,
                        variant: outcome.snapshot,
                        decision: decision
                    )
                selectedSeed.pendingExperimentCandidate = StoryExperimentCandidate(
                    decision: decision,
                    baseline: previous,
                    proposal: outcome.snapshot,
                    comparison: comparison
                )
                selectedSeed.promptTokens = outcome.usage.promptTokens
                selectedSeed.completionTokens = outcome.usage.completionTokens
                try ProjectPersistenceStore.save(
                    seed: selectedSeed,
                    under: projectID,
                    in: modelContext
                )

                withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
                    restoreReviewDraft(from: selectedSeed.pendingExperimentCandidate)
                }
            } catch {
                present(error)
            }
        }
    }

    private func resolvePendingExperiment() {
        guard let selectedSeed,
              let candidate = selectedSeed.pendingExperimentCandidate else { return }

        let originalSnapshot = selectedSeed.cultivationSnapshot
        let resolved = candidate.resolvedSnapshot(
            disposition: reviewDisposition,
            choiceReason: choiceReason,
            authorRevision: authorRevision,
            newDiscovery: newDiscovery
        )

        isRunning = true
        progress = 0.96
        progressMessage = "保存作者判断与新发现"
        selectedSeed.cultivationSnapshot = resolved
        selectedSeed.pendingExperimentCandidate = nil
        selectedSeed.dramaticCore = resolved.crystal.conflict
        selectedSeed.questionsText = resolved.dramaticQuestions.joined(separator: "\n")

        do {
            try ProjectPersistenceStore.save(
                seed: selectedSeed,
                under: projectID,
                in: modelContext
            )
            withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
                selectedExperimentID = resolved.experiments.first?.id
                selectedVariableValues = [:]
                selectedChoiceOrigin = nil
                customVariableValue = ""
                authorObservation = ""
                restoreReviewDraft(from: nil)
            }
        } catch {
            selectedSeed.cultivationSnapshot = originalSnapshot
            selectedSeed.pendingExperimentCandidate = candidate
            present(error)
        }
        isRunning = false
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
    }
}
