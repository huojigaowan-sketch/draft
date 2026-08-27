import Foundation

/// One-way bootstrap from the existing StoryMentor graph into NSIR. It never
/// rewrites screenplay text or deletes legacy records; stable IDs make it safe
/// to run whenever an older project first opens the compiler.
@MainActor
enum NSIRLegacyBridge {
    static func bootstrap(
        project: StoryProject,
        document: CompilerWorkspaceDocument
    ) -> CompilerWorkspaceDocument {
        var result = document
        var changed = false

        if result.state.relationships.isEmpty, !project.characterRelationships.isEmpty {
            result.state.relationships = project.characterRelationships.map(relationshipState)
            changed = true
        }

        let existingFactIDs = Set(result.propositions.map(\.id))
        for fact in project.canonicalFacts where fact.isLockedByAuthor && !existingFactIDs.contains(fact.id) {
            result.propositions.append(
                Proposition(
                    id: fact.id,
                    kind: fact.kind == .relationship ? .relationship : .imageAction,
                    originalText: "\(fact.subject) \(fact.predicate) \(fact.value)",
                    formalStatement: "CanonicalFact(\(fact.subject), \(fact.predicate), \(fact.value))",
                    lockedFacts: [fact.value],
                    status: .locked,
                    createdAt: fact.createdAt,
                    revision: max(result.revision, 1)
                )
            )
            changed = true
        }

        let existingTransitionIDs = Set(result.transitions.map(\.id))
        let characterByName = Dictionary(
            uniqueKeysWithValues: project.characters.map { ($0.name, $0.id) }
        )
        for update in project.dramaticUpdates.sorted(by: {
            if $0.sceneIndex == $1.sceneIndex { return $0.ordinal < $1.ordinal }
            return ($0.sceneIndex ?? .max) < ($1.sceneIndex ?? .max)
        }) where !existingTransitionIDs.contains(update.id) {
            let effects = update.mutations.map { mutation in
                StateMutation(
                    id: mutation.id,
                    dimension: dimension(mutation.dimension),
                    subject: mutation.subject,
                    holderID: characterByName[mutation.holder],
                    beforeValue: mutation.beforeValue,
                    afterValue: mutation.afterValue,
                    truthStatus: truth(mutation.truthStatus),
                    observerIDs: mutation.observerNames.compactMap { characterByName[$0] },
                    audienceObserves: mutation.observerNames.contains("观众")
                )
            }
            guard effects.contains(where: \.isEffective) else { continue }
            result.transitions.append(
                DramaticTransition(
                    id: update.id,
                    title: update.summary,
                    actor: characterByName[update.actor],
                    actorName: update.actor,
                    target: NarrativeTarget(
                        characterID: characterByName[update.target],
                        object: update.target
                    ),
                    intention: update.intention,
                    tactic: Tactic(
                        verb: update.actionVerb,
                        method: update.outcome,
                        concealment: ""
                    ),
                    resistance: update.resistance.isEmpty ? [] : [update.resistance],
                    effects: effects,
                    visibility: VisibilityMap(
                        observerIDs: effects.flatMap(\.observerIDs),
                        audienceObserves: effects.contains(where: \.audienceObserves),
                        concealedFromIDs: []
                    ),
                    partialOrderPredecessorIDs: update.causalParentIDs,
                    provenance: Provenance(
                        source: "现有情境透镜",
                        model: update.analysisModel,
                        sourcePropositionIDs: [],
                        generatedAt: update.createdAt
                    ),
                    confidence: AnalysisConfidence(
                        value: update.confidence,
                        basis: "由现有正文语义记录迁移",
                        disputed: update.status == .stale
                    )
                )
            )
            let anchor = update.sourceAnchor
            if anchor.localUTF16Length > 0 {
                result.sourceMaps.append(
                    SemanticSourceMap(
                        id: update.id,
                        utf16Location: anchor.localUTF16Location,
                        utf16Length: anchor.localUTF16Length,
                        transitionIDs: [update.id],
                        realizationRole: update.carrier.rawValue,
                        alignmentConfidence: update.confidence,
                        sourceFingerprint: anchor.sourceFingerprint
                    )
                )
            }
            changed = true
        }

        // Early compiler builds accidentally persisted a few implementation
        // expressions as literal prose.  They are derived NSIR labels, never
        // author text or screenplay text, so normalize them on read rather
        // than leaving the new audit surface mixed with old developer tokens.
        for index in result.transitions.indices {
            if result.transitions[index].title == "触发：(answer.isEmpty ? seed.before : answer)" {
                result.transitions[index].title = "触发：作者命题引入新的压力"
                changed = true
            }
            for effectIndex in result.transitions[index].effects.indices {
                if result.transitions[index].effects[effectIndex].subject == "(actorName)与(targetName)的关系" {
                    result.transitions[index].effects[effectIndex].subject = "人物关系的变化"
                    changed = true
                }
            }
        }

        for index in result.obligations.indices where result.obligations[index].title == "回收：(seed.title)" {
            result.obligations[index].title = "回收：本候选的后续义务"
            changed = true
        }

        for index in result.recommendationTraces.indices {
            for assumptionIndex in result.recommendationTraces[index].assumptions.indices {
                if result.recommendationTraces[index].assumptions[assumptionIndex].statement == "(targetName)会对该策略给出可观察反馈" {
                    result.recommendationTraces[index].assumptions[assumptionIndex].statement = "对方会对该策略给出可观察反馈"
                    changed = true
                }
            }
        }

        for index in result.validationHistory.indices {
            if result.validationHistory[index].issues.contains(where: { $0.title == "回收：(seed.title)" }) {
                for issueIndex in result.validationHistory[index].issues.indices where result.validationHistory[index].issues[issueIndex].title == "回收：(seed.title)" {
                    result.validationHistory[index].issues[issueIndex].title = "回收：本候选的后续义务"
                }
                changed = true
            }
        }

        if changed {
            result.revision = max(result.revision, 1)
            result.updatedAt = .now
        }
        return result
    }

    private static func relationshipState(_ value: CharacterRelationship) -> RelationshipState {
        let intensity = (Double(value.tension) / 100) * 2 - 1
        var trust = -intensity * 0.25
        var intimacy = 0.0
        var power = 0.0
        var dependency = 0.0
        var obligation = 0.0
        var resentment = max(intensity, 0) * 0.45
        var attraction = 0.0
        switch value.kind {
        case .family:
            intimacy = 0.62; dependency = 0.38; obligation = 0.7
        case .love:
            intimacy = 0.7; attraction = 0.78; dependency = 0.35
        case .alliance:
            trust = 0.5; obligation = 0.35
        case .rivalry:
            resentment = 0.55; power = intensity * 0.25
        case .control:
            power = 0.72; dependency = 0.48; trust = -0.35
        case .debt:
            obligation = 0.8; power = 0.35
        case .mentor:
            trust = 0.55; power = 0.48; obligation = 0.32
        case .secret:
            intimacy = 0.35; dependency = 0.52
        case .hostility:
            trust = -0.82; resentment = 0.76
        }
        return RelationshipState(
            id: value.id,
            fromID: value.fromCharacterID,
            toID: value.toCharacterID,
            trust: trust,
            intimacy: intimacy,
            power: power,
            dependency: dependency,
            obligation: obligation,
            resentment: resentment,
            attraction: attraction,
            publicStatus: value.isSecret ? -0.5 : 0.3
        )
    }

    private static func dimension(_ value: DramaticStateDimension) -> NarrativeStateDimension {
        switch value {
        case .world: .world
        case .knowledge: .belief
        case .goal: .goal
        case .relationship: .relationship
        case .norm: .norm
        case .audience: .audience
        }
    }

    private static func truth(_ value: DramaticTruthStatus) -> TruthStatus {
        switch value {
        case .fact: .fact
        case .belief: .belief
        case .mistakenBelief: .mistakenBelief
        case .suspicion: .suspicion
        case .expectation: .expectation
        }
    }
}
