# StoryMentor NSIR 1.0 implementation

## Product contract

- The author owns L0 premises. AI may only propose a staged `StoryPatch`.
- `CompilerWorkspaceDocument` is the canonical narrative state; Fountain text
  remains an editable realization and is never silently overwritten.
- DeepSeek is the primary reasoning provider. Apple Foundation Models are
  optional text preprocessing/polish only and do not adjudicate NSIR.
- Deterministic planning, validation, package I/O and the screenplay editor work
  without an AI connection.
- No total story-quality score is generated or shown. Candidate comparison uses
  a multi-objective Pareto vector.

## Implemented blueprint map

| Blueprint capability | Implementation |
| --- | --- |
| W/B/G/R/N/A/I/Q/U/M story state | `StoryState`, `NarrativeStateDimension` |
| Multidimensional relationships | `RelationshipState` with 8 independent axes |
| Minimal dramatic update | `DramaticTransition`, `Condition`, `StateMutation`, partial-order predecessors |
| L0–L5 epistemic rules | `RuleClass`, `RuleCard`, built-in rule library |
| Explainable recommendation | `RecommendationTrace`, evidence, assumptions, tradeoffs, uncertainty |
| AI cannot commit | `StoryPatch` staging, deterministic simulation, explicit author commit |
| Information-gain intake | Eight proposition entries and type-specific `InformationGainQuestion` routing |
| Four proposition compilers | Emotion, trauma, foreshadowing and micro-conflict paths; relationship, reveal, choice and visual entrances use the same typed pipeline |
| Weighted constraint search | `NarrativeConstraintSolver`, hard/soft rules, beam gate and Pareto pruning |
| Minimum-cost repair | `NarrativeValidationEngine.minimumRepairs` |
| Knowledge/causal/obligation audits | Global NSIR audit plus knowledge matrix, partial-order graph and audit console |
| Preference learning | Accepted-vs-rejected `PreferenceComparison` records at author commit |
| Text ↔ semantics | Existing dramatic source anchors migrate through `NSIRLegacyBridge` into `SemanticSourceMap`; semantic drift remains author-decided |
| Portable project package | Finder-visible `.storyproject` package with manifest, SHA-256, canonical JSON/JSONL, Fountain draft and derived maps |
| Native macOS workbench | Global `NavigationSplitView`; narrative navigator, six central modes, proof inspector and bottom audit console |
| Final Draft editor compatibility | Existing `NSTextView`/TextKit editor, styles, shortcuts, Fountain import/export and Return flow retained |

## Return-flow invariant

`FountainReturnPolicy` preserves the original editor behavior:

1. Return at the end of a non-empty screenplay element inserts a newline and
   applies that element's configured `nextStyleID`.
2. Return again on the now-empty element opens the complete screenplay-element
   chooser.
3. Marked-text input, selection replacement and Return inside a paragraph remain
   under standard `NSTextView` behavior.

The policy and all NSIR L0/L1 contracts run as network-free Debug launch
invariants in `NSIRInvariantChecks`.

## Verification

- Debug: `xcodebuild ... -configuration Debug ... build` — passed.
- Release: `xcodebuild ... -configuration Release ... build` — passed.
- Debug app launch — remained alive; all semantic, NSIR and editor invariants passed.
- The only build warning is Xcode's expected App Intents metadata message because
  the application does not link AppIntents.
