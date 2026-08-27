import Foundation
import SwiftData

/// Persists screenplay evidence and deterministically folds it upward through
/// the story tree. Language models may identify candidate updates, but they do
/// not decide pacing scores or overwrite author-owned story fields.
@MainActor
enum DramaticProjectionEngine {
    static func markAllStale(in project: StoryProject) {
        for update in project.dramaticUpdates where update.status != .locked {
            update.status = .stale
            update.updatedAt = .now
        }
        for projection in project.narrativeProjections where projection.status != .accepted {
            projection.status = .stale
            projection.updatedAt = .now
        }
    }

    static func markSceneStale(
        sceneRecordID: UUID,
        in project: StoryProject
    ) {
        let affectedIDs = Set(
            project.dramaticUpdates
                .filter { $0.sceneRecordID == sceneRecordID && $0.status != .locked }
                .map(\.id)
        )
        for projection in project.narrativeProjections
        where projection.status != .accepted
            && projection.scope == .scene
            && projection.scopeKey == sceneRecordID.uuidString {
            projection.status = .stale
            projection.updatedAt = .now
        }
        guard !affectedIDs.isEmpty else { return }

        for update in project.dramaticUpdates
        where affectedIDs.contains(update.id) {
            update.status = .stale
            update.updatedAt = .now
        }
        for projection in project.narrativeProjections
        where projection.status != .accepted
            && !affectedIDs.isDisjoint(with: projection.evidenceIDs) {
            projection.status = .stale
            projection.updatedAt = .now
        }
    }

    @discardableResult
    static func apply(
        _ analysis: DramaticSceneAnalysis,
        sceneText: String,
        sceneRecordID: UUID,
        sceneContract: SceneContract?,
        durationSeconds: Double,
        sceneDurations: [UUID: Double],
        project: StoryProject,
        context: ModelContext
    ) throws -> [DramaticUpdateRecord] {
        var records: [DramaticUpdateRecord] = []
        try ProjectPersistenceStore.transaction(in: context) {
            markSceneStale(sceneRecordID: sceneRecordID, in: project)
        let revision = ScreenplayReviewEngine.fingerprint(sceneText)
        var parentID = currentUpdates(in: project)
            .filter { $0.sceneRecordID != sceneRecordID }
            .sorted(by: updateOrder)
            .last?.id

        for (index, update) in analysis.updates.enumerated() {
            let anchor = DramaticAnchorResolver.anchor(
                quotedText: update.sourceQuote,
                sceneText: sceneText,
                sceneRecordID: sceneRecordID,
                sceneContractID: sceneContract?.id
            )
            let record = DramaticUpdateRecord(
                sceneRecordID: sceneRecordID,
                sceneContractID: sceneContract?.id,
                structureStageIndex: sceneContract?.structureStageIndex,
                sceneIndex: sceneContract?.sceneIndex,
                ordinal: index,
                carrier: update.carrier,
                actionVerb: update.actionVerb,
                summary: update.summary,
                actor: update.actor,
                target: update.target,
                intention: update.intention,
                resistance: update.resistance,
                outcome: update.outcome,
                mutations: update.mutations,
                sourceAnchor: anchor,
                causalParentIDs: parentID.map { [$0] } ?? [],
                origin: .extracted,
                status: .analyzed,
                confidence: update.confidence,
                salience: update.salience,
                irreversibility: update.irreversibility,
                sourceRevision: revision,
                analysisModel: analysis.modelLabel
            )
            record.project = project
            context.insert(record)
            records.append(record)
            parentID = record.id
        }

        context.processPendingChanges()
        var durations = sceneDurations
        durations[sceneRecordID] = durationSeconds
        refresh(project: project, sceneDurations: durations, context: context)
        if records.isEmpty {
            upsert(
                scope: .scene,
                scopeKey: sceneRecordID.uuidString,
                title: sceneContract.map { "第 \($0.sceneIndex) 场 · \($0.heading)" }
                    ?? "正文场景",
                summary: analysis.realizedSceneSummary.nonempty
                    ?? "本场没有实现可验证的情境更新。",
                entryState: sceneContract?.stateContract.entrySnapshot ?? "",
                exitState: sceneContract?.stateContract.entrySnapshot ?? "",
                intentSummary: sceneIntent(sceneContract),
                realizationGap: sceneContract == nil
                    ? ""
                    : "场景契约存在，但正文尚未实现可验证的情境更新。",
                updates: [],
                duration: durationSeconds,
                project: project,
                context: context
            )
            context.processPendingChanges()
            if let projection = project.narrativeProjections.first(where: {
                $0.scope == .scene
                    && $0.scopeKey == sceneRecordID.uuidString
                    && $0.status != .accepted
            }) {
                projection.sourceRevision = revision
            }
        }
        project.touch()
            StoryCompiler.updateFindings(project: project, in: context)
        }
        return records
    }

    static func refresh(
        project: StoryProject,
        sceneDurations: [UUID: Double],
        context: ModelContext
    ) {
        let updates = currentUpdates(in: project).sorted(by: updateOrder)
        let contracts = Dictionary(
            uniqueKeysWithValues: project.sceneContracts.map { ($0.id, $0) }
        )
        var refreshedKeys = Set<String>()

        let sceneGroups = Dictionary(grouping: updates) { $0.sceneRecordID }
        for (sceneID, group) in sceneGroups {
            guard let sceneID else { continue }
            let sorted = group.sorted { $0.ordinal < $1.ordinal }
            let contract = sorted.compactMap { update in
                update.sceneContractID.flatMap { contracts[$0] }
            }.first
            let duration = sceneDurations[sceneID] ?? 60
            let reduction = DramaticStateReducer.reduce(sorted)
            let key = key(.scene, sceneID.uuidString)
            refreshedKeys.insert(key)
            upsert(
                scope: .scene,
                scopeKey: sceneID.uuidString,
                title: contract.map { "第 \($0.sceneIndex) 场 · \($0.heading)" }
                    ?? "正文场景",
                summary: causalSummary(sorted),
                entryState: contract?.stateContract.entrySnapshot
                    .nonempty ?? DramaticStateReducer.stateDescription(reduction.entryState),
                exitState: DramaticStateReducer.stateDescription(reduction.exitState),
                intentSummary: sceneIntent(contract),
                realizationGap: realizationGap(contract: contract, updates: sorted),
                updates: sorted,
                duration: duration,
                project: project,
                context: context
            )
        }

        let stageGroups = Dictionary(grouping: updates) { $0.structureStageIndex }
        for (stageIndex, group) in stageGroups {
            guard let stageIndex else { continue }
            let sorted = group.sorted(by: updateOrder)
            let key = key(.stage, String(stageIndex))
            refreshedKeys.insert(key)
            let stage = project.structureTemplate.stages.indices.contains(stageIndex)
                ? project.structureTemplate.stages[stageIndex]
                : nil
            upsert(
                scope: .stage,
                scopeKey: String(stageIndex),
                title: stage?.name ?? "大节拍 \(stageIndex + 1)",
                summary: causalSummary(sorted, limit: 10),
                entryState: contractsFor(sorted, contracts: contracts)
                    .first?.stateContract.entrySnapshot ?? "",
                exitState: contractsFor(sorted, contracts: contracts)
                    .last?.stateContract.exitSnapshot ?? "",
                intentSummary: stage?.purpose ?? "",
                realizationGap: sorted.isEmpty ? "正文尚无情境更新证据。" : "",
                updates: sorted,
                duration: duration(of: sorted, sceneDurations: sceneDurations),
                project: project,
                context: context
            )
        }

        if !updates.isEmpty {
            let reduction = DramaticStateReducer.reduce(updates)
            refreshedKeys.insert(key(.project, "root"))
            upsert(
                scope: .project,
                scopeKey: "root",
                title: "正文实证的一句话故事",
                summary: projectSummary(updates),
                entryState: DramaticStateReducer.stateDescription(reduction.entryState),
                exitState: DramaticStateReducer.stateDescription(reduction.exitState),
                intentSummary: project.logline,
                realizationGap: projectGap(project: project, updates: updates),
                updates: updates,
                duration: sceneDurations.values.reduce(0, +),
                project: project,
                context: context,
                status: .proposed
            )
        }

        for character in project.characters {
            let name = character.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let evidence = updates.filter { update in
                update.actor.semanticContains(name)
                    || update.target.semanticContains(name)
                    || update.mutations.contains {
                        $0.holder.semanticContains(name)
                            || $0.subject.semanticContains(name)
                            || $0.observerNames.contains { $0.semanticContains(name) }
                    }
            }
            guard !evidence.isEmpty else { continue }
            refreshedKeys.insert(key(.character, character.id.uuidString))
            upsert(
                scope: .character,
                scopeKey: character.id.uuidString,
                title: "\(name)的正文轨迹",
                summary: causalSummary(evidence, limit: 10),
                entryState: "人物设定：\(character.externalGoal)",
                exitState: characterExit(name: name, updates: evidence),
                intentSummary: [character.externalGoal, character.internalNeed, character.arc]
                    .filter { !$0.semanticBlank }.joined(separator: "；"),
                realizationGap: "",
                updates: evidence,
                duration: duration(of: evidence, sceneDurations: sceneDurations),
                project: project,
                context: context
            )
        }

        refreshDomain(
            scope: .relationship,
            title: "关系与权力的实际变化",
            dimensions: [.relationship],
            updates: updates,
            project: project,
            sceneDurations: sceneDurations,
            refreshedKeys: &refreshedKeys,
            context: context
        )
        refreshDomain(
            scope: .world,
            title: "正文已经建立的世界事实",
            dimensions: [.world],
            updates: updates,
            project: project,
            sceneDurations: sceneDurations,
            refreshedKeys: &refreshedKeys,
            context: context
        )
        refreshDomain(
            scope: .theme,
            title: "被行动检验的主题命题",
            dimensions: [.norm, .goal, .relationship],
            updates: updates,
            project: project,
            sceneDurations: sceneDurations,
            refreshedKeys: &refreshedKeys,
            context: context,
            intent: project.themeText.nonempty ?? project.themeBibleText
        )

        let conflictEvidence = updates.filter { !$0.resistance.semanticBlank }
        if !conflictEvidence.isEmpty {
            refreshedKeys.insert(key(.conflict, "root"))
            upsert(
                scope: .conflict,
                scopeKey: "root",
                title: "正文正在运行的冲突",
                summary: conflictEvidence.prefix(12).map {
                    "\($0.actor.nonempty ?? "行动者")要\($0.intention.nonempty ?? "改变局面")，但\($0.resistance)"
                }.joined(separator: " → "),
                entryState: "",
                exitState: conflictEvidence.last?.outcome ?? "",
                intentSummary: project.coreConflictText,
                realizationGap: "",
                updates: conflictEvidence,
                duration: duration(of: conflictEvidence, sceneDurations: sceneDurations),
                project: project,
                context: context
            )
        }

        for projection in project.narrativeProjections
        where projection.status != .accepted
            && !refreshedKeys.contains(key(projection.scope, projection.scopeKey)) {
            projection.status = .stale
            projection.updatedAt = .now
        }
    }

    static func projection(
        _ scope: NarrativeProjectionScope,
        key scopeKey: String,
        in project: StoryProject
    ) -> NarrativeProjectionRecord? {
        project.narrativeProjections
            .filter {
                $0.scope == scope && $0.scopeKey == scopeKey && $0.status != .stale
            }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private static func currentUpdates(in project: StoryProject) -> [DramaticUpdateRecord] {
        project.dramaticUpdates.filter { $0.status != .stale && $0.isEffective }
    }

    private static func refreshDomain(
        scope: NarrativeProjectionScope,
        title: String,
        dimensions: Set<DramaticStateDimension>,
        updates: [DramaticUpdateRecord],
        project: StoryProject,
        sceneDurations: [UUID: Double],
        refreshedKeys: inout Set<String>,
        context: ModelContext,
        intent: String = ""
    ) {
        let evidence = updates.filter { update in
            update.mutations.contains { dimensions.contains($0.dimension) }
        }
        guard !evidence.isEmpty else { return }
        refreshedKeys.insert(key(scope, "root"))
        let states = evidence.flatMap(\.mutations).filter {
            dimensions.contains($0.dimension) && $0.isEffective
        }
        upsert(
            scope: scope,
            scopeKey: "root",
            title: title,
            summary: states.prefix(14).map {
                "\($0.subject)：\($0.beforeValue) → \($0.afterValue)"
            }.joined(separator: "；"),
            entryState: "",
            exitState: states.suffix(8).map { "\($0.subject)＝\($0.afterValue)" }
                .joined(separator: "\n"),
            intentSummary: intent,
            realizationGap: "",
            updates: evidence,
            duration: duration(of: evidence, sceneDurations: sceneDurations),
            project: project,
            context: context
        )
    }

    private static func upsert(
        scope: NarrativeProjectionScope,
        scopeKey: String,
        title: String,
        summary: String,
        entryState: String,
        exitState: String,
        intentSummary: String,
        realizationGap: String,
        updates: [DramaticUpdateRecord],
        duration: Double,
        project: StoryProject,
        context: ModelContext,
        status: NarrativeProjectionStatus = .current
    ) {
        let revision = updates.map(\.sourceRevision).joined(separator: "|")
        let metrics = DramaticStateReducer.metrics(
            for: updates,
            durationSeconds: duration
        )
        if let existing = project.narrativeProjections.first(where: {
            $0.scope == scope && $0.scopeKey == scopeKey && $0.status != .accepted
        }) {
            existing.title = title
            existing.summary = summary.nonempty ?? "尚未形成可归纳的变化链。"
            existing.entryState = entryState
            existing.exitState = exitState
            existing.intentSummary = intentSummary
            existing.realizationGap = realizationGap
            existing.evidenceIDs = updates.map(\.id)
            existing.metrics = metrics
            existing.sourceRevision = revision
            existing.status = status
            existing.updatedAt = .now
        } else {
            let projection = NarrativeProjectionRecord(
                scope: scope,
                scopeKey: scopeKey,
                title: title,
                summary: summary.nonempty ?? "尚未形成可归纳的变化链。",
                entryState: entryState,
                exitState: exitState,
                intentSummary: intentSummary,
                realizationGap: realizationGap,
                evidenceIDs: updates.map(\.id),
                metrics: metrics,
                sourceRevision: revision,
                status: status
            )
            projection.project = project
            context.insert(projection)
        }
    }

    private static func contractsFor(
        _ updates: [DramaticUpdateRecord],
        contracts: [UUID: SceneContract]
    ) -> [SceneContract] {
        var seen = Set<UUID>()
        return updates.compactMap { update in
            guard let id = update.sceneContractID,
                  seen.insert(id).inserted else { return nil }
            return contracts[id]
        }
    }

    private static func causalSummary(
        _ updates: [DramaticUpdateRecord],
        limit: Int = 7
    ) -> String {
        updates.prefix(limit).map(\.summary).filter { !$0.semanticBlank }
            .joined(separator: " → ")
    }

    private static func projectSummary(_ updates: [DramaticUpdateRecord]) -> String {
        let pivotal = updates.sorted {
            $0.effectiveImpact > $1.effectiveImpact
        }.prefix(5).sorted(by: updateOrder)
        return causalSummary(Array(pivotal), limit: 5)
    }

    private static func sceneIntent(_ contract: SceneContract?) -> String {
        guard let contract else { return "" }
        return [
            contract.characterGoal,
            contract.obstacle,
            contract.turn,
            contract.outcome,
            contract.stateContract.audienceOutcome
        ].filter { !$0.semanticBlank }.joined(separator: "；")
    }

    private static func realizationGap(
        contract: SceneContract?,
        updates: [DramaticUpdateRecord]
    ) -> String {
        guard let contract else { return "" }
        guard !updates.isEmpty else { return "场景契约存在，但正文尚未实现可验证的情境更新。" }
        let required = contract.stateContract.requiredChanges
        guard !required.isEmpty else {
            return contract.outcome.semanticBlank ? "" : "已发现正文变化；旧场景契约尚未结构化为状态差异。"
        }
        let realized = updates.flatMap(\.mutations)
        let missing = required.filter { requirement in
            !realized.contains {
                $0.dimension == requirement.dimension
                    && ($0.subject.semanticContains(requirement.subject)
                        || requirement.subject.semanticContains($0.subject))
            }
        }
        return missing.isEmpty
            ? ""
            : "尚未验证：" + missing.map {
                "\($0.dimension.rawValue)·\($0.subject) → \($0.afterValue)"
            }.joined(separator: "；")
    }

    private static func projectGap(
        project: StoryProject,
        updates: [DramaticUpdateRecord]
    ) -> String {
        let stageCount = Set(updates.compactMap(\.structureStageIndex)).count
        let expected = project.structureTemplate.stages.count
        if expected > 0 && stageCount < expected {
            return "正文证据目前覆盖 \(stageCount)/\(expected) 个固定结构大节拍。"
        }
        return "该归纳只是一条正文实证提案，不会覆盖作者的一句话故事。"
    }

    private static func characterExit(
        name: String,
        updates: [DramaticUpdateRecord]
    ) -> String {
        updates.flatMap(\.mutations).filter {
            $0.holder.semanticContains(name) || $0.subject.semanticContains(name)
        }.suffix(8).map {
            "\($0.dimension.rawValue)：\($0.subject)＝\($0.afterValue)"
        }.joined(separator: "\n")
    }

    private static func duration(
        of updates: [DramaticUpdateRecord],
        sceneDurations: [UUID: Double]
    ) -> Double {
        Set(updates.compactMap(\.sceneRecordID)).reduce(0) {
            $0 + (sceneDurations[$1] ?? 60)
        }
    }

    private static func updateOrder(
        _ lhs: DramaticUpdateRecord,
        _ rhs: DramaticUpdateRecord
    ) -> Bool {
        let lhsStage = lhs.structureStageIndex ?? Int.max
        let rhsStage = rhs.structureStageIndex ?? Int.max
        if lhsStage != rhsStage { return lhsStage < rhsStage }
        let lhsIndex = lhs.sceneIndex ?? Int.max
        let rhsIndex = rhs.sceneIndex ?? Int.max
        if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
        let lhsScene = lhs.sceneContractID?.uuidString ?? lhs.sceneRecordID?.uuidString ?? ""
        let rhsScene = rhs.sceneContractID?.uuidString ?? rhs.sceneRecordID?.uuidString ?? ""
        if lhsScene != rhsScene { return lhsScene < rhsScene }
        return lhs.ordinal < rhs.ordinal
    }

    private static func key(_ scope: NarrativeProjectionScope, _ scopeKey: String) -> String {
        "\(scope.rawValue)|\(scopeKey)"
    }
}

private extension String {
    nonisolated var semanticBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    nonisolated var nonempty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    nonisolated func semanticContains(_ other: String) -> Bool {
        let lhs = folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        ).filter { !$0.isWhitespace }
        let rhs = other.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        ).filter { !$0.isWhitespace }
        return !lhs.isEmpty && !rhs.isEmpty && (lhs.contains(rhs) || rhs.contains(lhs))
    }
}
