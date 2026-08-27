# Story Mentor

Story Mentor is a native macOS writing workspace for diagnosing story ideas and
turning them into concrete creative assignments. It is designed as an AI mentor,
not an automatic screenplay generator.

## Current milestone

Phase 1 establishes the product foundation:

- Native three-column macOS workspace
- SwiftData persistence
- Story project creation and switching
- Character Lab with free-form and structured character fields
- Local readiness checks in the mentor panel
- Data models for future analysis reports and creative tasks

The mentor panel intentionally labels its current output as local structure
checking. DeepSeek, Apple Foundation Models, Story DNA, and RAG are not connected
yet.

## Open the project

Open `编剧台.xcodeproj` in Xcode 27 and run the `StoryMentor` scheme, or use
`./script/build_and_run.sh` to build, install, and launch the latest app.

## Product architecture

```text
SwiftUI workspace
        |
SwiftData story graph
        |
Story Analysis Engine (Phase 2)
        |
DeepSeek or SiliconFlow reasoning provider + optional Apple text preprocessing
        |
Story DNA + theory RAG (later phases)
```

## Unified project database

All story-production data lives in the same SwiftData store. `StoryProject.id`
is the single project UUID shared by its seeds, experiment history, screenplay
workspace, and production assets. New seeds must be created under a project;
experiments inherit that ownership from their seed. The Project Archive is the
single place to switch, rename, inspect, or deliberately delete a complete
project workspace.

## Planned sequence

1. Phase 1: app shell, persistence, project management, Character Lab
2. Phase 2: provider-neutral analysis contracts and deterministic JSON reports
3. Phase 3: DeepSeek and Apple Foundation Models
4. Phase 4: curated Story DNA case library
5. Phase 5: private theory RAG with citations
6. Phase 6: antagonist, world, theme, structure, scene, and screenplay modules

## Using the finished app

1. Open Settings and choose DeepSeek or SiliconFlow. API keys are stored only
   in the macOS Keychain.
2. For SiliconFlow, keep the official base URL
   `https://api.siliconflow.cn/v1`. Saving the API key automatically loads the
   available chat model IDs from `/v1/models?sub_type=chat`; select one from the
   model menu. DeepSeek keeps its original model choices.
3. Create a project, write freely in any module, and run diagnosis from the
   mentor panel.
4. Import licensed or personally owned PDF writing references in Knowledge.
   PDF text remains local; only retrieved excerpts relevant to a diagnosis are
   included in the DeepSeek request.
5. DeepSeek is the primary model for NSIR planning and semantic analysis.
   Optional Apple processing is limited to local text compaction/polish and is
   disabled by default; deterministic validation never depends on either model.
