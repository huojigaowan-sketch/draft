import Foundation

struct ScreenplayProjectionSyncResult {
    let text: String
    let changed: Bool
    let replacedPlaceholder: Bool
    let projectedSceneCount: Int
    let pendingContractIDs: Set<UUID>
}

/// Projects the canonical story/scene tree into the editable Fountain draft.
///
/// The projection is deliberately provenance-aware: upstream changes replace a
/// scene only while its text still matches the last projection. Once the author
/// edits that scene, the edit becomes authoritative and the upstream change is
/// reported as pending until the author explicitly asks to remap it.
@MainActor
enum ScreenplayProjectionEngine {
    private struct Projection {
        let contractID: UUID
        let sceneIndex: Int
        let heading: String
        let text: String
        let sourceFingerprint: String
        let textFingerprint: String
    }

    static func sourceSignature(for project: StoryProject) -> String {
        let projections = makeProjections(for: project)
        return fingerprint(
            projections.map {
                "\($0.contractID.uuidString):\($0.sourceFingerprint)"
            }
            .joined(separator: "|")
        )
    }

    static func synchronize(
        project: StoryProject,
        state: ScreenplayWorkspaceState,
        forceContractIDs: Set<UUID> = []
    ) -> ScreenplayProjectionSyncResult {
        let projections = makeProjections(for: project)
        guard !projections.isEmpty else {
            return ScreenplayProjectionSyncResult(
                text: project.screenplayText,
                changed: false,
                replacedPlaceholder: false,
                projectedSceneCount: 0,
                pendingContractIDs: []
            )
        }

        let originalText = project.screenplayText
        if isReplaceablePlaceholder(originalText) {
            let projectedText = projections.map(\.text)
                .joined(separator: "\n\n")
            let snapshots = FountainParser.scenes(in: projectedText)
            var records = state.reconcileScenes(snapshots)
            for offset in projections.indices
            where records.indices.contains(offset) {
                records[offset].sceneContractID = projections[offset].contractID
                records[offset].lastProjectionSourceFingerprint =
                    projections[offset].sourceFingerprint
                records[offset].lastProjectedTextFingerprint =
                    projections[offset].textFingerprint
            }
            state.sceneRecords = records
            return ScreenplayProjectionSyncResult(
                text: projectedText,
                changed: projectedText != originalText,
                replacedPlaceholder: true,
                projectedSceneCount: projections.count,
                pendingContractIDs: []
            )
        }

        let workingText = removingDuplicateProjectionScenes(
            from: originalText,
            projections: projections,
            existingRecords: state.sceneRecords
        )
        let originalSnapshots = FountainParser.scenes(in: workingText)
        var records = state.reconcileScenes(originalSnapshots)
        bindRecords(
            &records,
            snapshots: originalSnapshots,
            projections: projections
        )
        state.sceneRecords = records

        var replacements: [(index: Int, projection: Projection)] = []
        var appended: [Projection] = []
        var mappedContractIDs = Set<UUID>()
        var pendingContractIDs = Set<UUID>()
        var targetOrders: [UUID: Int] = [:]

        for projection in projections {
            guard let record = records.first(where: {
                $0.sceneContractID == projection.contractID
            }), originalSnapshots.indices.contains(record.order) else {
                targetOrders[projection.contractID] = originalSnapshots.count
                    + appended.count
                appended.append(projection)
                mappedContractIDs.insert(projection.contractID)
                continue
            }

            targetOrders[projection.contractID] = record.order
            let snapshot = originalSnapshots[record.order]
            let currentTextFingerprint = fingerprint(snapshot.text)
            let sourceChanged = record.lastProjectionSourceFingerprint
                != projection.sourceFingerprint
            let forced = forceContractIDs.contains(projection.contractID)
            guard sourceChanged || forced else { continue }

            let stillMatchesLastProjection =
                record.lastProjectedTextFingerprint != nil
                && record.lastProjectedTextFingerprint == currentTextFingerprint
            let canAdoptProjection = forced
                || stillMatchesLastProjection
                || currentTextFingerprint == projection.textFingerprint
                || (record.lastProjectionSourceFingerprint == nil
                    && snapshot.isSkeleton)

            if canAdoptProjection {
                replacements.append((record.order, projection))
                mappedContractIDs.insert(projection.contractID)
            } else {
                pendingContractIDs.insert(projection.contractID)
            }
        }

        var synchronizedText = workingText
        for replacement in replacements.sorted(by: { $0.index > $1.index }) {
            synchronizedText = FountainParser.replacingScene(
                at: replacement.index,
                in: synchronizedText,
                with: replacement.projection.text
            )
        }
        for projection in appended {
            let separator = synchronizedText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ? "" : "\n\n"
            synchronizedText += separator + projection.text
        }

        let finalSnapshots = FountainParser.scenes(in: synchronizedText)
        var finalRecords = state.reconcileScenes(finalSnapshots)
        bindRecords(
            &finalRecords,
            snapshots: finalSnapshots,
            projections: projections
        )

        for projection in projections {
            guard let targetOrder = targetOrders[projection.contractID],
                  finalSnapshots.indices.contains(targetOrder),
                  let recordIndex = finalRecords.firstIndex(where: {
                      $0.order == targetOrder
                  }) else {
                continue
            }
            if finalRecords[recordIndex].sceneContractID == nil {
                finalRecords[recordIndex].sceneContractID = projection.contractID
            }
            guard finalRecords[recordIndex].sceneContractID == projection.contractID,
                  mappedContractIDs.contains(projection.contractID)
                    || fingerprint(finalSnapshots[targetOrder].text)
                        == projection.textFingerprint else {
                continue
            }
            finalRecords[recordIndex].lastProjectionSourceFingerprint =
                projection.sourceFingerprint
            finalRecords[recordIndex].lastProjectedTextFingerprint =
                projection.textFingerprint
        }
        state.sceneRecords = finalRecords

        return ScreenplayProjectionSyncResult(
            text: synchronizedText,
            changed: synchronizedText != originalText,
            replacedPlaceholder: false,
            projectedSceneCount: mappedContractIDs.count,
            pendingContractIDs: pendingContractIDs
        )
    }

    static func isReplaceablePlaceholder(_ text: String) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return true }
        let scenes = FountainParser.scenes(in: clean)
        guard scenes.count == 1,
              scenes[0].heading.contains("未定地点") else {
            return false
        }
        return scenes[0].text
            .components(separatedBy: .newlines)
            .dropFirst()
            .allSatisfy {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }

    static func fingerprint(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private static func makeProjections(
        for project: StoryProject
    ) -> [Projection] {
        project.sceneContracts
            .sorted { $0.sceneIndex < $1.sceneIndex }
            .map { contract in
                let text = SceneCompilationEngine.screenplayDraft(
                    for: contract,
                    project: project
                )
                let heading = FountainParser.scenes(in: text).first?.heading
                    ?? contract.heading
                return Projection(
                    contractID: contract.id,
                    sceneIndex: contract.sceneIndex,
                    heading: heading,
                    text: text,
                    sourceFingerprint: fingerprint(
                        "\(contract.id.uuidString)|\(contract.sceneIndex)|\(text)"
                    ),
                    textFingerprint: fingerprint(text)
                )
            }
    }

    /// Repairs exact duplicate scenes produced by older parsers that failed to
    /// recognize a valid localized heading and therefore appended the same
    /// untouched projection again on every synchronization. Only a projection
    /// whose complete text fingerprint is unique among current contracts is
    /// eligible, so two intentionally identical upstream scenes remain intact.
    private static func removingDuplicateProjectionScenes(
        from text: String,
        projections: [Projection],
        existingRecords: [ScreenplaySceneRecord]
    ) -> String {
        let snapshots = FountainParser.scenes(in: text)
        guard snapshots.count > 1 else { return text }
        let projectionsByText = Dictionary(
            grouping: projections,
            by: \.textFingerprint
        )
        var removedIndices = Set<Int>()

        for projection in projections
        where projectionsByText[projection.textFingerprint]?.count == 1 {
            let matchingIndices = snapshots.indices.filter { index in
                !removedIndices.contains(index)
                    && fingerprint(snapshots[index].text)
                        == projection.textFingerprint
            }
            guard matchingIndices.count > 1 else { continue }
            let linkedOrder = existingRecords.first {
                $0.sceneContractID == projection.contractID
            }?.order
            let keptIndex = linkedOrder.flatMap { order in
                matchingIndices.contains(order) ? order : nil
            } ?? matchingIndices[0]
            removedIndices.formUnion(
                matchingIndices.filter { $0 != keptIndex }
            )
        }

        guard !removedIndices.isEmpty else { return text }
        var lines = text.components(separatedBy: "\n")
        for index in removedIndices.sorted(by: >) {
            let scene = snapshots[index]
            guard scene.startLine >= 0,
                  scene.startLine < scene.endLine,
                  scene.endLine <= lines.count else { continue }
            lines.removeSubrange(scene.startLine..<scene.endLine)
        }
        while let last = lines.last,
              last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || FountainParser.isForcedPageBreak(last) {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private static func bindRecords(
        _ records: inout [ScreenplaySceneRecord],
        snapshots: [FountainSceneSnapshot],
        projections: [Projection]
    ) {
        let validContractIDs = Set(projections.map(\.contractID))
        for index in records.indices {
            if let contractID = records[index].sceneContractID,
               !validContractIDs.contains(contractID) {
                records[index].sceneContractID = nil
                records[index].lastProjectionSourceFingerprint = nil
                records[index].lastProjectedTextFingerprint = nil
            }
        }

        var claimedIDs = Set(records.compactMap(\.sceneContractID))
        for projection in projections where !claimedIDs.contains(projection.contractID) {
            let matchingRecordIndices = records.indices.filter { index in
                records[index].sceneContractID == nil
                    && canonicalHeading(records[index].heading)
                        == canonicalHeading(projection.heading)
            }
            if matchingRecordIndices.count == 1,
               let recordIndex = matchingRecordIndices.first {
                records[recordIndex].sceneContractID = projection.contractID
                claimedIDs.insert(projection.contractID)
            }
        }

        if records.count == projections.count {
            for offset in projections.indices
            where !claimedIDs.contains(projections[offset].contractID) {
                guard let recordIndex = records.firstIndex(where: {
                    $0.order == offset && $0.sceneContractID == nil
                }) else { continue }
                records[recordIndex].sceneContractID = projections[offset].contractID
                claimedIDs.insert(projections[offset].contractID)
            }
        }

        // `snapshots` is intentionally part of this boundary: callers bind only
        // records reconciled from the same parse. Corrupt legacy payloads decode
        // to an empty record set, so synchronization repairs them without a
        // launch-time assertion.
        records.removeAll {
            $0.order < 0 || $0.order >= snapshots.count
        }
    }

    private static func canonicalHeading(_ value: String) -> String {
        (FountainParser.localizedSceneHeading(value) ?? value)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            .filter { !$0.isWhitespace }
    }
}
