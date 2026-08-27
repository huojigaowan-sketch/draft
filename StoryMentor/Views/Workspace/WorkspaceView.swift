import SwiftData
import SwiftUI

struct WorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoryProject.updatedAt, order: .reverse)
    private var projects: [StoryProject]
    @Query(sort: \StorySeed.updatedAt, order: .reverse)
    private var seeds: [StorySeed]
    @State private var selectedProjectID: UUID?
    @State private var selectedSection: WorkspaceSection = .home
    @State private var navigationHistory: [WorkspaceSection] = []
    @State private var showingCreateProject = false
    @State private var projectPendingDeletion: StoryProject?
    @State private var showingPersistenceError = false
    @State private var persistenceError = ""
    @State private var didRepairLegacyProjects = false

    private var selectedProject: StoryProject? {
        guard let selectedProjectID else { return nil }
        return projects.first { $0.id == selectedProjectID }
    }

    var body: some View {
        NarrativeBubbleWorkspaceRoot(
            projects: projects,
            selectedProjectID: $selectedProjectID,
            onCreate: createCompilerProject,
            onCreateProject: createProjectWorkspace,
            onRenameProject: renameProject,
            onDeleteProject: deleteProject
        )
        .frame(minWidth: 1_080, minHeight: 700)
        .task {
            if !didRepairLegacyProjects {
                do {
                    try ProjectPersistenceStore.transaction(in: modelContext) {
                        _ = ProjectDataRepair.repairIfNeeded(
                            projects: projects,
                            in: modelContext
                        )
                        _ = try ProjectPersistenceStore.repairGraph(
                            projects: projects,
                            seeds: seeds,
                            in: modelContext
                        )
                        _ = StoryCultivationProjectBridge.repairLinkedProjects(
                            seeds: seeds,
                            projects: projects,
                            in: modelContext
                        )
                    }
                    try DataFlowInvariantChecks.validate(
                        projects: projects,
                        seeds: seeds,
                        in: modelContext
                    )
                    didRepairLegacyProjects = true
                } catch {
                    presentPersistenceError(error)
                }
            }
            if selectedProjectID == nil { selectedProjectID = projects.first?.id }
        }
        .onChange(of: projects.count) { _, _ in
            if selectedProjectID == nil {
                selectedProjectID = projects.first?.id
            }
        }
        .alert("无法保存更改", isPresented: $showingPersistenceError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(persistenceError)
        }
    }

    private func createCompilerProject(
        seed: StorySeed,
        snapshot: StoryCultivationSnapshot
    ) -> UUID? {
        let project = StoryCultivationProjectBridge.connect(
            seed: seed,
            snapshot: snapshot,
            projects: projects,
            in: modelContext
        )
        do {
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            selectedProjectID = project.id
            selectedSection = .compiler
            return project.id
        } catch {
            presentPersistenceError(error)
            return nil
        }
    }

    private func createProjectWorkspace() -> UUID? {
        let project = StoryProject(
            title: "新故事项目 \(projects.count + 1)",
            notes: "项目统一保存故事种子、实验记录、正式剧本与生产资产。"
        )
        modelContext.insert(project)
        do {
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            selectedProjectID = project.id
            return project.id
        } catch {
            presentPersistenceError(error)
            return nil
        }
    }

    private func renameProject(_ project: StoryProject, title: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        project.title = cleanTitle
        project.touch()
        do {
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
        } catch {
            presentPersistenceError(error)
        }
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch selectedSection {
        case .home:
            StoryGrowthHomeView(
                projects: projects,
                onCreateProject: { showingCreateProject = true },
                onOpenProject: {
                    selectedProjectID = $0.id
                    navigate(.compiler)
                },
                onDeleteProject: { projectPendingDeletion = $0 }
            )
        case .seeds:
            RealityStoryHubView(onCreateProject: createProject)
        case .classics:
            ClassicsLibraryView(onStartExperiment: startClassicExperiment)
        case .fragments:
            FragmentMemoryView(onGrow: growFragment)
        case .knowledge:
            ZStack {
                StudioCanvas()
                KnowledgeLibraryView()
            }
        case .compiler, .overview, .ideas, .templates, .journey, .characters, .relationships, .world, .theme, .structure, .scenes, .screenplay, .versions, .delivery:
            if let selectedProject {
                WorkspaceContentView(
                    project: selectedProject,
                    section: selectedSection,
                    onNavigate: navigate
                )
            } else {
                WelcomeWorkspaceView(onCreateProject: { showingCreateProject = true })
            }
        }
    }

    private func navigate(_ section: WorkspaceSection) {
        guard section != selectedSection else { return }
        if section == .home {
            navigateHome()
            return
        }
        navigationHistory.append(selectedSection)
        selectedSection = section
    }

    private func navigateBack() {
        guard let previousSection = navigationHistory.popLast() else { return }
        selectedSection = previousSection
    }

    private func navigateHome() {
        navigationHistory.removeAll()
        selectedSection = .home
    }

    private func createProject(from draft: NewProjectDraft) {
        let direction = draft.selectedDirection
        let dramatization = draft.dramatization
        let routeText = direction.map {
            """
            【一句话故事】
            \($0.logline)

            【主人公与欲望】
            \($0.protagonist)
            \($0.desire)

            【对抗力量】
            \($0.antagonistForce)

            【失败代价】
            \($0.stakes)

            【戏剧问题】
            \($0.dramaticQuestion)

            【事实与虚构边界】
            \($0.fictionalizationNote)
            """
        } ?? draft.logline
        let project = StoryProject(
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            genre: draft.genre,
            logline: draft.logline.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: """
            【素材入口】\(draft.sourceMethod)
            【作者意图】\(draft.authorIntent.isEmpty ? "未补充" : draft.authorIntent)
            \(direction.map { "\n【事实与虚构边界】\($0.fictionalizationNote)" } ?? "")
            """,
            sourceTitle: draft.sourceTitle,
            sourceText: draft.sourceText,
            sourceFacts: dramatization?.factualSummary ?? "",
            dramaticPromise: direction?.dramaticQuestion
                ?? dramatization?.dramaticCore
                ?? "",
            storyPathText: routeText
        )
        project.creativeDirectionText = routeText
        project.characterBibleText = direction?.protagonist ?? ""
        project.worldBibleText = direction?.realityTexture ?? ""
        project.coreConflictText = [
            direction?.antagonistForce,
            direction?.stakes,
            dramatization?.dramaticCore
        ]
        .compactMap { $0 }
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n")
        project.storyBibleDigest = """
        【人物小传】
        \(project.characterBibleText.isEmpty ? "尚待结构选择确认" : project.characterBibleText)

        【世界规则】
        \(project.worldBibleText.isEmpty ? "尚待结构选择确认" : project.worldBibleText)

        【主题命题】
        尚待结构选择确认

        【核心冲突】
        \(project.coreConflictText.isEmpty ? "尚待结构选择确认" : project.coreConflictText)
        """
        project.storyBibleRevision = 1
        project.storyBibleUpdatedAt = .now
        project.storyBibleSyncNote = "项目创建时已建立第一版剧本圣经"
        modelContext.insert(project)

        let sourceArtifact = ProjectArtifact(
            title: draft.sourceTitle,
            kind: .source,
            status: .integrated,
            originLabel: draft.sourceMethod,
            humanInput: draft.sourceText,
            lockedIdeas: direction?.fictionalizationNote ?? "",
            workingText: dramatization?.factualSummary ?? draft.sourceText,
            acceptedText: dramatization?.factualSummary ?? draft.sourceText,
            sortIndex: 0,
            project: project
        )
        sourceArtifact.integratedSnapshot = sourceArtifact.acceptedText
        modelContext.insert(sourceArtifact)
        project.artifacts.append(sourceArtifact)

        let directionArtifact = ProjectArtifact(
            title: "已选故事方向 · \(draft.title)",
            kind: .inspiration,
            status: .integrated,
            originLabel: "DeepSeek 戏剧化 · 用户选择",
            humanInput: draft.authorIntent,
            lockedIdeas: direction?.fictionalizationNote ?? "",
            workingText: routeText,
            acceptedText: routeText,
            sortIndex: 1,
            project: project
        )
        directionArtifact.integratedSnapshot = routeText
        modelContext.insert(directionArtifact)
        project.artifacts.append(directionArtifact)

        if let direction,
           !direction.protagonist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let protagonist = StoryCharacter(
                name: "主人公",
                role: .protagonist,
                seedText: direction.protagonist,
                externalGoal: direction.desire,
                project: project
            )
            modelContext.insert(protagonist)
            project.characters.append(protagonist)
        }

        do {
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            selectedProjectID = project.id
            navigate(.compiler)
        } catch {
            presentPersistenceError(error)
        }
    }

    private func createProject(
        from seed: StorySeed,
        direction: AdaptationDirection
    ) {
        let genre = StoryGenre.allCases.first {
            $0 != .unselected && direction.genre.contains($0.rawValue)
        } ?? .drama
        let project = StoryProject(
            title: direction.title,
            genre: genre,
            logline: direction.logline,
            notes: """
            【改编方向】
            \(direction.dramaticQuestion)

            【对抗力量】
            \(direction.antagonistForce)

            【失败代价】
            \(direction.stakes)

            【事实与虚构边界】
            \(direction.fictionalizationNote)
            """,
            sourceTitle: seed.title,
            sourceText: seed.sourceText,
            sourceFacts: seed.factualSummary,
            dramaticPromise: direction.dramaticQuestion
        )
        modelContext.insert(project)

        let sourceModule = ProjectArtifact(
            title: seed.title,
            kind: .source,
            status: .integrated,
            originLabel: seed.sourceType.rawValue,
            humanInput: seed.sourceText,
            lockedIdeas: "事实层与虚构提案必须分开；涉及真实人物时保留核验与匿名化要求。",
            workingText: seed.factualSummary,
            acceptedText: seed.factualSummary,
            sortIndex: 0,
            project: project
        )
        sourceModule.integratedSnapshot = seed.factualSummary
        modelContext.insert(sourceModule)
        project.artifacts.append(sourceModule)

        let routeText = """
        【一句话故事】
        \(direction.logline)

        【主人公与欲望】
        \(direction.protagonist)
        \(direction.desire)

        【对抗力量】
        \(direction.antagonistForce)

        【失败代价】
        \(direction.stakes)

        【戏剧问题】
        \(direction.dramaticQuestion)

        【事实与虚构边界】
        \(direction.fictionalizationNote)
        """
        let routeModule = ProjectArtifact(
            title: direction.title,
            kind: .inspiration,
            status: .integrated,
            originLabel: "现实变故事 · 用户选择",
            humanInput: seed.authorIntent,
            lockedIdeas: direction.fictionalizationNote,
            workingText: routeText,
            acceptedText: routeText,
            sortIndex: 1,
            project: project
        )
        modelContext.insert(routeModule)
        project.artifacts.append(routeModule)

        if !direction.protagonist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let protagonist = StoryCharacter(
                name: "主人公",
                role: .protagonist,
                seedText: direction.protagonist,
                externalGoal: direction.desire,
                project: project
            )
            modelContext.insert(protagonist)
            project.characters.append(protagonist)
        }

        let task = CreativeTask(
            title: direction.nextTaskTitle,
            prompt: direction.nextTaskPrompt,
            rationale: seed.dramaticCore,
            difficulty: 1,
            status: .active,
            project: project
        )
        modelContext.insert(task)
        project.tasks.append(task)
        seed.linkedProjectID = project.id
        seed.updatedAt = .now

        do {
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            selectedProjectID = project.id
            navigate(.compiler)
        } catch {
            presentPersistenceError(error)
        }
    }

    private func startClassicExperiment(_ story: StoryCase) {
        let project = StoryProject(
            title: "经典实验：\(story.title)",
            genre: .drama,
            notes: "只借用叙事功能，创造一个时代、人物关系和情节都不同的原创故事。",
            sourceTitle: story.title,
            sourceText: story.promptBlock,
            sourceFacts: "\(story.archetype)\n\(story.themeConflict)",
            dramaticPromise: story.themeConflict
        )
        modelContext.insert(project)
        let module = ProjectArtifact(
            title: "\(story.title) · 叙事功能研究",
            kind: .research,
            status: .integrated,
            originLabel: "经典研究",
            humanInput: "我想研究这部作品的功能，并注入自己的新人物、新时代或新命题。",
            lockedIdeas: "只借用叙事功能；不复制具体情节、对白与独特表达。",
            workingText: story.promptBlock,
            acceptedText: story.promptBlock,
            sortIndex: 0,
            project: project
        )
        modelContext.insert(module)
        project.artifacts.append(module)
        do {
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            selectedProjectID = project.id
            navigate(.compiler)
        } catch {
            presentPersistenceError(error)
        }
    }

    private func growFragment(_ fragment: StoryFragment) {
        let firstLine = fragment.content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? fragment.title
        let project = StoryProject(
            title: fragment.title,
            logline: String(firstLine.prefix(180)),
            notes: """
            【来自灵感碎片】
            类型：\(fragment.kind.rawValue)
            标签：\(fragment.tagsText)
            喜爱原因：\(fragment.note)

            \(fragment.content)
            """,
            sourceTitle: "灵感碎片：\(fragment.title)",
            sourceText: fragment.content
        )
        modelContext.insert(project)
        let module = ProjectArtifact(
            title: fragment.title,
            kind: .inspiration,
            status: .integrated,
            originLabel: "灵感碎片",
            humanInput: fragment.note,
            workingText: fragment.content,
            acceptedText: fragment.content,
            sortIndex: 0,
            project: project
        )
        modelContext.insert(module)
        project.artifacts.append(module)
        fragment.grownProjectID = project.id
        fragment.updatedAt = .now
        do {
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            selectedProjectID = project.id
            navigate(.compiler)
        } catch {
            presentPersistenceError(error)
        }
    }

    private func deleteProject(_ project: StoryProject) {
        let nextProjectID = projects.first { $0.id != project.id }?.id
        do {
            try ProjectPersistenceStore.delete(
                project: project,
                in: modelContext
            )
            if selectedProjectID == project.id {
                selectedProjectID = nextProjectID
                navigationHistory.removeAll()
                selectedSection = nextProjectID == nil ? .home : .compiler
            }
        } catch {
            presentPersistenceError(error)
        }
    }

    private func deletePendingProject() {
        guard let projectPendingDeletion else { return }
        deleteProject(projectPendingDeletion)
        self.projectPendingDeletion = nil
    }

    private func presentPersistenceError(_ error: Error) {
        persistenceError = error.localizedDescription
        showingPersistenceError = true
    }
}
