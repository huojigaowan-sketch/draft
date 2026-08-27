import SwiftUI

struct StoryGrowthHomeView: View {
    let projects: [StoryProject]
    let onCreateProject: () -> Void
    let onOpenProject: (StoryProject) -> Void
    let onDeleteProject: (StoryProject) -> Void

    @State private var searchText = ""

    private let columns = [
        GridItem(.adaptive(minimum: 265, maximum: 360), spacing: 16)
    ]

    private var filteredProjects: [StoryProject] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return projects }
        return projects.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.projectSummary.localizedCaseInsensitiveContains(query)
                || $0.genre.rawValue.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ZStack {
            StudioCanvas()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    libraryHeader

                    if projects.isEmpty {
                        emptyLibrary
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            NewProjectLibraryCard(action: onCreateProject)
                            ForEach(filteredProjects) { project in
                                ProjectLibraryCard(
                                    project: project,
                                    action: { onOpenProject(project) },
                                    onDelete: { onDeleteProject(project) }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 30)
                .frame(maxWidth: 1_220)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationSplitViewColumnWidth(min: 600, ideal: 860)
    }

    private var libraryHeader: some View {
        HStack(alignment: .bottom, spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                EyebrowLabel(text: "PROJECT LIBRARY", color: StudioTheme.mint)
                Text("所有剧本项目")
                    .font(.system(size: 38, weight: .semibold, design: .serif))
                Text("每个项目独立保存自己的素材、选择历史、剧本圣经与完整剧本。")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TextField("搜索项目", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
        }
    }

    private var emptyLibrary: some View {
        StudioCard(padding: 30) {
            HStack(spacing: 28) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(StudioTheme.mint.opacity(0.11))
                    Image(systemName: "film.stack.fill")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(StudioTheme.mint)
                }
                .frame(width: 112, height: 112)

                VStack(alignment: .leading, spacing: 10) {
                    Text("建立你的第一部剧本")
                        .font(.system(.title, design: .serif, weight: .semibold))
                    Text("可以从网页新闻、小说或资料 Markdown、TXT、参考剧本，甚至一句临时想法开始。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("新建第一个项目", systemImage: "plus") {
                        onCreateProject()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                Spacer()
            }
        }
    }

}

private struct NewProjectLibraryCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(StudioTheme.mint, in: RoundedRectangle(cornerRadius: 15))
                Spacer()
                Text("新建剧本项目")
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("新闻、Markdown、TXT、参考剧本或一个临时想法")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Label("选择起点", systemImage: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(StudioTheme.mint)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 245, alignment: .topLeading)
            .background(StudioTheme.mint.opacity(0.055), in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        StudioTheme.mint.opacity(0.40),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6])
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("新建剧本项目")
    }
}

private struct ProjectLibraryCard: View {
    let project: StoryProject
    let action: () -> Void
    let onDelete: () -> Void

    private var tint: Color {
        switch project.genre {
        case .romance, .comedy: StudioTheme.warm
        case .crime, .thriller, .mystery: StudioTheme.sky
        case .scienceFiction, .fantasy: Color.purple
        case .action, .shortDrama: Color.orange
        case .drama, .unselected: StudioTheme.mint
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Image(systemName: project.projectSymbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 50, height: 50)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                    Spacer()
                    ProgressRing(
                        value: project.completionFraction,
                        lineWidth: 5,
                        diameter: 46
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(project.title)
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(project.projectSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(minHeight: 48, alignment: .topLeading)
                }

                Spacer(minLength: 2)
                Divider()
                HStack {
                    PhaseBadge(text: project.workflowLabel)
                    Spacer()
                    Text(project.updatedAt, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(tint)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 245, alignment: .topLeading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.primary.opacity(0.06))
            }
            .shadow(color: .black.opacity(0.045), radius: 16, y: 7)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(project.title)，\(project.workflowLabel)")
        .contextMenu {
            Button("删除项目", systemImage: "trash", role: .destructive) {
                onDelete()
            }
        }
    }
}

struct GrowthGuidePanelView: View {
    let section: WorkspaceSection

    private var guide: (title: String, subtitle: String, steps: [String], icon: String) {
        switch section {
        case .home:
            ("今天从哪里开始", "写什么、怎么写、如何写完，入口都在这里。", [
                "从现实材料发现戏剧性",
                "继续一个正在生长的全本",
                "研究经典并完成原创实验"
            ], "leaf.fill")
        case .seeds:
            ("戏剧化路线", "AI不会把材料直接写成剧本，而是先给你选择。", [
                "保留事实层，标出未知",
                "寻找欲望、阻碍、代价与秘密",
                "提出四种不同类型的改编方向",
                "选择一个方向长成正式项目"
            ], "sparkles.rectangle.stack")
        case .classics:
            ("研究后立刻创作", "经典不是答案，而是一组可以重新实验的叙事功能。", [
                "观察人物为何必须行动",
                "理解对抗力量如何施压",
                "辨认主题如何进入选择",
                "只借功能，创造完全不同的故事"
            ], "theatermasks.fill")
        case .fragments:
            ("喜爱会形成你的私人品味", "收藏不消耗token，好碎片可以跨项目重新连接。", [
                "在AI结果旁点击心形",
                "按类型、关键词和标签检索",
                "记录为什么对这个结果有感觉",
                "让任意碎片长成新的故事项目"
            ], "heart.text.square.fill")
        case .knowledge:
            ("私人理论顾问", "大型书库保留在本机，每次只调用命中的少量片段。", [
                "Markdown 在本机建立索引",
                "Apple 智能压缩作者长文本",
                "DeepSeek只接收必要上下文"
            ], "books.vertical.fill")
        case .templates:
            ("先选择故事的规则", "结构像运动赛制：不同规则会产生不同节奏、压力与观看快感。", [
                "比较模板适合的题材与创作体验",
                "查看每个阶段真正要解决的问题",
                "了解机械套用的风险",
                "选定规则后再让AI逐轮给出具体道路"
            ], "square.grid.3x3.topleft.filled")
        case .journey:
            ("选择让故事前进", "你不需要先知道答案，只需要选择最想继续观看的可能。", [
                "每轮只有一个关键问题",
                "四个选项都包含场面、代价和后续压力",
                "可以换一组，也可以写自己的混合方案",
                "每个大节拍展开一个或多个场景，再将场内小节拍串联为剧本"
            ], "signpost.right.and.left.fill")
        case .compiler, .overview, .ideas, .characters, .relationships, .world, .theme, .structure, .scenes, .screenplay, .versions, .delivery:
            ("故事导师", "进入项目后，导师会根据当前模块给出诊断与下一道命题。", [
                "先判断当前已具备什么",
                "解释最重要的缺口",
                "给出能直接动笔的下一步"
            ], "sparkles")
        }
    }

    var body: some View {
        ZStack {
            StudioCanvas()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: guide.icon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(StudioTheme.mint)
                    Text(guide.title)
                        .font(.system(.title2, design: .serif, weight: .semibold))
                    Text(guide.subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    StudioCard(padding: 16) {
                        VStack(alignment: .leading, spacing: 13) {
                            EyebrowLabel(text: "工作方式")
                            ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(index + 1)")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 22, height: 22)
                                        .background(StudioTheme.accent, in: Circle())
                                    Text(step)
                                        .font(.callout)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    StudioCard(padding: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("节约 Token", systemImage: "apple.intelligence")
                                .font(.headline)
                            Text("整本书不会发送给 DeepSeek。系统只发送当前素材、本地压缩摘要和少量命中证据。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationSplitViewColumnWidth(min: 300, ideal: 350, max: 420)
    }
}
