import SwiftUI

/// A persistent scope bar shared by cultivation, experiments and screenplay
/// production. The project UUID is the stable root for every item shown here.
struct ProjectScopeBar: View {
    let project: StoryProject?
    let projects: [StoryProject]
    let seeds: [StorySeed]
    let onSelectProject: (UUID) -> Void
    let onCreateProject: () -> Void
    let onOpenArchive: () -> Void

    private var experimentCount: Int {
        seeds.reduce(0) { $0 + $1.cultivationSnapshot.decisions.count }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "cylinder.split.1x2.fill")
                .font(.title2)
                .foregroundStyle(StudioTheme.sky)

            if let project {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text("项目 UUID · \(shortID(project.id))")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 12)

                scopeMetric("种子", value: seeds.count, systemImage: "leaf.fill")
                scopeMetric("实验", value: experimentCount, systemImage: "flask.fill")
                scopeMetric(
                    "剧本",
                    value: project.screenplayText.storyScienceTrimmed.isEmpty ? 0 : 1,
                    systemImage: "text.book.closed.fill"
                )

                Menu {
                    ForEach(projects) { candidate in
                        Button {
                            onSelectProject(candidate.id)
                        } label: {
                            Label(
                                candidate.title,
                                systemImage: candidate.id == project.id
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                        }
                    }
                } label: {
                    Label("切换项目", systemImage: "arrow.left.arrow.right")
                }
                .menuStyle(.borderlessButton)

                Button("项目档案", systemImage: "tray.full.fill", action: onOpenArchive)
                    .buttonStyle(.bordered)
                Button("新项目", systemImage: "plus", action: onCreateProject)
                    .buttonStyle(.bordered)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("还没有项目容器")
                        .font(.headline)
                    Text("先建立项目，种子、实验和剧本才会共享同一个 UUID。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("建立第一个项目", systemImage: "plus", action: onCreateProject)
                    .buttonStyle(.borderedProminent)
                    .tint(StudioTheme.sky)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .animatedStoryBubble(tint: StudioTheme.sky, cornerRadius: 26)
    }

    @ViewBuilder
    private func scopeMetric(
        _ title: String,
        value: Int,
        systemImage: String
    ) -> some View {
        Label("\(value) \(title)", systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .fixedSize()
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8)).uppercased()
    }
}

struct ProjectArchiveView: View {
    @Environment(\.dismiss) private var dismiss

    let projects: [StoryProject]
    let seeds: [StorySeed]
    @Binding var selectedProjectID: UUID?
    let onCreateProject: () -> UUID?
    let onOpenSeed: (UUID) -> Void
    let onRenameProject: (StoryProject, String) -> Void
    let onDeleteProject: (StoryProject) -> Void

    @State private var projectPendingDeletion: StoryProject?

    private var selectedProject: StoryProject? {
        guard let selectedProjectID else { return nil }
        return projects.first { $0.id == selectedProjectID }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedProjectID) {
                ForEach(projects) { project in
                    ProjectArchiveSidebarRow(
                        project: project,
                        seeds: seeds.filter { $0.belongs(to: project.id) }
                    )
                    .tag(project.id as UUID?)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("项目数据库")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("新项目", systemImage: "plus") {
                        if let projectID = onCreateProject() {
                            selectedProjectID = projectID
                        }
                    }
                }
            }
        } detail: {
            if let selectedProject {
                ProjectArchiveDetail(
                    project: selectedProject,
                    seeds: seeds.filter { $0.belongs(to: selectedProject.id) },
                    onOpenSeed: {
                        onOpenSeed($0)
                        dismiss()
                    },
                    onRenameProject: onRenameProject,
                    onRequestDelete: { projectPendingDeletion = selectedProject }
                )
                .id(selectedProject.id)
            } else {
                ContentUnavailableView(
                    "选择一个项目",
                    systemImage: "cylinder.split.1x2",
                    description: Text("每个项目都有唯一 UUID，并统一保存种子、实验和正式剧本。")
                )
            }
        }
        .frame(minWidth: 980, minHeight: 660)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .alert(
            "删除整个项目？",
            isPresented: Binding(
                get: { projectPendingDeletion != nil },
                set: { if !$0 { projectPendingDeletion = nil } }
            ),
            presenting: projectPendingDeletion
        ) { project in
            Button("取消", role: .cancel) {}
            Button("删除项目及全部创作数据", role: .destructive) {
                onDeleteProject(project)
                projectPendingDeletion = nil
                dismiss()
            }
        } message: { project in
            let ownedSeeds = seeds.filter { $0.belongs(to: project.id) }
            let experiments = ownedSeeds.reduce(0) {
                $0 + $1.cultivationSnapshot.decisions.count
            }
            Text(
                "将删除“\(project.title)”及其 \(ownedSeeds.count) 颗种子、\(experiments) 条实验记录、剧本正文和所有生产资产。此操作无法从应用内恢复。"
            )
        }
    }
}

private struct ProjectArchiveSidebarRow: View {
    let project: StoryProject
    let seeds: [StorySeed]

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: project.projectSymbol)
                .foregroundStyle(StudioTheme.sky)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text("\(seeds.count) 种子 · \(shortID(project.id))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8)).uppercased()
    }
}

private struct ProjectArchiveDetail: View {
    let project: StoryProject
    let seeds: [StorySeed]
    let onOpenSeed: (UUID) -> Void
    let onRenameProject: (StoryProject, String) -> Void
    let onRequestDelete: () -> Void

    @State private var draftTitle: String

    init(
        project: StoryProject,
        seeds: [StorySeed],
        onOpenSeed: @escaping (UUID) -> Void,
        onRenameProject: @escaping (StoryProject, String) -> Void,
        onRequestDelete: @escaping () -> Void
    ) {
        self.project = project
        self.seeds = seeds
        self.onOpenSeed = onOpenSeed
        self.onRenameProject = onRenameProject
        self.onRequestDelete = onRequestDelete
        _draftTitle = State(initialValue: project.title)
    }

    private var experimentCount: Int {
        seeds.reduce(0) { $0 + $1.cultivationSnapshot.decisions.count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: project.projectSymbol)
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(StudioTheme.sky)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("项目名称", text: $draftTitle)
                                .font(.title2.weight(.semibold))
                                .textFieldStyle(.plain)
                                .onSubmit(saveTitle)
                            Button("保存名称", action: saveTitle)
                                .buttonStyle(.bordered)
                                .disabled(draftTitle.storyScienceTrimmed.isEmpty)
                        }
                        Text(project.id.uuidString)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text("所有种子、实验、剧本工作区和生产资产都以这个 UUID 为归属根。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("删除项目", systemImage: "trash", role: .destructive) {
                        onRequestDelete()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                HStack(spacing: 12) {
                    archiveMetric("故事种子", value: "\(seeds.count)", color: StudioTheme.mint)
                    archiveMetric("确认实验", value: "\(experimentCount)", color: StudioTheme.accent)
                    archiveMetric(
                        "正式剧本",
                        value: project.screenplayText.storyScienceTrimmed.isEmpty
                            ? "尚未建立"
                            : "\(project.screenplayText.count) 字",
                        color: StudioTheme.warm
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("项目内的种子与实验", systemImage: "leaf.circle.fill")
                        .font(.title3.weight(.semibold))
                    if seeds.isEmpty {
                        ContentUnavailableView(
                            "项目内还没有种子",
                            systemImage: "leaf",
                            description: Text("返回培养舱建立第一颗种子；它会从创建时就归入当前项目。")
                        )
                        .frame(maxWidth: .infinity, minHeight: 190)
                    } else {
                        ForEach(seeds) { seed in
                            ProjectSeedArchiveRow(seed: seed, onOpen: { onOpenSeed(seed.id) })
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("正式剧本工作区", systemImage: "text.book.closed.fill")
                        .font(.title3.weight(.semibold))
                    Text(
                        project.screenplayText.storyScienceTrimmed.isEmpty
                            ? "尚未写入正文；建立后系统只允许该项目保留一份规范工作区。"
                            : "正文、场景元数据、版本快照和复盘记录均通过同一个项目 UUID 保存。"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(24)
        }
    }

    private func archiveMetric(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.title3.weight(.bold))
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(0.2))
        }
    }

    private func saveTitle() {
        let title = draftTitle.storyScienceTrimmed
        guard !title.isEmpty else { return }
        draftTitle = title
        onRenameProject(project, title)
    }
}

private struct ProjectSeedArchiveRow: View {
    let seed: StorySeed
    let onOpen: () -> Void

    private var snapshot: StoryCultivationSnapshot { seed.cultivationSnapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(seed.title)
                        .font(.headline)
                    Text(seed.id.uuidString)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
                Spacer()
                Label("\(snapshot.decisions.count) 次实验", systemImage: "flask.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(StudioTheme.accent)
                Button("打开", action: onOpen)
                    .buttonStyle(.bordered)
            }

            if snapshot.decisions.isEmpty {
                Text(snapshot.hasAnalysis ? "已完成种子分析，等待第一次实验。" : "仍在培养阶段。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                DisclosureGroup("实验记录与唯一 ID") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(snapshot.decisions.sorted { $0.createdAt > $1.createdAt }) { decision in
                            HStack(alignment: .firstTextBaseline) {
                                Text(decision.experimentTitle)
                                    .lineLimit(1)
                                Spacer()
                                Text(String(decision.id.uuidString.prefix(8)).uppercased())
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.callout)
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(StudioTheme.mint.opacity(0.18))
        }
    }
}
