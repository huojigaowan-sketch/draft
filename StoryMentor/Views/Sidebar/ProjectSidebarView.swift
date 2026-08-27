import AppKit
import SwiftUI

struct ProjectSidebarView: View {
    let projects: [StoryProject]
    @Binding var selectedProjectID: UUID?
    @Binding var selectedSection: WorkspaceSection
    let onCreateProject: () -> Void
    let onRequestDelete: (StoryProject) -> Void

    @State private var expandedWorkflowID = "compiler"

    private var selectedProject: StoryProject? {
        guard let selectedProjectID else { return nil }
        return projects.first { $0.id == selectedProjectID }
    }

    private let workflowGroups = [
        SidebarWorkflowGroup(
            id: "compiler",
            number: "01",
            title: "叙事编译",
            subtitle: "作者命题、状态与约束",
            sections: [.compiler]
        ),
        SidebarWorkflowGroup(
            id: "semantics",
            number: "02",
            title: "故事语义",
            subtitle: "人物、关系、世界与主题",
            sections: [.characters, .relationships, .world, .theme]
        ),
        SidebarWorkflowGroup(
            id: "production",
            number: "03",
            title: "写作与交付",
            subtitle: "场景、Final Draft 正文、版本与检查",
            sections: [.scenes, .screenplay, .versions, .delivery]
        )
    ]

    var body: some View {
        ZStack {
            sidebarBackground

            VStack(spacing: 0) {
                brandHeader

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        discoverySection
                        currentStorySection

                        if selectedProject != nil {
                            workflowSection
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 18)
                }

                footer
            }
        }
        .navigationSplitViewColumnWidth(min: 250, ideal: 276, max: 310)
        .onAppear {
            expandWorkflow(containing: selectedSection, animated: false)
        }
        .onChange(of: selectedSection) { _, section in
            expandWorkflow(containing: section, animated: true)
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [StudioTheme.accent, StudioTheme.mint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "leaf.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)
            .shadow(color: StudioTheme.accent.opacity(0.22), radius: 10, y: 5)

            VStack(alignment: .leading, spacing: 2) {
                Text("故事导师")
                    .font(.system(.headline, design: .serif, weight: .semibold))
                Text("STORY MENTOR")
                    .font(.caption2.weight(.medium))
                    .tracking(0.8)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Button(action: onCreateProject) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.055), in: Circle())
            }
            .buttonStyle(.plain)
            .help("新建故事")
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private var discoverySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sidebarTitle("项目与资源")

            destinationButton(.home, prominent: true)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                ForEach(WorkspaceSection.discoverySections.filter { $0 != .home }) { section in
                    destinationButton(section, prominent: false)
                }
            }
        }
    }

    private var currentStorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sidebarTitle("当前故事")
                Spacer()
                Button(action: onCreateProject) {
                    Label("新建", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(StudioTheme.accent)
            }

            if let project = selectedProject {
                currentStoryCard(project)
            } else {
                Button(action: onCreateProject) {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("种下第一个故事", systemImage: "leaf.circle.fill")
                            .font(.callout.weight(.semibold))
                        Text("从一个人物、一条新闻或一句话开始。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(15)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 15))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(
                                StudioTheme.accent.opacity(0.30),
                                style: StrokeStyle(lineWidth: 1, dash: [5])
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func currentStoryCard(_ project: StoryProject) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                Button {
                    selectedSection = .compiler
                } label: {
                    HStack(spacing: 11) {
                        Text(project.title.prefix(1).uppercased())
                            .font(.system(.headline, design: .serif, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(
                                LinearGradient(
                                    colors: [StudioTheme.accent, StudioTheme.mint],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: RoundedRectangle(cornerRadius: 11)
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(project.title)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(project.genre == .unselected ? "等待选择类型" : project.genre.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                Menu {
                    ForEach(projects) { candidate in
                        Button {
                            selectedProjectID = candidate.id
                            selectedSection = .compiler
                        } label: {
                            Label(
                                candidate.title,
                                systemImage: candidate.id == project.id
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                        }
                    }
                    Divider()
                    Button("新建故事", systemImage: "plus", action: onCreateProject)
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.045), in: Circle())
                }
                .menuStyle(.borderlessButton)
            }

            VStack(spacing: 6) {
                HStack {
                    Text(
                        project.hasSelectedStructureTemplate
                            ? project.structureTemplate.name
                            : "尚未选择结构"
                    )
                    Spacer()
                    Text(project.completionFraction, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.07))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [StudioTheme.accent, StudioTheme.mint],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * project.completionFraction)
                    }
                }
                .frame(height: 5)
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(StudioTheme.accent.opacity(0.16), lineWidth: 1)
        }
        .contextMenu {
            Button("删除当前故事", systemImage: "trash", role: .destructive) {
                onRequestDelete(project)
            }
        }
    }

    private var workflowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sidebarTitle("创作路线")

            VStack(spacing: 8) {
                ForEach(workflowGroups) { group in
                    workflowGroup(group)
                }
            }
        }
    }

    private func workflowGroup(_ group: SidebarWorkflowGroup) -> some View {
        let isExpanded = expandedWorkflowID == group.id
        let containsSelection = group.sections.contains(selectedSection)

        return VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.24)) {
                    expandedWorkflowID = isExpanded ? "" : group.id
                }
            } label: {
                HStack(spacing: 11) {
                    Text(group.number)
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(
                            containsSelection
                                ? StudioTheme.accent
                                : Color.secondary.opacity(0.55)
                        )
                        .frame(width: 25, height: 25)
                        .background(
                            containsSelection
                                ? StudioTheme.accent.opacity(0.11)
                                : Color.primary.opacity(0.04),
                            in: RoundedRectangle(cornerRadius: 8)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(group.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 3) {
                    ForEach(group.sections) { section in
                        moduleRow(section)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            containsSelection
                ? StudioTheme.accent.opacity(0.045)
                : Color.primary.opacity(0.018),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    containsSelection
                        ? StudioTheme.accent.opacity(0.13)
                        : Color.primary.opacity(0.035)
                )
        }
    }

    private func moduleRow(_ section: WorkspaceSection) -> some View {
        let isSelected = selectedSection == section
        let isReady = moduleIsReady(section)

        return Button {
            selectedSection = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? StudioTheme.accent : .secondary)
                    .frame(width: 20)

                Text(section.rawValue)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer()

                if isReady {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(StudioTheme.mint)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.quaternary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                isSelected ? StudioTheme.accent.opacity(0.10) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(StudioTheme.accent)
                        .frame(width: 3, height: 18)
                        .offset(x: -1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func destinationButton(
        _ section: WorkspaceSection,
        prominent: Bool
    ) -> some View {
        let isSelected = selectedSection == section

        return Button {
            selectedSection = section
        } label: {
            if prominent {
                HStack(spacing: 11) {
                    Image(systemName: section.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : StudioTheme.accent)
                        .frame(width: 32, height: 32)
                        .background(
                            isSelected ? StudioTheme.accent : StudioTheme.accent.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("所有项目")
                            .font(.callout.weight(.semibold))
                        Text("浏览项目，或新建一部剧本")
                            .font(.caption2)
                            .foregroundStyle(isSelected ? Color.white.opacity(0.78) : .secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                }
                .padding(10)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(
                    isSelected
                        ? LinearGradient(
                            colors: [StudioTheme.accent, StudioTheme.accent.opacity(0.78)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        : LinearGradient(
                            colors: [Color.primary.opacity(0.035), Color.primary.opacity(0.02)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                    in: RoundedRectangle(cornerRadius: 13)
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: section.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : StudioTheme.accent)
                    Text(section.rawValue)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(destinationHint(section))
                        .font(.system(size: 9.5))
                        .foregroundStyle(
                            isSelected
                                ? Color.white.opacity(0.72)
                                : Color.secondary.opacity(0.55)
                        )
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                .padding(10)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(
                    isSelected ? StudioTheme.accent : Color.primary.opacity(0.028),
                    in: RoundedRectangle(cornerRadius: 13)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(
                            isSelected ? Color.clear : Color.primary.opacity(0.045),
                            lineWidth: 1
                        )
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func destinationHint(_ section: WorkspaceSection) -> String {
        switch section {
        case .seeds: "发现戏剧性"
        case .classics: "拆解好故事"
        case .fragments: "保存喜欢"
        case .knowledge: "私人书库"
        default: ""
        }
    }

    private func moduleIsReady(_ section: WorkspaceSection) -> Bool {
        guard let project = selectedProject else { return false }
        switch section {
        case .compiler:
            return true
        case .characters:
            return !project.characters.isEmpty
        case .relationships:
            return !project.characterRelationships.isEmpty
        case .world:
            return !project.worldText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .theme:
            return !project.themeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .scenes:
            return !project.scenesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .screenplay, .versions, .delivery:
            return !project.screenplayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .home, .seeds, .classics, .fragments, .knowledge,
             .overview, .ideas, .templates, .journey, .structure:
            return false
        }
    }

    private func sidebarTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 3)
    }

    private var footer: some View {
        HStack {
            Label("仅保存在这台 Mac", systemImage: "lock.shield.fill")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            SettingsLink {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.045), in: Circle())
            }
            .buttonStyle(.plain)
            .help("AI 与隐私设置")
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.045))
                .frame(height: 1)
        }
    }

    private var sidebarBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: [
                    StudioTheme.accent.opacity(0.075),
                    Color.clear,
                    StudioTheme.warm.opacity(0.035)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(StudioTheme.mint.opacity(0.07))
                .frame(width: 240, height: 240)
                .blur(radius: 70)
                .offset(x: -120, y: -310)
        }
        .ignoresSafeArea()
    }

    private func expandWorkflow(containing section: WorkspaceSection, animated: Bool) {
        guard let group = workflowGroups.first(where: { $0.sections.contains(section) }) else {
            return
        }
        if animated {
            withAnimation(.snappy(duration: 0.24)) {
                expandedWorkflowID = group.id
            }
        } else {
            expandedWorkflowID = group.id
        }
    }
}

private struct SidebarWorkflowGroup: Identifiable {
    let id: String
    let number: String
    let title: String
    let subtitle: String
    let sections: [WorkspaceSection]
}
