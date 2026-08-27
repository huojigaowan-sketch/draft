#if DEBUG
import Foundation

/// Network-free regression checks for the narrative compiler. These fail fast
/// during Debug launch if an L0/L1 invariant or Patch boundary regresses.
@MainActor
enum NSIRInvariantChecks {
    static func run() {
        let projectID = UUID()
        let characterID = UUID()
        var document = CompilerWorkspaceDocument.empty(projectID: projectID)
        let proposition = NarrativeCompilerEngine.formalize(
            kind: .emotion,
            text: "让她嫉妒，但她绝不能承认自己喜欢他。",
            characterIDs: [characterID],
            revision: 1
        )
        precondition(proposition.status == .locked, "Author confirmation must create an L0 lock.")
        precondition(!proposition.forbiddenOutcomes.isEmpty, "Explicit prohibitions must be extracted.")
        document.propositions.append(proposition)
        document.revision = 1

        let question = NarrativeCompilerEngine.nextQuestion(for: proposition)
        precondition(question?.variable == "珍视对象", "Information gain must prioritize the structural variable.")

        let candidates = NarrativeCompilerEngine.localCandidates(
            proposition: proposition,
            answer: "男主只对某人展示的脆弱",
            characterNames: ["她", "男主"],
            revision: document.revision
        )
        precondition(candidates.count == 3, "A vertical slice must retain three structural candidates.")
        precondition(
            Set(candidates.compactMap { $0.transitions.dropFirst().first?.tactic.verb }).count == 3,
            "Candidates must differ by tactic, not wording alone."
        )
        precondition(candidates.allSatisfy { !$0.transitions.isEmpty }, "Every path needs executable transitions.")
        precondition(candidates.allSatisfy { $0.transitions.allSatisfy(\.isEffective) }, "Every transition must change state.")

        let selected = candidates[0]
        let report = NarrativeValidationEngine.validate(patch: selected.patch, against: document)
        precondition(report.valid, "A coherent candidate should pass deterministic validation.")
        guard let committed = NarrativeValidationEngine.applying(
            selected.patch,
            validation: report,
            to: document,
            trace: selected.trace
        ) else {
            preconditionFailure("A valid staged Patch must be committable.")
        }
        precondition(committed.revision == 2, "Commit must advance the canonical revision once.")
        precondition(committed.propositions.contains { $0.id == proposition.id }, "Commit must preserve the author axiom.")
        precondition(committed.transitions.count == 3, "The chosen path must commit its transition graph.")
        precondition(committed.obligations.count == 1, "Consequences must become auditable obligations.")

        let expectedOrdinals = SceneMappingEngine.nsirTransitionOrdinals(
            in: committed
        )
        precondition(
            committed.transitions.enumerated().allSatisfy {
                expectedOrdinals[$0.element.id] == $0.offset + 1
            },
            "Committed NSIR transitions must produce stable one-based scene ordinals."
        )

        let sceneProject = StoryProject(
            id: projectID,
            title: "NSIR scene invariant"
        )
        sceneProject.nsirWorkspace = committed
        let legacyOrdinalContracts = committed.transitions.enumerated().map { offset, transition in
            let contract = SceneContract(
                id: transition.id,
                sceneIndex: offset + 1,
                stageSceneOrdinal: 1,
                scopeTitle: transition.title,
                scopePurpose: transition.intention
            )
            contract.sourceKindRawValue = SceneContractSourceKind.nsirTransition.rawValue
            contract.project = sceneProject
            return contract
        }
        sceneProject.sceneContracts = legacyOrdinalContracts
        precondition(
            SceneMappingEngine.repairNSIRTransitionOrdering(
                in: sceneProject,
                document: committed
            ),
            "Legacy NSIR scene ordinals must be repaired."
        )
        precondition(
            legacyOrdinalContracts.map(\.stageSceneOrdinal) == [1, 2, 3],
            "NSIR scene ordinal repair must follow the canonical transition order."
        )
        precondition(
            !SceneMappingEngine.repairNSIRTransitionOrdering(
                in: sceneProject,
                document: committed
            ),
            "NSIR scene ordinal repair must be idempotent."
        )
        guard let secondContract = legacyOrdinalContracts.dropFirst().first,
              let source = try? SceneChoiceEngine.sourceContext(
                  for: secondContract,
                  project: sceneProject
              ) else {
            preconditionFailure("A committed NSIR transition must resolve as a scene source.")
        }
        precondition(
            source.kind == .nsirTransition
                && source.promptBlock.contains(secondContract.scopeTitle),
            "Scene generation must consume the committed NSIR transition context."
        )

        let stale = NarrativeValidationEngine.validate(patch: selected.patch, against: committed)
        precondition(!stale.valid, "A stale Patch must never apply to a newer revision.")

        let leak = DramaticTransition(
            title: "无来源地知道秘密",
            actor: characterID,
            actorName: "她",
            intention: "利用秘密",
            tactic: Tactic(verb: "揭穿", method: "直接说出", concealment: ""),
            resistance: ["对方否认"],
            effects: [
                StateMutation(
                    dimension: .belief,
                    subject: "秘密",
                    holderID: characterID,
                    beforeValue: "未知",
                    afterValue: "已经知道",
                    truthStatus: .fact
                )
            ],
            provenance: Provenance(
                source: "invariant",
                model: "none",
                sourcePropositionIDs: [proposition.id],
                generatedAt: .now
            ),
            confidence: AnalysisConfidence(value: 1, basis: "invariant")
        )
        let leakPatch = StoryPatch(
            id: UUID(),
            baseRevision: committed.revision,
            title: "knowledge leak",
            operations: [.addTransition(leak)],
            createdAt: .now,
            generatedBy: ModelExecutionRecord(
                provider: "invariant",
                model: "none",
                profile: "AuditProfile",
                contextSummary: "test",
                createdAt: .now
            )
        )
        let leakReport = NarrativeValidationEngine.validate(patch: leakPatch, against: committed)
        precondition(
            leakReport.issues.contains { $0.kind == .knowledgeLeak && $0.severity == .error },
            "Knowledge without a source must be blocked at L1."
        )

        precondition(
            ScreenplayElementStyleDefinition.defaultStyles.contains {
                $0.id == ScreenplayElementStyleID.action
                    && !$0.nextStyleID.isEmpty
            },
            "Final Draft element flow must remain configured."
        )
        precondition(
            FountainReturnPolicy.action(
                hasMarkedText: false,
                selectionLength: 0,
                paragraphIsEmpty: false,
                cursorAtParagraphEnd: true
            ) == .insertNextElement,
            "The first Return must follow the configured element flow."
        )
        precondition(
            FountainReturnPolicy.action(
                hasMarkedText: false,
                selectionLength: 0,
                paragraphIsEmpty: true,
                cursorAtParagraphEnd: true
            ) == .showElementMenu,
            "The second Return on the empty element must open the chooser."
        )
        precondition(
            FountainParser.localizedSceneHeading("外景·村庄广场·白天")
                == "外. 村庄广场 - 白天",
            "Chinese middle-dot scene headings must remain scene boundaries."
        )
        precondition(
            FountainCursorContext.action.elementName == "动作",
            "SwiftUI editor chrome must have a nonempty cursor element before the first AppKit callback."
        )
        if var unnamedAction = ScreenplayElementStyleDefinition.defaultStyle(
            id: ScreenplayElementStyleID.action
        ) {
            unnamedAction.name = ""
            precondition(
                unnamedAction.displayName == "动作",
                "An empty editable style name must never blank the live element indicator."
            )
        } else {
            preconditionFailure("The built-in Action style must exist.")
        }

        let legacyPageFlow = "内. 旧宅 - 夜\n\n林夏关上门。\n\n===\n\n外. 河岸 - 日\n\n周野跑向渡口。"
        let standardPageFlow = FountainParser.standardizingSceneFlow(
            in: legacyPageFlow
        )
        precondition(
            !standardPageFlow.contains("===")
                && FountainParser.scenes(in: standardPageFlow).count == 2,
            "Professional screenplay flow must not force every scene onto a new page."
        )
        let finalDraftXML = FinalDraftXMLExporter.xml(
            title: "A&B",
            screenplayText: "内. 旧宅 - 夜\n\n林夏按下开关。\n\n@林夏\n别动。"
        )
        precondition(
            finalDraftXML.contains("<FinalDraft")
                && finalDraftXML.contains("Type=\"Scene Heading\"")
                && finalDraftXML.contains("Type=\"Character\"")
                && finalDraftXML.contains("A&amp;B"),
            "FDX delivery must preserve screenplay elements and XML escaping."
        )

        let cursorFixture = "内. 旧宅 - 夜\n\n林夏推开门。\n\n@林夏\n别动。"
        let cursorFixtureValue = cursorFixture as NSString
        let actionCaret = cursorFixtureValue.range(of: "推开门").location
        let characterCaret = cursorFixtureValue.range(of: "@林夏").location
        precondition(
            FountainParser.paragraph(
                atUTF16Location: actionCaret,
                in: cursorFixture
            )?.inferredType == .action,
            "The insertion caret must resolve the Action paragraph it is inside."
        )
        precondition(
            FountainParser.paragraph(
                atUTF16Location: characterCaret,
                in: cursorFixture
            )?.inferredType == .character,
            "Moving the insertion caret must immediately resolve the new paragraph element."
        )

        let candidateSource = "内. 旧宅 - 夜\n\n旧动作。"
        let candidateFingerprint = ScreenplayDraftOptionPolicy.fingerprint(
            candidateSource
        )
        let candidateOptions = [
            ScreenplaySceneDraftOption(
                title: "以物件施压",
                approach: "通过录音机的可见操作推进对抗",
                fountainText: "内. 旧宅 - 夜\n\n林夏按下录音机。",
                scenePurpose: "逼迫对手回应",
                emotionalTurn: "试探转为对抗",
                beatSummary: ["按下录音"],
                continuityWarnings: [],
                choicesForAuthor: [],
                modeRawValue: ScreenplayGenerationMode.draft.rawValue,
                sourceSceneFingerprint: candidateFingerprint
            ),
            ScreenplaySceneDraftOption(
                title: "以沉默施压",
                approach: "通过人物拒绝回答和空间停顿推进对抗",
                fountainText: "内. 旧宅 - 夜\n\n林夏堵住门口，一言不发。",
                scenePurpose: "逼迫对手回应",
                emotionalTurn: "克制转为威胁",
                beatSummary: ["堵住出口"],
                continuityWarnings: [],
                choicesForAuthor: [],
                modeRawValue: ScreenplayGenerationMode.draft.rawValue,
                sourceSceneFingerprint: candidateFingerprint
            ),
            ScreenplaySceneDraftOption(
                title: "以假撤退施压",
                approach: "通过离场假动作诱使对手主动暴露",
                fountainText: "内. 旧宅 - 夜\n\n林夏转身离开。门锁在身后响了一声。",
                scenePurpose: "逼迫对手回应",
                emotionalTurn: "退让转为诱捕",
                beatSummary: ["假意离场"],
                continuityWarnings: [],
                choicesForAuthor: [],
                modeRawValue: ScreenplayGenerationMode.draft.rawValue,
                sourceSceneFingerprint: candidateFingerprint
            )
        ]
        precondition(
            ScreenplayDraftOptionPolicy.isValidSet(candidateOptions),
            "Every generated screenplay scene must expose exactly three distinct, complete Fountain options."
        )
        let legacyMetadataJSON = Data(
            """
            {
              "sceneIndex": 0,
              "statusRawValue": "待起草",
              "lengthRawValue": "3–5页",
              "emotionalTurn": "",
              "aiNote": ""
            }
            """.utf8
        )
        let decodedLegacyMetadata = try? JSONDecoder().decode(
            ScreenplaySceneMetadata.self,
            from: legacyMetadataJSON
        )
        precondition(
            decodedLegacyMetadata?.screenplayDraftOptions == nil
                && decodedLegacyMetadata?.selectedScreenplayDraftOptionID == nil,
            "Existing screenplay metadata must decode before any AI candidate fields exist."
        )
        let partialCandidateJSON = Data(
            """
            {
              "title": "旧候选",
              "fountainText": "内. 旧宅 - 夜\\n\\n旧动作。"
            }
            """.utf8
        )
        let decodedPartialCandidate = try? JSONDecoder().decode(
            ScreenplaySceneDraftOption.self,
            from: partialCandidateJSON
        )
        precondition(
            decodedPartialCandidate?.title == "旧候选"
                && !(decodedPartialCandidate?.approach ?? "").isEmpty,
            "A partial legacy AI candidate must not invalidate all screenplay metadata."
        )
        let candidateScreenplay = candidateSource
            + "\n\n===\n\n外. 河岸 - 夜\n\n周野跑向渡口。"
        guard let selectedCandidateText = ScreenplayDraftOptionPolicy.applying(
            candidateOptions[1],
            to: candidateScreenplay,
            at: 0
        ) else {
            preconditionFailure("A valid screenplay candidate must be selectable.")
        }
        let selectedCandidateScenes = FountainParser.scenes(
            in: selectedCandidateText
        )
        precondition(
            selectedCandidateScenes.count == 2
                && selectedCandidateScenes[0].text.contains("堵住门口")
                && selectedCandidateScenes[1].text.contains("跑向渡口"),
            "Selecting one AI option must replace only its target scene."
        )

        let validElementIDs = Set(
            ScreenplayElementStyleDefinition.defaultStyles.map(\.id)
        )
        let emptyParagraph = FountainParser.paragraphs(in: "")[0]
        let pendingSceneHeading = ScreenplayParagraphElementAssignment(
            paragraphIndex: 0,
            elementStyleID: ScreenplayElementStyleID.sceneHeading,
            textFingerprint: ""
        )
        let preservedEmptyAssignment =
            ScreenplayParagraphAssignmentReconciler.reconcile(
                paragraphs: [emptyParagraph],
                previous: [pendingSceneHeading],
                attributedStyleIDs: [:],
                validStyleIDs: validElementIDs
            )
        precondition(
            preservedEmptyAssignment.first?.elementStyleID
                == ScreenplayElementStyleID.sceneHeading,
            "An explicit element selected on an empty paragraph must survive typing."
        )

        let characterLikeParagraph = FountainParser.paragraphs(in: "林夏")[0]
        precondition(
            characterLikeParagraph.inferredType == .character,
            "The regression fixture must be character-like to exercise inference drift."
        )
        let preservedAction = ScreenplayParagraphAssignmentReconciler.reconcile(
            paragraphs: [characterLikeParagraph],
            previous: [],
            attributedStyleIDs: [0: ScreenplayElementStyleID.action],
            validStyleIDs: validElementIDs
        )
        precondition(
            preservedAction.first?.elementStyleID == ScreenplayElementStyleID.action,
            "An explicit Action must not drift to Character when its text looks like a cue."
        )
        let shiftedParagraphs = FountainParser.paragraphs(
            in: "新插入的动作。\n\n林夏"
        )
        let shiftedCharacterIndex = shiftedParagraphs.last!.index
        let shiftedAction = ScreenplayParagraphAssignmentReconciler.reconcile(
            paragraphs: shiftedParagraphs,
            previous: preservedAction,
            attributedStyleIDs: [
                shiftedCharacterIndex: ScreenplayElementStyleID.action
            ],
            validStyleIDs: validElementIDs
        )
        precondition(
            shiftedAction.contains {
                $0.paragraphIndex == shiftedCharacterIndex
                    && $0.elementStyleID == ScreenplayElementStyleID.action
            },
            "TextKit markers must carry explicit elements when earlier paragraphs are inserted."
        )

        let projectionProject = StoryProject(title: "正文汇聚回归")
        let projectionContract = SceneContract(
            sceneIndex: 1,
            structureStageIndex: 0,
            scopeTitle: "旧宅会面",
            scopePurpose: "逼迫林夏承认线索",
            scopeEntryState: "林夏仍在回避",
            scopeExitState: "林夏决定追查",
            heading: "内. 旧宅 - 夜",
            pointOfView: "林夏",
            characterGoal: "拿到失踪案线索",
            obstacle: "周野拒绝交出录音",
            turn: "录音里出现林夏自己的声音",
            outcome: "林夏带走录音",
            nextPressure: "周野开始追赶"
        )
        projectionContract.project = projectionProject
        projectionProject.sceneContracts.append(projectionContract)
        let secondProjectionContract = SceneContract(
            sceneIndex: 2,
            structureStageIndex: 0,
            scopeTitle: "河岸追逐",
            scopePurpose: "让追查付出即时代价",
            heading: "外景·河岸·夜",
            pointOfView: "林夏",
            characterGoal: "摆脱周野",
            obstacle: "出口被封锁",
            turn: "林夏跳上渡船",
            outcome: "两人被河面隔开",
            nextPressure: "录音开始自动播放"
        )
        secondProjectionContract.project = projectionProject
        projectionProject.sceneContracts.append(secondProjectionContract)
        projectionProject.screenplayText = "内. 未定地点 - 日\n\n"
        let projectionState = ScreenplayWorkspaceState(
            projectID: projectionProject.id
        )
        let initialProjection = ScreenplayProjectionEngine.synchronize(
            project: projectionProject,
            state: projectionState
        )
        precondition(
            initialProjection.changed
                && initialProjection.text.contains("拿到失踪案线索")
                && !initialProjection.text.contains("写下一个"),
            "The Final Draft surface must be populated from upstream scene work."
        )

        let initiallyProjectedScenes = FountainParser.scenes(
            in: initialProjection.text
        )
        precondition(
            initiallyProjectedScenes.count == 2,
            "Every localized upstream heading must produce one parsed scene."
        )
        projectionProject.screenplayText = initialProjection.text
            + "\n\n===\n\n"
            + initiallyProjectedScenes[1].text
        let repairedDuplicate = ScreenplayProjectionEngine.synchronize(
            project: projectionProject,
            state: projectionState
        )
        precondition(
            repairedDuplicate.changed
                && FountainParser.scenes(in: repairedDuplicate.text).count == 2,
            "Exact duplicate legacy projections must be repaired once."
        )

        projectionProject.screenplayText = repairedDuplicate.text
        projectionContract.obstacle = "周野销毁了录音"
        let safeUpdate = ScreenplayProjectionEngine.synchronize(
            project: projectionProject,
            state: projectionState
        )
        precondition(
            safeUpdate.changed && safeUpdate.text.contains("周野销毁了录音"),
            "Untouched projections must follow upstream scene changes."
        )

        let editedFirstScene = FountainParser.scenes(in: safeUpdate.text)[0].text
            + "\n\n林夏把录音藏进外套。"
        projectionProject.screenplayText = FountainParser.replacingScene(
            at: 0,
            in: safeUpdate.text,
            with: editedFirstScene
        )
        projectionContract.turn = "警笛突然逼近"
        let protectedAuthorEdit = ScreenplayProjectionEngine.synchronize(
            project: projectionProject,
            state: projectionState
        )
        precondition(
            !protectedAuthorEdit.changed
                && protectedAuthorEdit.pendingContractIDs.contains(
                    projectionContract.id
                ),
            "An author-edited scene must not be silently overwritten upstream."
        )

        let forcedRemap = ScreenplayProjectionEngine.synchronize(
            project: projectionProject,
            state: projectionState,
            forceContractIDs: [projectionContract.id]
        )
        let protectedSecondScene = FountainParser.scenes(
            in: protectedAuthorEdit.text
        )[1].text
        let forcedSecondScene = FountainParser.scenes(in: forcedRemap.text)[1].text
        precondition(
            forcedRemap.changed
                && forcedRemap.text.contains("警笛突然逼近")
                && !forcedRemap.text.contains("林夏把录音藏进外套")
                && forcedSecondScene == protectedSecondScene,
            "Explicit remapping must replace only the requested scene."
        )
    }
}
#endif
