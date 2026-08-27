import Foundation

nonisolated struct DramaticStateValue: Codable, Hashable, Identifiable, Sendable {
    var id: String { key }
    var key: String
    var dimension: DramaticStateDimension
    var subject: String
    var holder: String
    var value: String
    var truthStatus: DramaticTruthStatus
    var observerNames: [String]
    var lastUpdateID: UUID
}

nonisolated struct DramaticStateConflict: Identifiable, Hashable, Sendable {
    let id: String
    let updateID: UUID
    let stateKey: String
    let expectedBefore: String
    let actualBefore: String
    let detail: String
}

nonisolated struct DramaticReductionResult: Sendable {
    let entryState: [DramaticStateValue]
    let exitState: [DramaticStateValue]
    let conflicts: [DramaticStateConflict]
}

enum DramaticStateReducer {
    static func reduce(
        _ updates: [DramaticUpdateRecord],
        initialState: [DramaticStateValue] = []
    ) -> DramaticReductionResult {
        var state = Dictionary(uniqueKeysWithValues: initialState.map { ($0.key, $0) })
        let entry = initialState
        var conflicts: [DramaticStateConflict] = []

        for update in updates.sorted(by: updateOrder) where update.status != .stale {
            for mutation in update.mutations where mutation.isEffective {
                let key = mutation.stateKey
                if let current = state[key],
                   !mutation.beforeValue.semanticEquivalent(to: current.value),
                   !mutation.beforeValue.semanticUnknown {
                    conflicts.append(
                        DramaticStateConflict(
                            id: "\(update.id.uuidString)-\(mutation.id.uuidString)",
                            updateID: update.id,
                            stateKey: key,
                            expectedBefore: mutation.beforeValue,
                            actualBefore: current.value,
                            detail: "“\(mutation.subject)”在本次更新前被分析为“\(mutation.beforeValue)”，但此前状态已经是“\(current.value)”。"
                        )
                    )
                }

                state[key] = DramaticStateValue(
                    key: key,
                    dimension: mutation.dimension,
                    subject: mutation.subject,
                    holder: mutation.holder,
                    value: mutation.afterValue,
                    truthStatus: mutation.truthStatus,
                    observerNames: mutation.observerNames,
                    lastUpdateID: update.id
                )
            }
        }

        return DramaticReductionResult(
            entryState: entry,
            exitState: state.values.sorted(by: stateOrder),
            conflicts: conflicts
        )
    }

    static func metrics(
        for updates: [DramaticUpdateRecord],
        durationSeconds: Double
    ) -> SemanticPacingMetrics {
        let current = updates.filter { $0.status != .stale }
        let effective = current.filter(\.isEffective)
        let safeDuration = max(durationSeconds, 1)
        let impact = effective.reduce(0) { $0 + $1.effectiveImpact }
        let resistanceCount = effective.count {
            !$0.resistance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let audienceCount = effective.count { update in
            update.mutations.contains { $0.dimension == .audience }
        }

        return SemanticPacingMetrics(
            durationSeconds: max(durationSeconds, 0),
            updateCount: current.count,
            effectiveUpdateCount: effective.count,
            updateDensity: impact / (safeDuration / 60),
            averageImpact: effective.isEmpty ? 0 : impact / Double(effective.count),
            resistanceIntensity: effective.isEmpty
                ? 0
                : Double(resistanceCount) / Double(effective.count),
            irreversibility: effective.isEmpty
                ? 0
                : effective.reduce(0) { $0 + $1.irreversibility }
                    / Double(effective.count),
            audienceInformationRate: Double(audienceCount) / (safeDuration / 60)
        )
    }

    static func stateDescription(
        _ state: [DramaticStateValue],
        limit: Int = 8
    ) -> String {
        state.prefix(limit).map { value in
            let owner = value.holder.trimmingCharacters(in: .whitespacesAndNewlines)
            let subject = owner.isEmpty ? value.subject : "\(owner)·\(value.subject)"
            return "\(value.dimension.rawValue)：\(subject)＝\(value.value)"
        }
        .joined(separator: "\n")
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
        if lhs.sceneRecordID == rhs.sceneRecordID {
            return lhs.ordinal < rhs.ordinal
        }
        let lhsScene = lhs.sourceAnchor.sceneRecordID?.uuidString ?? ""
        let rhsScene = rhs.sourceAnchor.sceneRecordID?.uuidString ?? ""
        if lhsScene != rhsScene { return lhsScene < rhsScene }
        return lhs.ordinal < rhs.ordinal
    }

    private static func stateOrder(
        _ lhs: DramaticStateValue,
        _ rhs: DramaticStateValue
    ) -> Bool {
        if lhs.dimension.rawValue == rhs.dimension.rawValue {
            return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
        }
        return dimensionRank(lhs.dimension) < dimensionRank(rhs.dimension)
    }

    private static func dimensionRank(_ dimension: DramaticStateDimension) -> Int {
        DramaticStateDimension.allCases.firstIndex(of: dimension) ?? .max
    }
}

extension String {
    fileprivate var semanticComparisonValue: String {
        folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        .components(separatedBy: .whitespacesAndNewlines)
        .joined()
        .trimmingCharacters(in: CharacterSet(charactersIn: "，。！？；：,.!?;:\"'“”‘’"))
    }

    fileprivate var semanticUnknown: Bool {
        let value = semanticComparisonValue
        return value.isEmpty
            || ["未知", "不明确", "尚未发生", "未建立", "未说明", "不适用"].contains(value)
    }

    fileprivate func semanticEquivalent(to other: String) -> Bool {
        let lhs = semanticComparisonValue
        let rhs = other.semanticComparisonValue
        return lhs == rhs || (!lhs.isEmpty && !rhs.isEmpty && (lhs.contains(rhs) || rhs.contains(lhs)))
    }
}
