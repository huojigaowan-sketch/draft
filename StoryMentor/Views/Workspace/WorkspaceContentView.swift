import SwiftUI

struct WorkspaceContentView: View {
    let project: StoryProject
    let section: WorkspaceSection
    let onNavigate: (WorkspaceSection) -> Void

    var body: some View {
        ZStack {
            StudioCanvas()
            sectionContent
        }
        .navigationSplitViewColumnWidth(min: 560, ideal: 820)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .home, .seeds, .classics, .fragments:
            WelcomeWorkspaceView(onCreateProject: { onNavigate(.seeds) })
        // Older project records can still request these sections.  They now
        // resolve to the NSIR workbench rather than reopening a parallel,
        // pre-compiler interface.
        case .compiler, .overview, .ideas, .templates, .journey, .structure:
            NarrativeCompilerWorkbenchView(project: project, onNavigate: onNavigate)
        case .characters:
            CharacterLabView(project: project)
        case .relationships:
            CharacterRelationshipGraphView(project: project)
        case .world, .theme:
            StoryModuleEditorView(project: project, section: section)
        case .scenes:
            SceneContractWorkspaceView(project: project, onNavigate: onNavigate)
        case .screenplay:
            ScreenplayStudioView(
                project: project,
                onNavigate: onNavigate
            )
        case .versions:
            VersionWorkspaceView(project: project, onNavigate: onNavigate)
        case .delivery:
            DeliveryWorkspaceView(project: project, onNavigate: onNavigate)
        case .knowledge:
            KnowledgeLibraryView()
        }
    }
}

struct WelcomeWorkspaceView: View {
    let onCreateProject: () -> Void

    var body: some View {
        ZStack {
            StudioCanvas()

            VStack(spacing: 24) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [StudioTheme.accent, StudioTheme.warm],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(spacing: 8) {
                    Text("从一个故事碎片开始")
                        .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    Text("把人物、欲望或困境写下来，工作台会帮你看见下一步。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)

                Button("创建故事项目", systemImage: "plus") {
                    onCreateProject()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(48)
        }
    }
}

struct ComingSoonModuleView: View {
    let section: WorkspaceSection

    private var description: String {
        switch section {
        case .world: "把世界规则变成冲突，而不是百科设定。"
        case .theme: "把抽象关键词转成可以被故事验证的命题。"
        case .structure: "用选择与代价组织节拍，而不是机械套模板。"
        case .scenes: "先明确目标、冲突和转折，再进入剧本正文。"
        case .screenplay: "从场景数据生成并维护标准 Fountain 剧本。"
        case .versions: "把重要节点冻结为可命名、可比较、可恢复的版本。"
        case .delivery: "分轮检查结构、连续性与格式，再生成交付文件。"
        case .knowledge: "导入你的编剧资料，在本机建立可检索的私人知识库。"
        case .home: "从现实材料、经典研究或已有项目开始今天的创作。"
        case .seeds: "从新闻、历史、资讯和观察中发现欲望、阻碍与代价。"
        case .classics: "按人物、冲突、结构与主题研究中国及全球经典。"
        case .fragments: "把真正喜欢的AI结果积累成可以检索、重组和继续生长的私人素材。"
        case .templates: "选择一套会真正改变故事节奏、转折方式与创作体验的规则。"
        case .journey: "通过一连串具体选择推动故事，每次选择都会改变后续压力与场面。"
        case .compiler: "把作者命题编译为可验证、可比较、可提交的叙事状态转移。"
        case .overview, .ideas, .characters, .relationships: ""
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: section.systemImage)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(StudioTheme.accent)
                .frame(width: 76, height: 76)
                .background(StudioTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 22))

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Text(section.rawValue)
                        .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    if let phaseLabel = section.phaseLabel {
                        PhaseBadge(text: phaseLabel)
                    }
                }

                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }

            Text("界面位置和数据边界已经预留，后续会按诊断引擎的顺序开放。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(48)
    }
}
