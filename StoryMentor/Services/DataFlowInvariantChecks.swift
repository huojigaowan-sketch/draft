import Foundation
import SwiftData

/// Read-only assertions for the persistence graph after startup repair.
///
/// These checks intentionally fail closed: corrupt Codable payloads and broken
/// identifiers are reported to the UI instead of being replaced with empty data.
@MainActor
enum DataFlowInvariantChecks {
    static func validate(
        projects _: [StoryProject],
        seeds _: [StorySeed],
        in context: ModelContext
    ) throws {
        var violations: [String] = []
        let projects = try context.fetch(FetchDescriptor<StoryProject>())
        let seeds = try context.fetch(FetchDescriptor<StorySeed>())
        let projectIDs = Set(projects.map(\.id))
        if projectIDs.count != projects.count {
            violations.append("项目 UUID 存在重复。")
        }
        if Set(seeds.map(\.id)).count != seeds.count {
            violations.append("故事种子 UUID 存在重复。")
        }

        var experimentIDs = Set<UUID>()
        var variableIDs = Set<UUID>()
        var decisionIDs = Set<UUID>()
        var atomIDs = Set<UUID>()
        var candidateIDs = Set<UUID>()
        let states = try context.fetch(FetchDescriptor<ScreenplayWorkspaceState>())
        let statesByProject = Dictionary(grouping: states, by: \.projectID)

        for (projectID, matches) in statesByProject where matches.count > 1 {
            violations.append(
                "项目 \(projectID.uuidString) 仍有 \(matches.count) 份剧本工作区。"
            )
        }
        for state in states where !projectIDs.contains(state.projectID) {
            violations.append(
                "剧本工作区 \(state.id.uuidString) 指向不存在的项目。"
            )
        }
        for state in states {
            validatePayloads(of: state, violations: &violations)
        }

        for seed in seeds {
            guard let projectID = seed.projectID else {
                violations.append(
                    "故事种子 \(seed.id.uuidString) 尚未归入项目。"
                )
                validatePayloads(
                    of: seed,
                    experimentIDs: &experimentIDs,
                    variableIDs: &variableIDs,
                    decisionIDs: &decisionIDs,
                    atomIDs: &atomIDs,
                    candidateIDs: &candidateIDs,
                    violations: &violations
                )
                continue
            }
            if !projectIDs.contains(projectID) {
                violations.append(
                    "故事种子 \(seed.id.uuidString) 指向不存在的项目。"
                )
            }
            validatePayloads(
                of: seed,
                experimentIDs: &experimentIDs,
                variableIDs: &variableIDs,
                decisionIDs: &decisionIDs,
                atomIDs: &atomIDs,
                candidateIDs: &candidateIDs,
                violations: &violations
            )
        }

        let fragments = try context.fetch(FetchDescriptor<StoryFragment>())
        for fragment in fragments {
            if let projectID = fragment.projectID,
               !projectIDs.contains(projectID) {
                violations.append(
                    "灵感碎片 \(fragment.id.uuidString) 的 projectID 已悬空。"
                )
            }
            if let grownProjectID = fragment.grownProjectID,
               !projectIDs.contains(grownProjectID) {
                violations.append(
                    "灵感碎片 \(fragment.id.uuidString) 的 grownProjectID 已悬空。"
                )
            }
        }

        for project in projects {
            validateNSIR(of: project, violations: &violations)
        }

        guard violations.isEmpty else {
            throw DataFlowInvariantError.violations(violations)
        }
    }

    private static func validatePayloads(
        of seed: StorySeed,
        experimentIDs: inout Set<UUID>,
        variableIDs: inout Set<UUID>,
        decisionIDs: inout Set<UUID>,
        atomIDs: inout Set<UUID>,
        candidateIDs: inout Set<UUID>,
        violations: inout [String]
    ) {
        decode(
            [DramaticElement].self,
            data: seed.dramaticElementsData,
            label: "dramaticElements",
            seed: seed,
            violations: &violations
        )
        decode(
            [AdaptationDirection].self,
            data: seed.directionsData,
            label: "directions",
            seed: seed,
            violations: &violations
        )

        if !seed.scienceLabData.isEmpty {
            do {
                let snapshot = try PersistentPayloadCodec.decodeRequired(
                    StoryCultivationSnapshot.self,
                    from: seed.scienceLabData,
                    label: "StorySeed.cultivationSnapshot"
                )
                validate(
                    snapshot: snapshot,
                    seed: seed,
                    experimentIDs: &experimentIDs,
                    variableIDs: &variableIDs,
                    decisionIDs: &decisionIDs,
                    atomIDs: &atomIDs,
                    violations: &violations
                )
            } catch {
                violations.append(
                    "故事种子“\(seed.title)”的实验载荷无法读取：\(error.localizedDescription)"
                )
            }
        }

        if !seed.pendingExperimentData.isEmpty {
            do {
                let candidate = try PersistentPayloadCodec.decodeRequired(
                    StoryExperimentCandidate.self,
                    from: seed.pendingExperimentData,
                    label: "StorySeed.pendingExperimentCandidate"
                )
                if !candidateIDs.insert(candidate.id).inserted {
                    violations.append("实验候选 UUID \(candidate.id.uuidString) 重复。")
                }
                if !decisionIDs.insert(candidate.decision.id).inserted {
                    violations.append("实验决定 UUID \(candidate.decision.id.uuidString) 重复。")
                }
                validate(
                    decision: candidate.decision,
                    seed: seed,
                    violations: &violations
                )
                validateInternalIDs(
                    of: candidate.proposal,
                    seed: seed,
                    label: "待复盘提案",
                    violations: &violations
                )
            } catch {
                violations.append(
                    "故事种子“\(seed.title)”的待复盘载荷无法读取：\(error.localizedDescription)"
                )
            }
        }
    }

    private static func validate(
        snapshot: StoryCultivationSnapshot,
        seed: StorySeed,
        experimentIDs: inout Set<UUID>,
        variableIDs: inout Set<UUID>,
        decisionIDs: inout Set<UUID>,
        atomIDs: inout Set<UUID>,
        violations: inout [String]
    ) {
        for atom in snapshot.atoms where !atomIDs.insert(atom.id).inserted {
            violations.append("种子“\(seed.title)”的故事原子 UUID \(atom.id.uuidString) 重复。")
        }
        for experiment in snapshot.experiments {
            if !experimentIDs.insert(experiment.id).inserted {
                violations.append("种子“\(seed.title)”的实验 UUID \(experiment.id.uuidString) 重复。")
            }
            for variable in experiment.variables where !variableIDs.insert(variable.id).inserted {
                violations.append("种子“\(seed.title)”的实验变量 UUID \(variable.id.uuidString) 重复。")
            }
        }
        for decision in snapshot.decisions {
            if !decisionIDs.insert(decision.id).inserted {
                violations.append("种子“\(seed.title)”的实验决定 UUID \(decision.id.uuidString) 重复。")
            }
            validate(decision: decision, seed: seed, violations: &violations)
        }
        validateInternalIDs(
            of: snapshot,
            seed: seed,
            label: "实验快照",
            violations: &violations
        )
    }

    private static func validateInternalIDs(
        of snapshot: StoryCultivationSnapshot,
        seed: StorySeed,
        label: String,
        violations: inout [String]
    ) {
        if Set(snapshot.atoms.map(\.id)).count != snapshot.atoms.count {
            violations.append("种子“\(seed.title)”的\(label)含重复故事原子 UUID。")
        }
        if Set(snapshot.experiments.map(\.id)).count != snapshot.experiments.count {
            violations.append("种子“\(seed.title)”的\(label)含重复实验 UUID。")
        }
        let variables = snapshot.experiments.flatMap(\.variables)
        if Set(variables.map(\.id)).count != variables.count {
            violations.append("种子“\(seed.title)”的\(label)含重复实验变量 UUID。")
        }
        if Set(snapshot.decisions.map(\.id)).count != snapshot.decisions.count {
            violations.append("种子“\(seed.title)”的\(label)含重复实验决定 UUID。")
        }
    }

    private static func validate(
        decision: StoryExperimentDecision,
        seed: StorySeed,
        violations: inout [String]
    ) {
        guard !decision.selectedValues.isEmpty else {
            violations.append(
                "种子“\(seed.title)”的实验决定 \(decision.id.uuidString) 没有最终选择。"
            )
            return
        }
        guard let record = decision.choiceRecord else { return }
        guard decision.selectedValues.count == 1,
              let selectedValue = decision.selectedValues.first?.value else {
            violations.append(
                "种子“\(seed.title)”的新实验决定 \(decision.id.uuidString) 不是单变量选择。"
            )
            return
        }
        if record.finalValue != selectedValue {
            violations.append(
                "实验决定 \(decision.id.uuidString) 的审计值与最终选择不一致。"
            )
        }
        switch record.source {
        case .aiSuggestion:
            guard let index = record.selectedCandidateIndex,
                  record.aiCandidates.indices.contains(index),
                  record.aiCandidates[index] == record.finalValue else {
                violations.append(
                    "实验决定 \(decision.id.uuidString) 的 AI 候选索引无效。"
                )
                return
            }
        case .authorDesigned:
            if record.selectedCandidateIndex != nil {
                violations.append(
                    "实验决定 \(decision.id.uuidString) 的作者自定选择不应携带 AI 候选索引。"
                )
            }
        }
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        data: Data,
        label: String,
        seed: StorySeed,
        violations: inout [String]
    ) {
        guard !data.isEmpty else { return }
        do {
            _ = try PersistentPayloadCodec.decodeRequired(
                type,
                from: data,
                label: "StorySeed.\(label)"
            )
        } catch {
            violations.append(
                "故事种子“\(seed.title)”的 \(label) 载荷损坏：\(error.localizedDescription)"
            )
        }
    }

    private static func validateNSIR(
        of project: StoryProject,
        violations: inout [String]
    ) {
        guard !project.nsirWorkspaceData.isEmpty else { return }

        let document: CompilerWorkspaceDocument
        do {
            document = try project.requireNSIRWorkspace()
        } catch {
            violations.append(
                "项目“\(project.title)”的 NSIR 载荷无法读取：\(error.localizedDescription)"
            )
            return
        }

        if document.projectID != project.id {
            violations.append("项目“\(project.title)”的 NSIR projectID 不一致。")
        }
        if document.schemaVersion != NSIRSchema.currentVersion {
            violations.append(
                "项目“\(project.title)”的 NSIR schema 为 \(document.schemaVersion)，当前应为 \(NSIRSchema.currentVersion)。"
            )
        }
        if project.nsirRevision != document.revision {
            violations.append("项目“\(project.title)”的 NSIR revision 镜像不一致。")
        }

        let transitionIDs = Set(document.transitions.map(\.id))
        if transitionIDs.count != document.transitions.count {
            violations.append("项目“\(project.title)”的 NSIR 转移 UUID 存在重复。")
        }
        let expectedOrdinals = SceneMappingEngine.nsirTransitionOrdinals(
            in: document
        )
        for contract in project.sceneContracts
        where contract.sourceKindRawValue == "nsir.transition" {
            if contract.sourceSnapshotData.isEmpty || contract.sourceFingerprint.isEmpty {
                violations.append(
                    "场景合同 \(contract.id.uuidString) 缺少 NSIR 来源快照。"
                )
            }
            if contract.sourceIsMissing && !contract.sourceIsDetached {
                violations.append(
                    "场景合同 \(contract.id.uuidString) 标记来源缺失却未分叉。"
                )
            }
            if !contract.sourceIsMissing && !transitionIDs.contains(contract.id) {
                violations.append(
                    "场景合同 \(contract.id.uuidString) 的 NSIR 来源不存在。"
                )
            }
            if !contract.sourceIsMissing,
               let expectedOrdinal = expectedOrdinals[contract.id],
               contract.stageSceneOrdinal != expectedOrdinal {
                violations.append(
                    "场景合同 \(contract.id.uuidString) 的序号为 \(contract.stageSceneOrdinal)，应为 \(expectedOrdinal)。"
                )
            }
        }
    }

    private static func validatePayloads(
        of state: ScreenplayWorkspaceState,
        violations: inout [String]
    ) {
        validate(
            [ScreenplaySceneMetadata].self,
            data: state.metadataData,
            label: "metadata",
            stateID: state.id,
            violations: &violations
        )
        validate(
            [ScreenplaySceneRecord].self,
            data: state.sceneRecordsData,
            label: "sceneRecords",
            stateID: state.id,
            violations: &violations
        )
        validate(
            [ScreenplayRevision].self,
            data: state.revisionsData,
            label: "revisions",
            stateID: state.id,
            violations: &violations
        )
        validate(
            [ScreenplayReviewRound].self,
            data: state.reviewRoundsData,
            label: "reviewRounds",
            stateID: state.id,
            violations: &violations
        )
        validate(
            [ScreenplayElementStyleDefinition].self,
            data: state.elementStylesData,
            label: "elementStyles",
            stateID: state.id,
            violations: &violations
        )
    }

    private static func validate<Value: Decodable>(
        _ type: Value.Type,
        data: Data,
        label: String,
        stateID: UUID,
        violations: inout [String]
    ) {
        guard !data.isEmpty else { return }
        do {
            _ = try PersistentPayloadCodec.decodeRequired(
                type,
                from: data,
                label: "ScreenplayWorkspaceState.\(label)"
            )
        } catch {
            violations.append(
                "剧本工作区 \(stateID.uuidString) 的 \(label) 载荷损坏：\(error.localizedDescription)"
            )
        }
    }
}

enum DataFlowInvariantError: LocalizedError {
    case violations([String])

    var errorDescription: String? {
        switch self {
        case .violations(let items):
            return (["数据流不变量检查失败："] + items.prefix(12).map { "• \($0)" })
                .joined(separator: "\n")
        }
    }
}
