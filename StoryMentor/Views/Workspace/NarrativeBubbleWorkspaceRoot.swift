import SwiftData
import SwiftUI

/// Stable three-phase product root. Story cultivation and experimentation are
/// SwiftUI-owned; the production phase keeps the existing NSIR compiler and
/// its narrowly bridged Final Draft-style NSTextView editor intact.
struct NarrativeBubbleWorkspaceRoot: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StorySeed.updatedAt, order: .reverse)
    private var seeds: [StorySeed]

    let projects: [StoryProject]
    @Binding var selectedProjectID: UUID?
    let onCreate: (StorySeed, StoryCultivationSnapshot) -> UUID?
    let onCreateProject: () -> UUID?
    let onRenameProject: (StoryProject, String) -> Void
    let onDeleteProject: (StoryProject) -> Void

    @State private var phase: StorySciencePhase = .incubator
    @State private var selectedSeedID: UUID?
    @State private var productionSection: WorkspaceSection = .compiler
    @State private var isHandoffExpanded = true
    @State private var showingProjectArchive = false

    private var selectedProject: StoryProject? {
        guard let selectedProjectID else { return nil }
        return projects.first { $0.id == selectedProjectID }
    }

    private var projectSeeds: [StorySeed] {
        guard let selectedProjectID else { return [] }
        return seeds.filter { $0.belongs(to: selectedProjectID) }
    }

    private var selectedSeed: StorySeed? {
        guard let selectedSeedID else { return nil }
        return projectSeeds.first { $0.id == selectedSeedID }
    }

    private var productionSeed: StorySeed? {
        selectedSeed ?? projectSeeds.first
    }

    private var canEnterLaboratory: Bool {
        selectedSeed?.cultivationSnapshot.hasAnalysis == true
            || projectSeeds.contains { $0.cultivationSnapshot.hasAnalysis }
    }

    var body: some View {
        ZStack {
            StudioCanvas()
            CompilerAnimatedBackdrop(active: false)

            VStack(spacing: 10) {
                StorySciencePhaseRail(
                    phase: phase,
                    canEnterLaboratory: canEnterLaboratory,
                    hasProductionProject: !projects.isEmpty,
                    onSelect: selectPhase
                )
                .padding(.horizontal, 14)
                .padding(.top, 12)

                ProjectScopeBar(
                    project: selectedProject,
                    projects: projects,
                    seeds: projectSeeds,
                    onSelectProject: selectProject,
                    onCreateProject: createProjectWorkspace,
                    onOpenArchive: { showingProjectArchive = true }
                )
                .padding(.horizontal, 14)

                phaseContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if selectedProjectID == nil {
                selectedProjectID = projects.first?.id
            }
            alignSeedSelectionToProject()
        }
        .onChange(of: projects.count) { _, _ in
            if selectedProject == nil {
                selectedProjectID = projects.first?.id
            }
            alignSeedSelectionToProject()
        }
        .onChange(of: seeds.count) { _, _ in
            alignSeedSelectionToProject()
        }
        .onChange(of: selectedProjectID) { _, _ in
            alignSeedSelectionToProject()
        }
        .sheet(isPresented: $showingProjectArchive) {
            ProjectArchiveView(
                projects: projects,
                seeds: seeds,
                selectedProjectID: $selectedProjectID,
                onCreateProject: {
                    let projectID = onCreateProject()
                    if let projectID { selectProject(projectID) }
                    return projectID
                },
                onOpenSeed: openSeedFromArchive,
                onRenameProject: onRenameProject,
                onDeleteProject: onDeleteProject
            )
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .incubator, .laboratory:
            if let selectedProject {
                StoryScienceLabView(
                    projectID: selectedProject.id,
                    phase: phase,
                    selectedSeedID: $selectedSeedID,
                    onChangePhase: selectPhase,
                    onCompile: compile
                )
                .id(selectedProject.id)
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                projectEmptyState
            }

        case .compiler:
            if let selectedProject {
                VStack(spacing: 8) {
                    if let productionSeed {
                        ProductionHandoffBubble(
                            seed: productionSeed,
                            snapshot: productionSeed.cultivationSnapshot,
                            section: productionSection,
                            isExpanded: $isHandoffExpanded,
                            onNavigate: navigateProduction,
                            onReturnToLaboratory: { selectPhase(.laboratory) }
                        )
                        .padding(.horizontal, 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    WorkspaceContentView(
                        project: selectedProject,
                        section: productionSection,
                        onNavigate: navigateProduction
                    )
                    .id(selectedProject.id)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    projectDock
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                productionEmptyState
            }
        }
    }

    private var projectDock: some View {
        VStack(spacing: 8) {
            ProductionSectionBubbleBar(
                selection: productionSection,
                onSelect: navigateProduction
            )

            HStack(spacing: 10) {
                Menu {
                    Section("生产项目") {
                        ForEach(projects) { project in
                            Button {
                                selectProject(project.id)
                            } label: {
                                Label(
                                    project.title,
                                    systemImage: project.id == selectedProjectID
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                            }
                        }
                    }
                    Divider()
                    Button("培养新的故事种子", systemImage: "leaf.fill") {
                        selectPhase(.incubator)
                    }
                } label: {
                    Label(
                        selectedProject?.title ?? "选择生产项目",
                        systemImage: "text.book.closed.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                }
                .menuStyle(.borderlessButton)

                Spacer()

                Label(
                    "剧本正文编辑器受保护 · 元素格式与双回车流转不变",
                    systemImage: "lock.shield.fill"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)

                SettingsLink {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.plain)
                .help("模型与应用设置")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .animatedStoryBubble(tint: StudioTheme.warm, cornerRadius: 24)
    }

    private var productionEmptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "diamond.fill")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(StudioTheme.warm)
            Text("先让故事结晶，再进入生产")
                .font(.system(.title2, design: .serif, weight: .semibold))
            Text("在实验室确认人物洞察、不可两全的冲突与主题假设后，系统会建立 NSIR 项目，并继续使用现有 Final Draft 式正文编辑器。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Button("返回故事培养舱", systemImage: "leaf.fill") {
                selectPhase(.incubator)
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioTheme.warm)
        }
        .padding(42)
        .animatedStoryBubble(tint: StudioTheme.warm, cornerRadius: 58)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var projectEmptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "cylinder.split.1x2")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(StudioTheme.sky)
            Text("先建立一个项目容器")
                .font(.system(.title2, design: .serif, weight: .semibold))
            Text("项目拥有唯一 UUID；之后创建的种子、实验记录、正式剧本与生产资产都会自动归入其中。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            Button("建立项目", systemImage: "plus", action: createProjectWorkspace)
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.sky)
        }
        .padding(42)
        .animatedStoryBubble(tint: StudioTheme.sky, cornerRadius: 58)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectPhase(_ next: StorySciencePhase) {
        if next == .laboratory {
            guard canEnterLaboratory else { return }
            if selectedSeed?.cultivationSnapshot.hasAnalysis != true {
                selectedSeedID = projectSeeds.first(where: {
                    $0.cultivationSnapshot.hasAnalysis
                })?.id
            }
        }
        if next == .compiler, selectedProjectID == nil {
            selectedProjectID = selectedSeed?.linkedProjectID ?? projects.first?.id
        } else if next == .compiler,
                  let linkedProjectID = selectedSeed?.linkedProjectID,
                  projects.contains(where: { $0.id == linkedProjectID }) {
            selectedProjectID = linkedProjectID
        }
        withAnimation(.spring(response: 0.48, dampingFraction: 0.84)) {
            phase = next
        }
    }

    private func compile(_ seed: StorySeed, crystal: StoryCrystal) {
        var snapshot = seed.cultivationSnapshot
        if snapshot.crystal != crystal {
            snapshot.crystal = crystal
            seed.cultivationSnapshot = snapshot
        }
        guard let projectID = onCreate(seed, snapshot) else { return }
        selectedSeedID = seed.id
        selectedProjectID = projectID
        productionSection = .compiler
        isHandoffExpanded = true
        selectPhase(.compiler)
    }

    private func navigateProduction(_ section: WorkspaceSection) {
        guard section.requiresProject else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            productionSection = section
            if section == .screenplay {
                isHandoffExpanded = false
            }
        }
    }

    private func selectProject(_ projectID: UUID) {
        selectedProjectID = projectID
        alignSeedSelectionToProject()
        productionSection = .compiler
        isHandoffExpanded = true
    }

    private func createProjectWorkspace() {
        guard let projectID = onCreateProject() else { return }
        selectProject(projectID)
        withAnimation(.spring(response: 0.44, dampingFraction: 0.86)) {
            phase = .incubator
        }
    }

    private func alignSeedSelectionToProject() {
        guard let selectedProjectID else {
            selectedSeedID = nil
            return
        }
        if let selectedSeedID,
           seeds.contains(where: {
               $0.id == selectedSeedID && $0.belongs(to: selectedProjectID)
           }) {
            return
        }
        let ownedSeeds = seeds.filter { $0.belongs(to: selectedProjectID) }
        selectedSeedID = ownedSeeds.first(where: {
            $0.cultivationSnapshot.hasAnalysis
        })?.id ?? ownedSeeds.first?.id
    }

    private func openSeedFromArchive(_ seedID: UUID) {
        guard let seed = seeds.first(where: { $0.id == seedID }),
              let projectID = seed.projectID else { return }
        selectedProjectID = projectID
        selectedSeedID = seed.id
        withAnimation(.spring(response: 0.44, dampingFraction: 0.86)) {
            phase = seed.cultivationSnapshot.hasAnalysis ? .laboratory : .incubator
        }
    }
}
