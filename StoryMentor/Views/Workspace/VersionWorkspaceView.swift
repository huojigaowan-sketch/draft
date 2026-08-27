import SwiftData
import SwiftUI

struct VersionWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: StoryProject
    let onNavigate: (WorkspaceSection) -> Void
    @Query private var workspaceStates: [ScreenplayWorkspaceState]

    @State private var selectedRevisionID: UUID?
    @State private var revisionPendingRestore: ScreenplayRevision?
    @State private var persistenceError = ""
    @State private var showingPersistenceError = false

    private var workspaceState: ScreenplayWorkspaceState? {
        workspaceStates
            .filter { $0.projectID == project.id }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private var revisions: [ScreenplayRevision] {
        workspaceState?.revisions.sorted { $0.createdAt > $1.createdAt } ?? []
    }

    private var selectedRevision: ScreenplayRevision? {
        guard let selectedRevisionID else { return revisions.first }
        return revisions.first { $0.id == selectedRevisionID } ?? revisions.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                revisionList
                    .frame(minWidth: 270, idealWidth: 310, maxWidth: 360)
                revisionDetail
                    .frame(minWidth: 560)
            }
        }
        .background(StudioCanvas())
        .task {
            selectedRevisionID = selectedRevisionID ?? revisions.first?.id
        }
        .confirmationDialog(
            "恢复“\(revisionPendingRestore?.title ?? "此版本")”？",
            isPresented: Binding(
                get: { revisionPendingRestore != nil },
                set: { if !$0 { revisionPendingRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("恢复并保留当前稿") {
                restorePendingRevision()
            }
            .keyboardShortcut(.defaultAction)
            Button("取消", role: .cancel) {
                revisionPendingRestore = nil
            }
            .keyboardShortcut(.cancelAction)
        } message: {
            Text("当前正文会先自动保存为“恢复前版本”，不会丢失。")
        }
        .alert("无法保存版本", isPresented: $showingPersistenceError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(persistenceError)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("版本")
                    .font(.headline)
                Text("\(revisions.count) 个已保存节点")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 160, alignment: .leading)

            Spacer(minLength: 8)
            ProductionWorkspaceSwitcher(selection: .versions, onSelect: onNavigate)
            Spacer(minLength: 8)

            Button("保存当前版本", systemImage: "clock.badge.checkmark") {
                saveCurrentVersion()
            }
            .buttonStyle(.borderedProminent)
            .disabled(project.screenplayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .frame(minWidth: 150, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
        .background(.thinMaterial)
    }

    private var revisionList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("时间线")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("当前稿始终自动保存")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)

            Divider()

            ScrollView {
                LazyVStack(spacing: 3) {
                    currentDraftRow
                    ForEach(revisions) { revision in
                        revisionRow(revision)
                    }
                }
                .padding(7)
            }
        }
        .background(Color.primary.opacity(0.025))
    }

    private var currentDraftRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil.line")
                .foregroundStyle(StudioTheme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text("当前工作稿")
                    .font(.callout.weight(.semibold))
                Text(project.updatedAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("实时")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(StudioTheme.mint)
        }
        .padding(11)
        .background(StudioTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }

    private func revisionRow(_ revision: ScreenplayRevision) -> some View {
        Button {
            selectedRevisionID = revision.id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(revision.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(revision.createdAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(11)
            .background(
                selectedRevision?.id == revision.id
                    ? Color.primary.opacity(0.09)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var revisionDetail: some View {
        if let revision = selectedRevision {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(revision.title)
                                .font(.system(.title2, design: .serif, weight: .semibold))
                            Text(revision.createdAt, format: .dateTime.year().month().day().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("恢复此版本", systemImage: "arrow.uturn.backward") {
                            revisionPendingRestore = revision
                        }
                        .buttonStyle(.bordered)
                    }

                    comparison(revision)

                    Divider()

                    Text(revision.fountainText)
                        .font(.system(size: 14, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(30)
                .frame(maxWidth: 920, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        } else {
            ContentUnavailableView(
                "还没有版本",
                systemImage: "clock.badge.plus",
                description: Text("保存重要节点即可形成时间线；编辑器仍会自动保存当前工作稿。")
            )
        }
    }

    private func comparison(_ revision: ScreenplayRevision) -> some View {
        let old = revisionMetrics(revision.fountainText)
        let current = revisionMetrics(project.screenplayText)
        return HStack(spacing: 0) {
            metric("场景", old.scenes, current.scenes)
            Divider().frame(height: 44)
            metric("行数", old.lines, current.lines)
            Divider().frame(height: 44)
            metric("字数", old.characters, current.characters)
        }
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    private func metric(_ title: String, _ oldValue: Int, _ currentValue: Int) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(oldValue) → \(currentValue)")
                .font(.callout.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity)
    }

    private func revisionMetrics(_ text: String) -> (scenes: Int, lines: Int, characters: Int) {
        (
            FountainParser.scenes(in: text).count,
            text.components(separatedBy: .newlines).count,
            text.count
        )
    }

    private func saveCurrentVersion() {
        let title = "版本 \(revisions.count + 1) · " + Date.now.formatted(
            .dateTime.month().day().hour().minute()
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
                    reason: "作者冻结剧本版本",
                    in: modelContext
                )
            }
            selectedRevisionID = state.revisions.first?.id
        } catch {
            present(error)
        }
    }

    private func restorePendingRevision() {
        guard let revision = revisionPendingRestore else { return }
        do {
            let state = try ProjectPersistenceStore.screenplayState(
                for: project,
                in: modelContext
            )
            try ProjectPersistenceStore.transaction(in: modelContext) {
                state.addRevision(title: "恢复前版本", fountainText: project.screenplayText)
                StoryCompiler.insertSnapshot(
                    project: project,
                    title: "恢复前版本",
                    reason: "恢复剧本版本前自动保护当前工作稿",
                    in: modelContext
                )
                project.screenplayText = revision.fountainText
                _ = state.reconcileScenes(FountainParser.scenes(in: revision.fountainText))
                state.activeSceneIndex = 0
                state.activeSceneID = state.sceneRecords.first?.id
                project.touch()
                StoryCompiler.updateFindings(project: project, in: modelContext)
            }
            revisionPendingRestore = nil
            onNavigate(.screenplay)
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        persistenceError = error.localizedDescription
        showingPersistenceError = true
    }
}
