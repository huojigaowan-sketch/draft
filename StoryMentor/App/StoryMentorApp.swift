import SwiftData
import SwiftUI

@main
struct StoryMentorApp: App {
    @State private var aiSettings = AISettingsStore()

    init() {
        #if DEBUG
        DramaticSemanticInvariantChecks.run()
        NSIRInvariantChecks.run()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            WorkspaceView()
                .environment(aiSettings)
                .debugPreviewDataIfRequested()
        }
        .modelContainer(
            for: [
                StoryProject.self,
                StorySeed.self,
                StoryDecision.self,
                StoryCharacter.self,
                AnalysisReport.self,
                CreativeTask.self,
                StoryFragment.self,
                ProjectArtifact.self,
                KnowledgeDocument.self,
                KnowledgeChunk.self,
                ResearchDossier.self,
                ScreenplayWorkspaceState.self,
                AuthorIdeaRecord.self,
                StoryFactRecord.self,
                StoryChangeSet.self,
                StoryCompilerIssue.self,
                SceneContract.self,
                StoryRevisionSnapshot.self,
                DramaticUpdateRecord.self,
                NarrativeProjectionRecord.self
            ]
        )
        .defaultSize(width: 1_420, height: 900)

        Settings {
            AISettingsView()
                .environment(aiSettings)
        }
    }
}
