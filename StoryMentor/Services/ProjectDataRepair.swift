import Foundation
import SwiftData

enum ProjectDataRepair {
    @MainActor
    @discardableResult
    static func repairIfNeeded(
        projects: [StoryProject],
        in modelContext: ModelContext
    ) -> Bool {
        var changed = false

        for project in projects {
            let originalUpdatedAt = project.updatedAt
            if !project.nsirWorkspaceData.isEmpty,
               let document = try? project.requireNSIRWorkspace(),
               SceneMappingEngine.repairNSIRTransitionOrdering(
                   in: project,
                   document: document
               ) {
                changed = true
            }
            for contract in project.sceneContracts
            where contract.stateContractData.isEmpty
                && contract.selectedSceneOptionID != nil {
                let before = contract.scopeEntryState.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                let after = contract.scopeExitState.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                let inferred: [DramaticStateMutation]
                if !after.isEmpty && before != after {
                    inferred = [
                        DramaticStateMutation(
                            dimension: .world,
                            subject: contract.scopeTitle.isEmpty
                                ? "场 \(contract.sceneIndex) 的局面"
                                : contract.scopeTitle,
                            beforeValue: before.isEmpty ? "未知" : before,
                            afterValue: after,
                            observerNames: ["观众"]
                        )
                    ]
                } else {
                    inferred = []
                }
                contract.stateContract = SceneStateContract(
                    entrySnapshot: before,
                    requiredChanges: inferred,
                    forbiddenChanges: [],
                    audienceOutcome: contract.outcome,
                    exitSnapshot: after,
                    verificationRule: contract.outcome
                )
                changed = true
            }
            if project.authorIdeas.isEmpty {
                for legacy in project.creativeIdeas {
                    let status: AuthorIdeaStatus
                    if legacy.scope == .inbox {
                        status = .inbox
                    } else {
                        status = legacy.isActive ? .active : .paused
                    }
                    let record = AuthorIdeaRecord(
                        id: legacy.id,
                        originalText: legacy.text,
                        scope: legacy.scope,
                        status: status,
                        targetStageIndex: legacy.targetStageIndex,
                        createdAt: legacy.createdAt
                    )
                    record.updatedAt = legacy.updatedAt
                    record.appliedAt = status == .active ? legacy.updatedAt : nil
                    record.executionIdeaID = legacy.id
                    record.project = project
                    modelContext.insert(record)
                    changed = true
                }
            }

            let orderedDecisions = project.decisions.sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.createdAt < $1.createdAt
            }

            guard let template = inferredTemplate(
                for: project,
                decisions: orderedDecisions
            ) else {
                project.updatedAt = originalUpdatedAt
                continue
            }

            if project.structureTemplateID != template.id {
                project.structureTemplateID = template.id
                changed = true
            }
            if project.structureTemplateName != template.name {
                project.structureTemplateName = template.name
                changed = true
            }

            let hasCommittedDecision = orderedDecisions.contains {
                $0.selectedOptionID != nil
                    || $0.resolvedAt != nil
                    || !$0.selectedAnswerText.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
            }
            if hasCommittedDecision {
                if project.structureRulesText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty {
                    project.structureRulesText = template.rulesPrompt
                    changed = true
                }
                if project.lockedStructureSnapshot.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty {
                    project.lockedStructureSnapshot = template.rulesPrompt
                    changed = true
                }
                if !project.isStructureLocked {
                    project.isStructureLocked = true
                    changed = true
                }
                if project.structureLockedAt == nil {
                    project.structureLockedAt = orderedDecisions
                        .first(where: {
                            $0.selectedOptionID != nil
                                || $0.resolvedAt != nil
                                || !$0.selectedAnswerText.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty
                        })?
                        .createdAt ?? project.createdAt
                    changed = true
                }
            }

            let indexRepair = repairDecisionIndices(
                orderedDecisions,
                against: template
            )
            if indexRepair.changed {
                changed = true
                if repairStageScopedData(
                    in: project,
                    using: indexRepair.unambiguousStageMoves
                ) {
                    changed = true
                }
                rebuildStoryPath(in: project)
            }

            project.updatedAt = originalUpdatedAt
        }

        return changed
    }

    @MainActor
    private static func inferredTemplate(
        for project: StoryProject,
        decisions: [StoryDecision]
    ) -> StoryStructureTemplate? {
        if let exact = StoryStructureCatalog.templates.first(where: {
            $0.id == project.structureTemplateID
        }) {
            return exact
        }

        if let named = StoryStructureCatalog.templates.first(where: {
            $0.name == project.structureTemplateName
        }) {
            return named
        }

        guard !decisions.isEmpty else { return nil }

        // The legacy workflow used JourneyPhase verbatim. Recognize that schema
        // before any fuzzy template matching so a shared stage name cannot
        // accidentally migrate the project to a shorter template.
        if decisions.allSatisfy({
            JourneyPhase(rawValue: $0.stageName) != nil
        }) {
            return StoryStructureCatalog.template(id: "guided-core")
        }

        let decisionNames = Set(decisions.map(\.stageName))
        let ranked = StoryStructureCatalog.templates
            .map { template in
                (
                    template: template,
                    score: template.stages.reduce(0) {
                        $0 + (decisionNames.contains($1.name) ? 1 : 0)
                    }
                )
            }
            .sorted {
                if $0.score == $1.score {
                    return $0.template.id < $1.template.id
                }
                return $0.score > $1.score
            }

        guard let best = ranked.first,
              best.score >= 2,
              Double(best.score) / Double(max(decisionNames.count, 1)) >= 0.6 else {
            return nil
        }
        let equallyRanked = ranked.filter { $0.score == best.score }
        guard equallyRanked.count == 1 else { return nil }
        return best.template
    }

    private struct DecisionIndexRepair {
        let changed: Bool
        let unambiguousStageMoves: [Int: Int]
    }

    private static func repairDecisionIndices(
        _ decisions: [StoryDecision],
        against template: StoryStructureTemplate
    ) -> DecisionIndexRepair {
        guard !decisions.isEmpty else {
            return DecisionIndexRepair(
                changed: false,
                unambiguousStageMoves: [:]
            )
        }

        var indicesByName: [String: [Int]] = [:]
        for (index, stage) in template.stages.enumerated() {
            indicesByName[stage.name, default: []].append(index)
        }

        var usedIndices = Set<Int>()
        var assignments: [UUID: Int] = [:]
        var normalizedStageNames: [UUID: String] = [:]

        // Exact, unique stage names are the strongest migration evidence.
        for decision in decisions {
            let mapped: Int?
            if let matches = indicesByName[decision.stageName],
               matches.count == 1 {
                mapped = matches.first
            } else if template.id == "guided-core",
                      let legacyPhase = JourneyPhase(rawValue: decision.stageName),
                      let legacyIndex = JourneyPhase.ordered.firstIndex(
                        of: legacyPhase
                      ),
                      template.stages.indices.contains(legacyIndex) {
                mapped = legacyIndex
                normalizedStageNames[decision.id] =
                    template.stages[legacyIndex].name
            } else {
                mapped = nil
            }
            guard let mapped, !usedIndices.contains(mapped) else {
                continue
            }
            assignments[decision.id] = mapped
            usedIndices.insert(mapped)
        }

        // Preserve valid custom/unknown stages in place. Never invent a new
        // semantic stage merely to eliminate a duplicate.
        for decision in decisions where assignments[decision.id] == nil {
            let current = decision.stageIndex
            guard template.stages.indices.contains(current),
                  !usedIndices.contains(current) else {
                continue
            }
            assignments[decision.id] = current
            usedIndices.insert(current)
        }

        var changed = false
        var finalTransitions: [Int: Set<Int>] = [:]
        for decision in decisions {
            let original = decision.stageIndex
            let repaired = assignments[decision.id] ?? original
            finalTransitions[original, default: []].insert(repaired)
            if repaired != original {
                decision.stageIndex = repaired
                changed = true
            }
            if let normalized = normalizedStageNames[decision.id],
               decision.phaseRawValue != normalized {
                decision.phaseRawValue = normalized
                changed = true
            }
        }

        let unambiguousMoves = finalTransitions.reduce(
            into: [Int: Int]()
        ) { result, item in
            guard item.value.count == 1,
                  let destination = item.value.first,
                  destination != item.key else {
                return
            }
            result[item.key] = destination
        }
        return DecisionIndexRepair(
            changed: changed,
            unambiguousStageMoves: unambiguousMoves
        )
    }

    @MainActor
    private static func repairStageScopedData(
        in project: StoryProject,
        using moves: [Int: Int]
    ) -> Bool {
        guard !moves.isEmpty else { return false }
        var changed = false

        if var ideas = PersistentPayloadCodec.decodeOptional(
            [CreativeIdea].self,
            from: project.creativeIdeasData,
            label: "StoryProject.creativeIdeas"
        ) {
            for index in ideas.indices {
                guard ideas[index].scope == .stage,
                      let current = ideas[index].targetStageIndex,
                      let repaired = moves[current] else {
                    continue
                }
                ideas[index].targetStageIndex = repaired
                changed = true
            }
            if changed {
                project.creativeIdeasData = PersistentPayloadCodec.encode(
                    ideas,
                    preserving: project.creativeIdeasData,
                    label: "StoryProject.creativeIdeas"
                )
            }
        }

        if var plans = PersistentPayloadCodec.decodeOptional(
            [StagePacingPlan].self,
            from: project.pacingPlansData,
            label: "StoryProject.pacingPlans"
        ) {
            var occupied = Set(plans.map(\.stageIndex))
            var plansChanged = false
            for index in plans.indices {
                let current = plans[index].stageIndex
                guard let repaired = moves[current],
                      !occupied.contains(repaired) else {
                    continue
                }
                occupied.remove(current)
                occupied.insert(repaired)
                plans[index].stageIndex = repaired
                plansChanged = true
            }
            if plansChanged {
                project.pacingPlansData = PersistentPayloadCodec.encode(
                    plans,
                    preserving: project.pacingPlansData,
                    label: "StoryProject.pacingPlans"
                )
                changed = true
            }
        }

        return changed
    }

    private static func rebuildStoryPath(in project: StoryProject) {
        project.storyPathText = project.decisions
            .filter {
                $0.selectedOptionID != nil
                    || !$0.selectedAnswerText.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
            }
            .sorted {
                if $0.stageIndex == $1.stageIndex {
                    return $0.createdAt < $1.createdAt
                }
                return $0.stageIndex < $1.stageIndex
            }
            .map {
                "第\($0.stageIndex + 1)阶段 · \($0.stageName)\n\($0.selectedAnswerText)"
            }
            .joined(separator: "\n\n")
    }
}
