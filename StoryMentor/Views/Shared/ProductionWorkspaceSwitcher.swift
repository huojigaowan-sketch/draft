import SwiftUI

/// The single navigation surface for the production half of a project.
/// Each step owns one responsibility and exposes no duplicate commands.
struct ProductionWorkspaceSwitcher: View {
    let selection: WorkspaceSection
    let onSelect: (WorkspaceSection) -> Void

    private let sections: [WorkspaceSection] = [
        .scenes, .screenplay, .versions, .delivery
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }

                Button {
                    onSelect(section)
                } label: {
                    HStack(spacing: 6) {
                        Text("\(index + 1)")
                            .font(.caption2.monospacedDigit().weight(.bold))
                            .frame(width: 18, height: 18)
                            .background(
                                selection == section
                                    ? StudioTheme.accent
                                    : Color.primary.opacity(0.08),
                                in: Circle()
                            )
                            .foregroundStyle(selection == section ? Color.white : .secondary)
                        Text(section.rawValue)
                            .font(.caption.weight(selection == section ? .semibold : .medium))
                    }
                    .foregroundStyle(selection == section ? .primary : .secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(
                        selection == section
                            ? Color.primary.opacity(0.08)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(Color.primary.opacity(0.06))
        }
    }
}
