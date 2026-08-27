# Story Mentor

Story Mentor is a native macOS writing workspace for diagnosing story ideas and
turning them into concrete creative assignments. It is designed as an AI mentor,
not an automatic screenplay generator.

## Guided flow is the default production path

The production entry now uses a novice-first guided-flow workspace. It presents
one small creative decision at a time, checks the author's attempt, escalates
help through a fixed scaffold ladder, and deterministically compiles accepted
steps into structure, scene contracts, micro-beats, and Fountain screenplay
text.

The AI is prohibited from returning a whole outline, scene, episode, or
screenplay in this path. Its structured response is limited to a one-step
review, one nudge, a faithful summary, or—at the final support level—one small
editable suggestion for the current step. The full NSIR compiler remains
available as an advanced tool.

See `Documentation/GuidedFlowArchitecture.md` for the state machine, difficulty
model, scaffold ladder, and output boundaries.

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
Guided flow micro-challenge state machine
        |
Story Analysis Engine and deterministic contracts
        |
DeepSeek or SiliconFlow reasoning provider + optional Apple text preprocessing
        |
Story DNA + theory RAG
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
3. Create a project and enter production. The guided-flow workspace asks one
   question at a time and saves only author-confirmed decisions.
4. Import licensed or personally owned PDF writing references in Knowledge.
   PDF text remains local; only retrieved excerpts relevant to a diagnosis are
   included in the model request.
5. DeepSeek is used for one-step semantic review and the final micro-support
   level. Deterministic validation and project progression do not depend on a
   model response.
