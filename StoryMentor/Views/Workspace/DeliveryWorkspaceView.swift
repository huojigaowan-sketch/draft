import SwiftData
import SwiftUI

struct DeliveryWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AISettingsStore.self) private var aiSettings
    @Bindable var project: StoryProject
    let onNavigate: (WorkspaceSection) -> Void
    @Query private var workspaceStates: [ScreenplayWorkspaceState]

    @State private var selectedKind: ScreenplayReviewKind = .structure
    @State private var isReviewing = false
    @State private var isExportingFinalDraft = false
    @State private var isExportingFountain = false
    @State private var errorMessage = ""
    @State private var showingError = false

    private var workspaceState: ScreenplayWorkspaceState? {
        workspaceStates
            .filter { $0.projectID == project.id }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private var selectedRound: ScreenplayReviewRound? {
        workspaceState?.latestReview(for: selectedKind)
    }

    private var isSelectedRoundCurrent: Bool {
        ScreenplayReviewEngine.isCurrent(selectedRound, project: project)
    }

    private var isReady: Bool {
        ScreenplayReviewEngine.isReady(state: workspaceState, project: project)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                roundList
                    .frame(minWidth: 230, idealWidth: 260, maxWidth: 300)
                roundDetail
                    .frame(minWidth: 480)
                readinessPanel
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 340)
            }
        }
        .background(StudioCanvas())
        .task {
            selectedKind = ScreenplayReviewEngine.nextRequiredKind(
                state: workspaceState,
                project: project
            )
        }
        .fileExporter(
            isPresented: $isExportingFinalDraft,
            document: FinalDraftDocument(
                xml: FinalDraftXMLExporter.xml(
                    title: project.title,
                    screenplayText: project.screenplayText
                )
            ),
            contentType: .finalDraftDocument,
            defaultFilename: "\(project.title).fdx"
        ) { result in
            switch result {
            case .success:
                recordDeliveryVersion(format: "Final Draft FDX")
            case .failure(let error):
                present(error)
            }
        }
        .fileExporter(
            isPresented: $isExportingFountain,
            document: FountainDocument(
                text: FountainParser.standardizingSceneFlow(
                    in: project.screenplayText
                )
            ),
            contentType: .fountainScript,
            defaultFilename: "\(project.title).fountain"
        ) { result in
            switch result {
            case .success:
                recordDeliveryVersion(format: "Fountain")
            case .failure(let error):
                present(error)
            }
        }
        .alert("检查与交付", isPresented: $showingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("检查与交付")
                    .font(.headline)
                Text(isReady ? "当前稿可以交付" : "按轮次锁定问题")
                    .font(.caption)
                    .foregroundStyle(isReady ? StudioTheme.mint : .secondary)
            }
            .frame(width: 160, alignment: .leading)

            Spacer(minLength: 8)
            ProductionWorkspaceSwitcher(selection: .delivery, onSelect: onNavigate)
            Spacer(minLength: 8)

            Button("检查本轮", systemImage: "checkmark.magnifyingglass") {
                runSelectedReview()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isReviewing || project.screenplayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .frame(minWidth: 150, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
        .background(.thinMaterial)
    }

    private var roundList: some View {
        VStack(spacing: 0) {
            Text("四轮检查")
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .frame(height: 42)

            Divider()

            VStack(spacing: 3) {
                ForEach(Array(ScreenplayReviewKind.allCases.enumerated()), id: \.element.id) {
                    index, kind in
                    roundButton(index: index, kind: kind)
                }
            }
            .padding(7)

            Spacer()
        }
        .background(Color.primary.opacity(0.025))
    }

    private func roundButton(index: Int, kind: ScreenplayReviewKind) -> some View {
        let round = workspaceState?.latestReview(for: kind)
        let current = ScreenplayReviewEngine.isCurrent(round, project: project)
        let blockers = round?.findings.count(where: { $0.severity == .blocker }) ?? 0
        return Button {
            selectedKind = kind
        } label: {
            HStack(spacing: 10) {
                Text("\(index + 1)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .frame(width: 22, height: 22)
                    .background(Color.primary.opacity(0.07), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.rawValue)
                        .font(.callout.weight(.medium))
                    Text(roundStatus(round: round, current: current, blockers: blockers))
                        .font(.caption2)
                        .foregroundStyle(roundStatusColor(round: round, current: current, blockers: blockers))
                }
                Spacer(minLength: 0)
                Image(systemName: statusImage(round: round, current: current, blockers: blockers))
                    .foregroundStyle(roundStatusColor(round: round, current: current, blockers: blockers))
            }
            .padding(10)
            .background(
                selectedKind == kind ? Color.primary.opacity(0.09) : Color.clear,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var roundDetail: some View {
        if isReviewing {
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("正在检查\(selectedKind.rawValue)")
                    .font(.headline)
                Text("AI 只查找可验证问题，不改写你的故事。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let round = selectedRound {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(selectedKind.rawValue)
                                .font(.system(.title2, design: .serif, weight: .semibold))
                            Text(selectedKind.purpose)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !isSelectedRoundCurrent {
                            Text("正文已变化")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(StudioTheme.warm)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(StudioTheme.warm.opacity(0.10), in: Capsule())
                        }
                    }

                    Text(round.summary)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 11))

                    if round.findings.isEmpty {
                        Label("本轮没有发现问题", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(StudioTheme.mint)
                            .padding(.vertical, 18)
                    } else {
                        ForEach(round.findings) { finding in
                            findingRow(finding)
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        } else {
            ContentUnavailableView(
                "尚未检查\(selectedKind.rawValue)",
                systemImage: selectedKind.systemImage,
                description: Text(selectedKind.purpose)
            )
        }
    }

    private func findingRow(_ finding: ScreenplayReviewFinding) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: findingImage(finding.severity))
                .foregroundStyle(findingColor(finding.severity))
                .font(.title3)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(finding.title)
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text(finding.location)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(finding.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
    }

    private var readinessPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Label(
                    isReady ? "可以交付" : "尚未就绪",
                    systemImage: isReady ? "checkmark.seal.fill" : "circle.dashed"
                )
                .font(.headline)
                .foregroundStyle(isReady ? StudioTheme.mint : .primary)
                Text(readinessMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            let report = ScreenplayReportBuilder.build(from: project.screenplayText)
            let parsedScenes = FountainParser.scenes(in: project.screenplayText)
            stat("结构体系", project.structureTemplate.name)
            stat("场景", "\(report.scenes.count)")
            stat("预计页数", "\(report.totalPages)")
            stat("预计时长", formattedDuration(report.totalDurationSeconds))
            stat("人物", "\(report.totalCharacterCount)")
            stat(
                "完整正文",
                parsedScenes.contains(where: SceneCompilationEngine.needsProfessionalDraft)
                    ? "仍有骨架"
                    : "已完成"
            )

            Spacer()

            Button("导出 Final Draft 交付稿 (.fdx)", systemImage: "doc.badge.arrow.up.fill") {
                isExportingFinalDraft = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isReady)
            .frame(maxWidth: .infinity)

            Button("同时导出 Fountain 源稿", systemImage: "text.document") {
                isExportingFountain = true
            }
            .buttonStyle(.bordered)
            .disabled(!isReady)
            .frame(maxWidth: .infinity)

            Text("FDX 可直接进入 Final Draft 继续排版与修订；导出成功后自动冻结一个交付版本。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(18)
        .background(Color.primary.opacity(0.025))
    }

    private func stat(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit().weight(.semibold))
        }
    }

    private var readinessMessage: String {
        if isReady {
            return "四轮检查均对应当前正文，且没有阻塞问题。"
        }
        let next = ScreenplayReviewEngine.nextRequiredKind(
            state: workspaceState,
            project: project
        )
        return "下一步：检查或处理“\(next.rawValue)”。正文变化后，旧检查会自动失效。"
    }

    private func runSelectedReview() {
        Task {
            isReviewing = true
            defer { isReviewing = false }
            do {
                guard let state = ensureWorkspaceState() else { return }
                let deterministic = ScreenplayReviewEngine.deterministicFindings(
                    kind: selectedKind,
                    project: project
                )
                let round: ScreenplayReviewRound
                if selectedKind == .format {
                    round = ScreenplayReviewRound(
                        kind: selectedKind,
                        screenplayFingerprint: ScreenplayReviewEngine.fingerprint(project.screenplayText),
                        summary: deterministic.isEmpty
                            ? "格式与交付前置条件已通过。"
                            : "确定性格式检查发现 \(deterministic.count) 个项目。",
                        findings: deterministic
                    )
                } else {
                    var aiRound = try await TypedScreenplayReviewExecutor.review(
                        kind: selectedKind,
                        project: project,
                        configuration: try aiSettings.configuration()
                    )
                    aiRound.findings = merge(deterministic, aiRound.findings)
                    if !deterministic.isEmpty {
                        aiRound.summary += " 同时合并了 \(deterministic.count) 条确定性检查结果。"
                    }
                    round = aiRound
                }
                state.addReviewRound(round)
                try ProjectPersistenceStore.savePendingChanges(in: modelContext)
                advanceIfPossible(after: round)
            } catch {
                present(error)
            }
        }
    }

    private func merge(
        _ deterministic: [ScreenplayReviewFinding],
        _ ai: [ScreenplayReviewFinding]
    ) -> [ScreenplayReviewFinding] {
        var result = deterministic
        let existing = Set(deterministic.map { "\($0.location)|\($0.title)" })
        result.append(contentsOf: ai.filter {
            !existing.contains("\($0.location)|\($0.title)")
        })
        return result
    }

    private func advanceIfPossible(after round: ScreenplayReviewRound) {
        guard !round.findings.contains(where: { $0.severity == .blocker }) else {
            return
        }
        guard let index = ScreenplayReviewKind.allCases.firstIndex(of: selectedKind),
              index + 1 < ScreenplayReviewKind.allCases.count else {
            return
        }
        selectedKind = ScreenplayReviewKind.allCases[index + 1]
    }

    private func recordDeliveryVersion(format: String) {
        let title = "\(format) 交付稿 · " + Date.now.formatted(
            .dateTime.year().month().day().hour().minute()
        )
        do {
            let state = try ProjectPersistenceStore.screenplayState(
                for: project,
                in: modelContext
            )
            try ProjectPersistenceStore.transaction(in: modelContext) {
                state.addRevision(title: title, fountainText: project.screenplayText)
                StoryCompiler.insertSnapshot(
                    project: project,
                    title: title,
                    reason: "通过四轮检查并导出 \(format) 交付稿",
                    in: modelContext
                )
            }
        } catch {
            present(error)
        }
    }

    private func ensureWorkspaceState() -> ScreenplayWorkspaceState? {
        if let workspaceState { return workspaceState }
        do {
            return try ProjectPersistenceStore.screenplayState(
                for: project,
                in: modelContext
            )
        } catch {
            present(error)
            return nil
        }
    }

    private func roundStatus(
        round: ScreenplayReviewRound?,
        current: Bool,
        blockers: Int
    ) -> String {
        guard round != nil else { return "未检查" }
        guard current else { return "已过期" }
        return blockers == 0 ? "已通过" : "\(blockers) 个阻塞"
    }

    private func roundStatusColor(
        round: ScreenplayReviewRound?,
        current: Bool,
        blockers: Int
    ) -> Color {
        guard round != nil else { return .secondary }
        guard current else { return StudioTheme.warm }
        return blockers == 0 ? StudioTheme.mint : .red
    }

    private func statusImage(
        round: ScreenplayReviewRound?,
        current: Bool,
        blockers: Int
    ) -> String {
        guard round != nil else { return "circle.dashed" }
        guard current else { return "arrow.clockwise.circle" }
        return blockers == 0 ? "checkmark.circle.fill" : "xmark.octagon.fill"
    }

    private func findingImage(_ severity: ScreenplayReviewSeverity) -> String {
        switch severity {
        case .blocker: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .note: "info.circle.fill"
        }
    }

    private func findingColor(_ severity: ScreenplayReviewSeverity) -> Color {
        switch severity {
        case .blocker: .red
        case .warning: StudioTheme.warm
        case .note: .secondary
        }
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return "\(minutes) 分钟"
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
    }
}
