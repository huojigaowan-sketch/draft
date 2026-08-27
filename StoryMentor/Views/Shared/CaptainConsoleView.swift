import SwiftData
import SwiftUI

enum CaptainInputLayer: String {
    case overview = "项目全景"
    case journey = "大节拍选择"
    case scenes = "场景工作台"
    case screenplay = "小节拍与剧本"

    init?(section: WorkspaceSection) {
        switch section {
        case .overview, .ideas:
            self = .overview
        case .journey, .templates, .structure:
            self = .journey
        case .scenes:
            self = .scenes
        case .screenplay:
            self = .screenplay
        default:
            return nil
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .journey: "point.3.connected.trianglepath.dotted"
        case .scenes: "rectangle.stack.fill"
        case .screenplay: "text.book.closed.fill"
        }
    }

    var analysisContext: String {
        switch self {
        case .overview:
            "船长正在项目全景层思考，优先判断这条想法对全本宏观方向与各层的连锁影响。"
        case .journey:
            "船长正在大节拍选择层思考，优先理解它与已锁定结构、事件顺序和代价递进的关系，但不得擅自更换结构模板。"
        case .scenes:
            "船长正在场景工作台层思考，优先理解它对场景目标、阻力、转折、结果及上下场连续性的影响。"
        case .screenplay:
            "船长正在小节拍与剧本层思考，优先理解它对当前小节拍、动作、对白、节奏及其与前后小节拍连续性的影响。"
        }
    }
}

@MainActor
struct CaptainConsoleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AISettingsStore.self) private var aiSettings

    @Bindable var project: StoryProject
    let layer: CaptainInputLayer

    @State private var commandText = ""
    @State private var isGenerating = false
    @State private var reviewIdeaID: UUID?
    @State private var showingReview = false
    @State private var errorMessage = ""
    @State private var showingError = false
    @FocusState private var commandFocused: Bool

    private var reviewIdea: AuthorIdeaRecord? {
        guard let reviewIdeaID else { return nil }
        return project.authorIdeas.first { $0.id == reviewIdeaID }
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: isGenerating ? "waveform" : "command.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isGenerating ? StudioTheme.accent : StudioTheme.mint)
                    .symbolEffect(.variableColor.iterative, isActive: isGenerating)

                TextField(
                    "船长，在这一层写下任何新想法……",
                    text: $commandText,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 16, design: .rounded))
                .lineLimit(1...4)
                .focused($commandFocused)
                .disabled(isGenerating)
                .onChange(of: commandText) {
                    if commandText.count > 8_000 {
                        commandText = String(commandText.prefix(8_000))
                    }
                }

                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        submitCommand()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(
                        commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.secondary.opacity(0.35)
                            : StudioTheme.accent
                    )
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("结合当前层与全本生成四种方案（⌘↩）")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: commandFocused || isGenerating
                                ? [StudioTheme.mint, StudioTheme.accent, StudioTheme.warm]
                                : [Color.primary.opacity(0.08), Color.primary.opacity(0.04)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: commandFocused || isGenerating ? 1.6 : 1
                    )
            }

            HStack(spacing: 8) {
                Label("当前：\(layer.rawValue)", systemImage: layer.systemImage)
                    .foregroundStyle(StudioTheme.mint)
                Text("·")
                Text(
                    isGenerating
                        ? "正在结合当前层与全本生成 4 个方案…"
                        : "原话先保存；确认方案后并入整个剧本。"
                )
                Spacer()
                Text("\(commandText.count)/8000")
                    .monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .alert("船长控制台", isPresented: $showingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingReview) {
            if let reviewIdea {
                CaptainProposalSheet(
                    project: project,
                    idea: reviewIdea,
                    originLayer: layer,
                    onClose: { showingReview = false }
                )
            }
        }
    }

    private func submitCommand() {
        let clean = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        guard aiSettings.hasAPIKey else {
            present("请先在设置中保存 DeepSeek API Key。")
            return
        }

        let record = AuthorIdeaRecord(
            originalText: String(clean.prefix(8_000)),
            scope: .project,
            status: .analyzing
        )
        record.project = project
        modelContext.insert(record)

        do {
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            commandText = ""
            isGenerating = true
        } catch {
            modelContext.delete(record)
            present(error.localizedDescription)
            return
        }

        Task { @MainActor in
            do {
                let result = try await CaptainCommandEngine.generate(
                    command: record.originalText,
                    originContext: layer.analysisContext,
                    project: project,
                    configuration: try aiSettings.configuration()
                )
                record.captainInterpretation = result.interpretation
                record.captainOptions = result.options
                record.impactSummary = result.interpretation
                record.affectedAreas = Array(
                    Set(result.options.flatMap { $0.affectedChanges.map(\.area.rawValue) })
                )
                record.preservedElements = Array(
                    Set(result.options.flatMap(\.preservedFacts))
                )
                record.risks = Array(Set(result.options.flatMap(\.continuityRisks)))
                record.status = .proposed
                record.updatedAt = .now
                project.touch()
                try ProjectPersistenceStore.savePendingChanges(in: modelContext)
                reviewIdeaID = record.id
                showingReview = true
            } catch {
                record.status = .inbox
                record.updatedAt = .now
                commandText = record.originalText
                do {
                    try ProjectPersistenceStore.savePendingChanges(in: modelContext)
                } catch {
                    present(error.localizedDescription)
                    return
                }
                present(error.localizedDescription)
            }
            isGenerating = false
            commandFocused = true
        }
    }

    private func present(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

@MainActor
private struct CaptainProposalSheet: View {
    @Bindable var project: StoryProject
    @Bindable var idea: AuthorIdeaRecord
    let originLayer: CaptainInputLayer
    let onClose: () -> Void

    var body: some View {
        ZStack {
            StudioCanvas()

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.title2)
                        .foregroundStyle(StudioTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("四种执行方案")
                            .font(.system(.title2, design: .serif, weight: .semibold))
                        Text("来自\(originLayer.rawValue) · 确认后并入整个剧本")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("稍后确认") {
                        onClose()
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)

                Divider().opacity(0.42)

                ScrollView {
                    CaptainProposalBoard(project: project, idea: idea)
                        .padding(22)
                }
            }
        }
        .frame(minWidth: 820, minHeight: 660)
    }
}

@MainActor
struct CaptainProposalBoard: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var project: StoryProject
    @Bindable var idea: AuthorIdeaRecord

    @State private var selectedOptionID: UUID?
    @State private var errorMessage = ""
    @State private var showingError = false

    private var selectedOption: CaptainCommandOption? {
        let resolvedID = idea.selectedCaptainOptionID ?? selectedOptionID
        return idea.captainOptions.first { $0.id == resolvedID }
            ?? idea.captainOptions.first
    }

    var body: some View {
        StudioCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.title2)
                        .foregroundStyle(StudioTheme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("本轮四种执行方案")
                                .font(.headline)
                            PhaseBadge(text: idea.status.rawValue)
                        }
                        Text(idea.originalText)
                            .font(.system(.title3, design: .serif, weight: .semibold))
                            .lineLimit(3)
                        if !idea.captainInterpretation.isEmpty {
                            Text(idea.captainInterpretation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 250), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(idea.captainOptions) { option in
                        proposalOptionCard(option)
                    }
                }

                if let selectedOption {
                    selectedOptionDetail(selectedOption)
                }
            }
        }
        .onAppear {
            selectedOptionID = idea.selectedCaptainOptionID
                ?? idea.captainOptions.first?.id
        }
        .onChange(of: idea.id) {
            selectedOptionID = idea.selectedCaptainOptionID
                ?? idea.captainOptions.first?.id
        }
        .alert("船长控制台", isPresented: $showingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func proposalOptionCard(_ option: CaptainCommandOption) -> some View {
        let isSelected = selectedOption?.id == option.id
        let isApplied = idea.selectedCaptainOptionID == option.id

        return Button {
            guard idea.selectedCaptainOptionID == nil else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedOptionID = option.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(option.title)
                        .font(.system(.headline, design: .serif))
                    Spacer()
                    Image(
                        systemName: isApplied
                            ? "checkmark.seal.fill"
                            : (isSelected ? "checkmark.circle.fill" : "circle")
                    )
                    .foregroundStyle(isApplied || isSelected ? StudioTheme.mint : Color.secondary.opacity(0.35))
                }

                Text(option.strategy)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 5) {
                    ForEach(option.affectedChanges.prefix(5)) { change in
                        Image(systemName: change.area.systemImage)
                            .font(.caption2)
                            .foregroundStyle(StudioTheme.accent)
                            .help(change.area.rawValue)
                    }
                    if option.affectedChanges.count > 5 {
                        Text("+\(option.affectedChanges.count - 5)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .background(
                isSelected ? StudioTheme.mint.opacity(0.085) : Color.primary.opacity(0.025),
                in: RoundedRectangle(cornerRadius: 13)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(
                        isSelected ? StudioTheme.mint.opacity(0.48) : Color.primary.opacity(0.05),
                        lineWidth: isSelected ? 1.4 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private func selectedOptionDetail(_ option: CaptainCommandOption) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    EyebrowLabel(text: "EXECUTION MAP", color: StudioTheme.mint)
                    Text(option.title)
                        .font(.system(.title2, design: .serif, weight: .semibold))
                }
                Spacer()
                if idea.selectedCaptainOptionID == option.id {
                    Label("已确认并写入项目", systemImage: "checkmark.seal.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(StudioTheme.mint)
                } else {
                    Button("确认并执行这个方案", systemImage: "checkmark.seal.fill") {
                        apply(option)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(StudioTheme.mint)
                    .keyboardShortcut(.defaultAction)
                }
            }

            Label(option.protectedCore, systemImage: "lock.shield.fill")
                .font(.callout)
                .foregroundStyle(StudioTheme.warm)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StudioTheme.warm.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260), spacing: 10)],
                spacing: 10
            ) {
                ForEach(option.affectedChanges) { change in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(change.area.rawValue, systemImage: change.area.systemImage)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(StudioTheme.accent)
                        Text(change.target)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(change.update)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        if !change.consequence.isEmpty {
                            Label(change.consequence, systemImage: "arrow.triangle.branch")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 11))
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    checklist("保持不动", option.preservedFacts, "lock.fill", StudioTheme.mint)
                    checklist("后续检查", option.continuityRisks, "exclamationmark.triangle.fill", StudioTheme.warm)
                }
                VStack(alignment: .leading, spacing: 12) {
                    checklist("保持不动", option.preservedFacts, "lock.fill", StudioTheme.mint)
                    checklist("后续检查", option.continuityRisks, "exclamationmark.triangle.fill", StudioTheme.warm)
                }
            }
        }
    }

    private func checklist(
        _ title: String,
        _ items: [String],
        _ icon: String,
        _ tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            if items.isEmpty {
                Text("无额外项目")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(items.prefix(6).enumerated()), id: \.offset) { _, item in
                    Text("• \(item)")
                        .font(.caption2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(tint.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private func apply(_ option: CaptainCommandOption) {
        do {
            try CaptainCommandApplier.apply(
                option,
                from: idea,
                to: project,
                in: modelContext
            )
            selectedOptionID = option.id
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
