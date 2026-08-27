import SwiftUI

struct RealityStoryHubView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case research = "深挖现实"
        case dramatize = "故事路线"

        var id: String { rawValue }
    }

    let onCreateProject: (StorySeed, AdaptationDirection) -> Void

    @State private var mode = Mode.research
    @State private var seedToOpenID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("工作阶段", selection: $mode) {
                    Label("深挖现实", systemImage: "globe.desk.fill")
                        .tag(Mode.research)
                    Label("故事路线", systemImage: "sparkles.rectangle.stack")
                        .tag(Mode.dramatize)
                }
                .pickerStyle(.segmented)
                .frame(width: 310)

                Spacer()

                Text(
                    mode == .research
                        ? "资料先变成立体世界，再交给 DeepSeek"
                        : "从有依据的四条路线中选择真正想写的故事"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial)

            Divider()

            switch mode {
            case .research:
                RealityResearchView { seed in
                    seedToOpenID = seed.id
                    mode = .dramatize
                }
            case .dramatize:
                DramaSeedLabView(
                    initialSeedID: seedToOpenID,
                    onCreateProject: onCreateProject
                )
            }
        }
    }
}
