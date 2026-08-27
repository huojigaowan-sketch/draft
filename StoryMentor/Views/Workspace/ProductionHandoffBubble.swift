import SwiftUI

/// 生产区共享的实验接力气泡。它始终显示上游依据，因此人物、世界、主题、
/// 场景和正文不再像彼此独立的空白工具。
struct ProductionHandoffBubble: View {
    let seed: StorySeed
    let snapshot: StoryCultivationSnapshot
    let section: WorkspaceSection
    @Binding var isExpanded: Bool
    let onNavigate: (WorkspaceSection) -> Void
    let onReturnToLaboratory: () -> Void

    private var crystal: StoryCrystal { snapshot.crystal }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded {
                BubbleWorkspaceConnector(
                    tint: StudioTheme.warm,
                    branchCount: 4,
                    height: 22
                )
                .transition(.opacity)

                relayCards
                    .transition(.move(edge: .top).combined(with: .opacity))

                nextStep
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(isExpanded ? 15 : 11)
        .animatedStoryBubble(
            tint: StudioTheme.warm,
            cornerRadius: isExpanded ? 38 : 28,
            isSelected: isExpanded
        )
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: isExpanded)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(
                    LinearGradient(
                        colors: [StudioTheme.warm, StudioTheme.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("实验结果已接入生产")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Text("\(seed.title) · 第 \(max(snapshot.round, 1)) 轮 · \(snapshot.decisions.count) 次已确认实验")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Label(
                snapshot.evaluation.gaps.isEmpty ? "生产底稿已铺好" : "\(snapshot.evaluation.gaps.count) 项待确认",
                systemImage: snapshot.evaluation.gaps.isEmpty
                    ? "checkmark.seal.fill"
                    : "questionmark.bubble.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(snapshot.evaluation.gaps.isEmpty ? StudioTheme.mint : StudioTheme.warm)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.045), in: Capsule())

            Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                    isExpanded.toggle()
                }
            } label: {
                Label(isExpanded ? "收起依据" : "查看实验依据", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var relayCards: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 190, maximum: 320), spacing: 10)],
            spacing: 10
        ) {
            relayCard(
                title: "故事核心",
                text: crystal.coreIdea,
                icon: "sparkles",
                tint: StudioTheme.warm,
                target: .compiler
            )
            relayCard(
                title: "人物洞察",
                text: crystal.characterInsight,
                icon: "person.crop.circle.fill",
                tint: StudioTheme.sky,
                target: .characters
            )
            relayCard(
                title: "不可两全的冲突",
                text: crystal.conflict,
                icon: "arrow.left.and.right.circle.fill",
                tint: StudioTheme.accent,
                target: .compiler
            )
            relayCard(
                title: "主题假设",
                text: crystal.theme,
                icon: "scope",
                tint: StudioTheme.mint,
                target: .theme
            )
        }
    }

    private func relayCard(
        title: String,
        text: String,
        icon: String,
        tint: Color,
        target: WorkspaceSection
    ) -> some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) {
                onNavigate(target)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(title, systemImage: icon)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                    Spacer()
                    Image(systemName: section == target ? "checkmark.circle.fill" : "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(section == target ? tint : Color.secondary)
                }
                Text(text.storyScienceTrimmed.isEmpty ? "本轮实验尚未明确" : text)
                    .font(.callout)
                    .foregroundStyle(text.storyScienceTrimmed.isEmpty ? .secondary : .primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
            .animatedStoryBubble(
                tint: tint,
                cornerRadius: 28,
                isSelected: section == target
            )
        }
        .buttonStyle(.plain)
    }

    private var nextStep: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Label("生产下一步", systemImage: "arrow.right.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(StudioTheme.warm)
                Text(snapshot.evaluation.nextStep.storyScienceTrimmed.isEmpty
                     ? "继续锁定一条可验证的创作决定"
                     : snapshot.evaluation.nextStep)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button("回到实验室", systemImage: "flask.fill", action: onReturnToLaboratory)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("继续结构推演", systemImage: "function") {
                onNavigate(.compiler)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(StudioTheme.warm)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .animatedStoryBubble(tint: StudioTheme.warm, cornerRadius: 26)
    }
}

struct ProductionSectionBubbleBar: View {
    let selection: WorkspaceSection
    let onSelect: (WorkspaceSection) -> Void

    private let sections: [(WorkspaceSection, String)] = [
        (.compiler, "实验接力"),
        (.characters, "人物"),
        (.relationships, "关系"),
        (.world, "世界"),
        (.theme, "主题"),
        (.scenes, "场景"),
        (.screenplay, "剧本正文"),
        (.versions, "版本"),
        (.delivery, "交付")
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(sections, id: \.0.id) { section, title in
                    Button {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                            onSelect(section)
                        }
                    } label: {
                        Label(title, systemImage: section.systemImage)
                            .font(.caption.weight(selection == section ? .bold : .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                selection == section
                                    ? StudioTheme.accent.opacity(0.16)
                                    : Color.primary.opacity(0.035),
                                in: Capsule()
                            )
                            .foregroundStyle(selection == section ? StudioTheme.accent : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
