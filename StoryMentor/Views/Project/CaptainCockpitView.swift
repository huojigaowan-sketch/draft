import SwiftData
import SwiftUI

@MainActor
struct CaptainCockpitView: View {
  @Environment(\.modelContext) private var modelContext

  @Bindable var project: StoryProject
  let onNavigate: (WorkspaceSection) -> Void

  @State private var persistenceError = ""
  @State private var showingPersistenceError = false

  private var latestCommand: AuthorIdeaRecord? {
    project.authorIdeas
      .filter { !$0.captainOptions.isEmpty }
      .sorted { $0.updatedAt > $1.updatedAt }
      .first
  }

  private var structureProgress: Double {
    guard project.hasSelectedStructureTemplate else { return 0 }
    let stageCount = project.structureTemplate.stages.count
    guard stageCount > 0 else { return 0 }
    return Double(project.resolvedDecisionCount) / Double(stageCount)
  }

  var body: some View {
    ZStack {
      StudioCanvas()

      VStack(spacing: 0) {
        cockpitHeader

        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            if let latestCommand {
              CaptainProposalBoard(project: project, idea: latestCommand)
            }

            ProjectBubbleUniverseView(
              project: project,
              onNavigate: onNavigate
            )
          }
          .padding(.horizontal, 20)
          .padding(.top, 10)
          .padding(.bottom, 24)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .task(id: project.updatedAt) {
      do {
        try StoryCompiler.refresh(project: project, in: modelContext)
      } catch {
        persistenceError = error.localizedDescription
        showingPersistenceError = true
      }
    }
    .alert("无法更新项目诊断", isPresented: $showingPersistenceError) {
      Button("好", role: .cancel) {}
    } message: {
      Text(persistenceError)
    }
  }

  private var cockpitHeader: some View {
    GlassEffectContainer(spacing: 12) {
      VStack(spacing: 10) {
        HStack(spacing: 14) {
          Image(systemName: "scope")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(StudioTheme.mint)
            .frame(width: 46, height: 46)
            .glassEffect(
              .regular.tint(StudioTheme.mint.opacity(0.14)),
              in: .circle
            )

          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
              Text("项目全景")
                .font(.system(size: 28, weight: .semibold, design: .serif))
              PhaseBadge(text: "第 1 层")
            }
            Text(
              "\(project.title) · \(project.isStructureLocked ? project.structureTemplate.name : "结构待锁定")"
            )
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
          }

          Spacer(minLength: 12)

          HStack(spacing: 10) {
            Label(
              project.isStructureLocked ? "结构已固定" : "结构待选择",
              systemImage: project.isStructureLocked ? "lock.fill" : "lock.open"
            )
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(project.isStructureLocked ? StudioTheme.mint : StudioTheme.warm)

            ProgressRing(
              value: project.hasSelectedStructureTemplate
                ? structureProgress
                : project.completionFraction,
              lineWidth: 5,
              diameter: 44
            )
          }
        }

        StoryHierarchyBar(selection: .overview, onSelect: onNavigate)
          .frame(maxWidth: .infinity, alignment: .center)
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 12)
      .modifier(CockpitHeaderSurface())
    }
    .padding(.horizontal, 16)
    .padding(.top, 12)
    .padding(.bottom, 8)
  }
}

private struct CockpitHeaderSurface: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  @ViewBuilder
  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    if reduceTransparency {
      content
        .background(StudioTheme.secondaryCanvas, in: shape)
        .overlay {
          shape.stroke(Color.primary.opacity(0.10), lineWidth: 1)
        }
    } else {
      content.glassEffect(
        .regular.tint(StudioTheme.accent.opacity(0.035)),
        in: shape
      )
    }
  }
}
