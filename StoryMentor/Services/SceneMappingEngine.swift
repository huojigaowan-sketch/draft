import Foundation
import SwiftData

@MainActor
enum SceneMappingEngine {
    /// 将已经由作者提交的 NSIR 状态转移铺成场景范围草稿。
    /// 转移 ID 同时作为场景契约 ID，因此重复打开或重复同步都不会增生副本。
    @discardableResult
    static func synchronizeNSIRTransitions(
        in project: StoryProject,
        document: CompilerWorkspaceDocument,
        modelContext: ModelContext
    ) -> Bool {
        var changed = repairNSIRTransitionOrdering(
            in: project,
            document: document
        )
        var nextIndex = nextSceneIndex(in: project)
        let ordinals = nsirTransitionOrdinals(in: document)
        let transitionsByID = Dictionary(
            uniqueKeysWithValues: document.transitions.map { ($0.id, $0) }
        )
        let contractsByID = Dictionary(
            uniqueKeysWithValues: project.sceneContracts.map { ($0.id, $0) }
        )

        for transition in document.transitions {
            let source = NSIRSceneContractSnapshot(transition: transition)
            if let contract = contractsByID[transition.id] {
                if contract.sourceKindRawValue.isEmpty {
                    contract.sourceKindRawValue = SceneContractSourceKind.nsirTransition.rawValue
                    contract.sourceSnapshotData = PersistentPayloadCodec.encode(
                        NSIRSceneContractSnapshot(contract: contract),
                        preserving: contract.sourceSnapshotData,
                        label: "SceneContract.sourceSnapshot"
                    )
                    contract.sourceFingerprint = sourceFingerprint(
                        NSIRSceneContractSnapshot(contract: contract)
                    )
                    changed = true
                }

                guard contract.sourceKindRawValue
                        == SceneContractSourceKind.nsirTransition.rawValue else {
                    continue
                }

                let previous = PersistentPayloadCodec.decodeOptional(
                    NSIRSceneContractSnapshot.self,
                    from: contract.sourceSnapshotData,
                    label: "SceneContract.sourceSnapshot"
                )
                let current = NSIRSceneContractSnapshot(contract: contract)
                let canRefresh = previous == nil || previous == current
                if canRefresh {
                    if current != source
                        || contract.sourceRevision != document.revision
                        || contract.sourceIsDetached
                        || contract.sourceIsMissing {
                        source.apply(to: contract)
                        contract.sourceRevision = document.revision
                        contract.sourceFingerprint = sourceFingerprint(source)
                        contract.sourceSnapshotData = PersistentPayloadCodec.encode(
                            source,
                            preserving: contract.sourceSnapshotData,
                            label: "SceneContract.sourceSnapshot"
                        )
                        contract.sourceIsDetached = false
                        contract.sourceIsMissing = false
                        contract.updatedAt = .now
                        changed = true
                    }
                } else if !contract.sourceIsDetached
                            || contract.sourceRevision != document.revision {
                    contract.sourceIsDetached = true
                    contract.sourceRevision = document.revision
                    contract.sourceIsMissing = false
                    contract.updatedAt = .now
                    changed = true
                }
                continue
            }

            let contract = source.makeContract(
                id: transition.id,
                sceneIndex: nextIndex,
                stageSceneOrdinal: ordinals[transition.id] ?? nextIndex
            )
            nextIndex += 1
            contract.sourceKindRawValue = SceneContractSourceKind.nsirTransition.rawValue
            contract.sourceRevision = document.revision
            contract.sourceFingerprint = sourceFingerprint(source)
            contract.sourceSnapshotData = PersistentPayloadCodec.encode(
                source,
                preserving: contract.sourceSnapshotData,
                label: "SceneContract.sourceSnapshot"
            )
            contract.project = project
            modelContext.insert(contract)
            changed = true
        }

        for contract in project.sceneContracts
        where contract.sourceKindRawValue
                == SceneContractSourceKind.nsirTransition.rawValue
            && transitionsByID[contract.id] == nil {
            let previous = PersistentPayloadCodec.decodeOptional(
                NSIRSceneContractSnapshot.self,
                from: contract.sourceSnapshotData,
                label: "SceneContract.sourceSnapshot"
            )
            let current = NSIRSceneContractSnapshot(contract: contract)
            let isUnmodified = previous == nil || previous == current
            if isUnmodified,
               contract.selectedSceneOptionID == nil,
               contract.microBeats.isEmpty {
                modelContext.delete(contract)
            } else {
                contract.sourceIsMissing = true
                contract.sourceIsDetached = true
                contract.sourceRevision = document.revision
                contract.updatedAt = .now
            }
            changed = true
        }

        if changed {
            modelContext.processPendingChanges()
            renumber(project.sceneContracts)
            project.touch()
        }
        return changed
    }

    /// NSIR transitions form one committed causal chain. Older builds created
    /// every projected scene with the model default ordinal of `1`; repair the
    /// persisted order from the canonical transition array without touching
    /// author-edited scene content.
    @discardableResult
    static func repairNSIRTransitionOrdering(
        in project: StoryProject,
        document: CompilerWorkspaceDocument
    ) -> Bool {
        let ordinals = nsirTransitionOrdinals(in: document)
        var changed = false

        for transition in document.transitions {
            guard let contract = project.sceneContracts.first(where: {
                $0.id == transition.id
                    && ($0.sourceKindRawValue.isEmpty
                        || $0.sourceKindRawValue == SceneContractSourceKind.nsirTransition.rawValue)
            }), let ordinal = ordinals[transition.id] else {
                continue
            }

            if contract.sourceKindRawValue.isEmpty {
                contract.sourceKindRawValue = SceneContractSourceKind.nsirTransition.rawValue
                changed = true
            }
            if contract.stageSceneOrdinal != ordinal {
                contract.stageSceneOrdinal = ordinal
                contract.updatedAt = .now
                changed = true
            }
        }

        if changed {
            renumber(project.sceneContracts)
        }
        return changed
    }

    static func nsirTransitionOrdinals(
        in document: CompilerWorkspaceDocument
    ) -> [TransitionID: Int] {
        var result: [TransitionID: Int] = [:]
        for (offset, transition) in document.transitions.enumerated()
        where result[transition.id] == nil {
            result[transition.id] = offset + 1
        }
        return result
    }

    @discardableResult
    static func synchronizeConfirmedStages(
        in project: StoryProject,
        modelContext: ModelContext
    ) -> Bool {
        var changed = false
        let resolved = project.decisions
            .filter { $0.selectedOptionID != nil }
            .sorted { $0.stageIndex < $1.stageIndex }
        guard project.isStructureLocked,
              !project.structureTemplate.stages.isEmpty,
              project.nextStructureStageIndex == nil else {
            return false
        }

        for decision in resolved where !project.sceneContracts.contains(where: {
            $0.structureStageIndex == decision.stageIndex
        }) {
            guard let selected = decision.selectedOption else { continue }
            let planned = selected.plannedStateChanges?.first
            let placeholder = SceneContract(
                sceneIndex: nextSceneIndex(in: project),
                structureStageIndex: decision.stageIndex,
                stageSceneOrdinal: 1,
                scopeTitle: "\(decision.stageName) · 待拆分场景",
                scopePurpose: selected.pitch,
                scopeEntryState: planned?.beforeValue ?? selected.concreteDetail,
                scopeExitState: planned?.afterValue ?? [selected.consequence, selected.futurePressure]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: "；"),
                status: "待拆分场景"
            )
            placeholder.project = project
            modelContext.insert(placeholder)
            changed = true
        }

        if changed {
            renumber(project.sceneContracts)
            project.touch()
        }
        return changed
    }

    static func replaceUnconfirmedScopes(
        _ scopes: [SceneScopeDraft],
        for decision: StoryDecision,
        in project: StoryProject,
        modelContext: ModelContext
    ) {
        let existing = project.sceneContracts.filter {
            $0.structureStageIndex == decision.stageIndex
        }
        guard !existing.contains(where: { $0.selectedSceneOptionID != nil }) else {
            return
        }
        let insertionStart = project.sceneContracts
            .filter { $0.structureStageIndex != decision.stageIndex }
            .map(\.sceneIndex)
            .max() ?? 0
        for contract in existing {
            modelContext.delete(contract)
        }

        for (offset, scope) in scopes.enumerated() {
            let contract = SceneContract(
                sceneIndex: insertionStart + offset + 1,
                structureStageIndex: decision.stageIndex,
                stageSceneOrdinal: offset + 1,
                scopeTitle: scope.title,
                scopePurpose: scope.purpose,
                scopeEntryState: scope.entryState,
                scopeExitState: scope.exitState,
                status: "待选择"
            )
            contract.project = project
            modelContext.insert(contract)
        }
        modelContext.processPendingChanges()
        renumber(project.sceneContracts)
        project.touch()
    }

    static func confirm(
        _ option: SceneChoiceOption,
        for contract: SceneContract,
        in project: StoryProject
    ) throws {
        guard contract.selectedSceneOptionID == nil else {
            throw SceneMappingError.alreadyConfirmed
        }
        guard contract.sceneOptions.contains(where: { $0.id == option.id }) else {
            throw SceneMappingError.optionMissing
        }
        contract.heading = option.heading
        contract.pointOfView = option.pointOfView
        contract.characterGoal = option.characterGoal
        contract.obstacle = option.obstacle
        contract.turn = option.turn
        contract.outcome = option.outcome
        contract.nextPressure = option.nextPressure
        contract.selectedSceneOptionID = option.id
        contract.stateContract = SceneStateContract(
            entrySnapshot: contract.scopeEntryState,
            requiredChanges: option.requiredStateChanges ?? [],
            forbiddenChanges: option.forbiddenChanges ?? [],
            audienceOutcome: option.audienceUpdate ?? "",
            exitSnapshot: contract.scopeExitState,
            verificationRule: option.outcome
        )
        contract.status = "已确认"
        contract.updatedAt = .now
        project.scenesText = project.sceneContracts
            .filter { $0.selectedSceneOptionID != nil }
            .sorted { $0.sceneIndex < $1.sceneIndex }
            .map {
                """
                【场景 \($0.sceneIndex) · 第 \(($0.structureStageIndex ?? 0) + 1) 节拍】 \($0.heading)
                视点：\($0.pointOfView)
                目标：\($0.characterGoal)
                阻碍：\($0.obstacle)
                转折：\($0.turn)
                结果：\($0.outcome)
                下一场压力：\($0.nextPressure)
                """
            }
            .joined(separator: "\n\n")
        project.touch()
    }

    static func appendScope(
        toStage stageIndex: Int,
        in project: StoryProject,
        modelContext: ModelContext
    ) -> SceneContract {
        let ordinal = project.sceneContracts
            .filter { $0.structureStageIndex == stageIndex }
            .map(\.stageSceneOrdinal)
            .max() ?? 0
        let contract = SceneContract(
            sceneIndex: nextSceneIndex(in: project),
            structureStageIndex: stageIndex,
            stageSceneOrdinal: ordinal + 1,
            scopeTitle: "补充场景",
            scopePurpose: "明确这个节拍还需要承担的额外状态变化",
            status: "待拆分场景"
        )
        contract.project = project
        modelContext.insert(contract)
        modelContext.processPendingChanges()
        renumber(project.sceneContracts)
        project.touch()
        return contract
    }

    static func renumber(_ contracts: [SceneContract]) {
        let sorted = contracts.sorted {
            let lhsStage = $0.structureStageIndex ?? Int.max
            let rhsStage = $1.structureStageIndex ?? Int.max
            if lhsStage == rhsStage {
                if $0.stageSceneOrdinal == $1.stageSceneOrdinal {
                    return $0.createdAt < $1.createdAt
                }
                return $0.stageSceneOrdinal < $1.stageSceneOrdinal
            }
            return lhsStage < rhsStage
        }
        for (offset, contract) in sorted.enumerated() {
            contract.sceneIndex = offset + 1
        }
    }

    private static func sourceFingerprint(_ snapshot: NSIRSceneContractSnapshot) -> String {
        PersistentPayloadCodec.encode(
            snapshot,
            preserving: Data(),
            label: "SceneContract.sourceFingerprint"
        ).base64EncodedString()
    }

    private static func nextSceneIndex(in project: StoryProject) -> Int {
        (project.sceneContracts.map(\.sceneIndex).max() ?? 0) + 1
    }
}

enum SceneContractSourceKind: String {
    case nsirTransition = "nsir.transition"
}

private struct NSIRSceneContractSnapshot: Codable, Equatable {
    var scopeTitle: String
    var scopePurpose: String
    var scopeEntryState: String
    var scopeExitState: String
    var pointOfView: String
    var characterGoal: String
    var obstacle: String
    var turn: String
    var outcome: String
    var nextPressure: String
    var status: String

    init(transition: DramaticTransition) {
        let stateChanges = transition.effects.map {
            "\($0.dimension.rawValue)·\($0.subject)：\($0.beforeValue) → \($0.afterValue)"
        }
        let entryStates = transition.effects.map {
            "\($0.dimension.rawValue)·\($0.subject)：\($0.beforeValue)"
        }
        let exitStates = transition.effects.map {
            "\($0.dimension.rawValue)·\($0.subject)：\($0.afterValue)"
        }
        let costs = transition.cost.map {
            [$0.title, $0.detail].filter { !$0.isEmpty }.joined(separator: "：")
        }

        scopeTitle = transition.title
        scopePurpose = [transition.intention, transition.tactic.verb, transition.tactic.method]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        scopeEntryState = entryStates.joined(separator: "；")
        scopeExitState = exitStates.joined(separator: "；")
        pointOfView = transition.actorName
        characterGoal = transition.intention
        obstacle = transition.resistance.joined(separator: "；")
        turn = stateChanges.joined(separator: "；")
        outcome = exitStates.joined(separator: "；")
        nextPressure = costs.joined(separator: "；")
        status = "来自结构推演 · 待选择"
    }

    init(contract: SceneContract) {
        scopeTitle = contract.scopeTitle
        scopePurpose = contract.scopePurpose
        scopeEntryState = contract.scopeEntryState
        scopeExitState = contract.scopeExitState
        pointOfView = contract.pointOfView
        characterGoal = contract.characterGoal
        obstacle = contract.obstacle
        turn = contract.turn
        outcome = contract.outcome
        nextPressure = contract.nextPressure
        status = contract.status
    }

    func apply(to contract: SceneContract) {
        contract.scopeTitle = scopeTitle
        contract.scopePurpose = scopePurpose
        contract.scopeEntryState = scopeEntryState
        contract.scopeExitState = scopeExitState
        contract.pointOfView = pointOfView
        contract.characterGoal = characterGoal
        contract.obstacle = obstacle
        contract.turn = turn
        contract.outcome = outcome
        contract.nextPressure = nextPressure
        contract.status = status
    }

    func makeContract(
        id: UUID,
        sceneIndex: Int,
        stageSceneOrdinal: Int
    ) -> SceneContract {
        SceneContract(
            id: id,
            sceneIndex: sceneIndex,
            stageSceneOrdinal: stageSceneOrdinal,
            scopeTitle: scopeTitle,
            scopePurpose: scopePurpose,
            scopeEntryState: scopeEntryState,
            scopeExitState: scopeExitState,
            pointOfView: pointOfView,
            characterGoal: characterGoal,
            obstacle: obstacle,
            turn: turn,
            outcome: outcome,
            nextPressure: nextPressure,
            status: status
        )
    }
}

enum SceneMappingError: LocalizedError {
    case alreadyConfirmed
    case optionMissing

    var errorDescription: String? {
        switch self {
        case .alreadyConfirmed:
            "这个场景已经确认。"
        case .optionMissing:
            "所选方案已经失效，请重新生成。"
        }
    }
}
