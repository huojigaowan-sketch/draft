import SwiftUI

/// The new app-wide creation hierarchy.  All paths begin in the narrative
/// compiler; the Final Draft editor remains the authoritative writing surface.
struct StoryHierarchyBar: View {
    let selection: WorkspaceSection
    let onSelect: (WorkspaceSection) -> Void
    var compact = false

    private let levels: [(section: WorkspaceSection, title: String, icon: String)] = [
        (.compiler, "叙事编译台", "function"),
        (.characters, "故事语义", "person.2.fill"),
        (.scenes, "场景工作台", "rectangle.stack.fill"),
        (.screenplay, "Final Draft 正文", "text.book.closed.fill")
    ]

    private var selectedIndex: Int {
        levels.firstIndex { $0.section == selection } ?? 0
    }

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: compact ? 8 : 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }

                Button {
                    onSelect(level.section)
                } label: {
                    HStack(spacing: compact ? 6 : 8) {
                        Text("\(index + 1)")
                            .font(.system(size: compact ? 10 : 11.5, weight: .bold, design: .monospaced))
                            .frame(width: compact ? 19 : 24, height: compact ? 19 : 24)
                            .background(
                                index == selectedIndex
                                    ? StudioTheme.accent
                                    : index < selectedIndex
                                        ? StudioTheme.mint.opacity(0.18)
                                        : Color.primary.opacity(0.07),
                                in: Circle()
                            )
                            .foregroundStyle(
                                index == selectedIndex
                                    ? Color.white
                                    : index < selectedIndex
                                        ? StudioTheme.mint
                                        : Color.secondary
                            )
                        Image(systemName: level.icon)
                            .font(.system(size: compact ? 10 : 12, weight: .semibold))
                        Text(level.title)
                            .font(.system(size: compact ? 11.5 : 13.5, weight: index == selectedIndex ? .semibold : .medium))
                    }
                    .foregroundStyle(index == selectedIndex ? .primary : .secondary)
                    .padding(.horizontal, compact ? 8 : 12)
                    .padding(.vertical, compact ? 6 : 9)
                    .background(
                        index == selectedIndex ? Color.primary.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                }
                .buttonStyle(.plain)
                .help("第 \(index + 1) 层 · \(level.title)")
            }
        }
        .padding(compact ? 3 : 4)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.055))
        }
    }
}

struct CoreWorkspaceSwitcher: View {
    let selection: WorkspaceSection
    let onSelect: (WorkspaceSection) -> Void

    var body: some View {
        StoryHierarchyBar(selection: selection, onSelect: onSelect)
    }
}
