import Foundation
import SwiftData

enum ScreenplaySceneStatus: String, CaseIterable, Codable, Identifiable {
    case outline = "待起草"
    case drafted = "初稿"
    case revised = "已细化"
    case approved = "锁定"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .outline: "circle.dashed"
        case .drafted: "pencil.line"
        case .revised: "checkmark.circle"
        case .approved: "lock.fill"
        }
    }
}

enum ScreenplaySceneLength: String, CaseIterable, Codable, Identifiable {
    case compact = "1–2页"
    case standard = "3–5页"
    case extended = "6–8页"

    var id: String { rawValue }

    var prompt: String {
        switch self {
        case .compact: "紧凑，约1至2页，尽快进入转折。"
        case .standard: "标准场景，约3至5页，完成完整的行动、反应与转折。"
        case .extended: "重要长场景，约6至8页，允许多轮策略变化，但不能松散。"
        }
    }
}

/// One author-selectable, Final Draft/Fountain-compatible realization of a
/// scene. Candidate sets live in the screenplay workspace metadata so they
/// survive navigation and relaunch, but they do not alter the screenplay until
/// the author explicitly selects one.
struct ScreenplaySceneDraftOption: Codable, Identifiable, Hashable {
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case approach
        case fountainText
        case scenePurpose
        case emotionalTurn
        case beatSummary
        case continuityWarnings
        case choicesForAuthor
        case modeRawValue
        case sourceSceneFingerprint
        case sourceUpstreamSignature
        case structureAnchor
        case knowledgeSources
        case generatedAt
    }

    let id: UUID
    var title: String
    var approach: String
    var fountainText: String
    var scenePurpose: String
    var emotionalTurn: String
    var beatSummary: [String]
    var continuityWarnings: [String]
    var choicesForAuthor: [String]
    var modeRawValue: String
    var sourceSceneFingerprint: String
    var sourceUpstreamSignature: String?
    var structureAnchor: String?
    var knowledgeSources: [String]?
    var generatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        approach: String,
        fountainText: String,
        scenePurpose: String,
        emotionalTurn: String,
        beatSummary: [String],
        continuityWarnings: [String],
        choicesForAuthor: [String],
        modeRawValue: String,
        sourceSceneFingerprint: String,
        sourceUpstreamSignature: String? = nil,
        structureAnchor: String = "",
        knowledgeSources: [String] = [],
        generatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.approach = approach
        self.fountainText = FountainParser.localizingSceneHeadings(
            in: fountainText
        )
        self.scenePurpose = scenePurpose
        self.emotionalTurn = emotionalTurn
        self.beatSummary = beatSummary
        self.continuityWarnings = continuityWarnings
        self.choicesForAuthor = choicesForAuthor
        self.modeRawValue = modeRawValue
        self.sourceSceneFingerprint = sourceSceneFingerprint
        self.sourceUpstreamSignature = sourceUpstreamSignature
        self.structureAnchor = structureAnchor
        self.knowledgeSources = knowledgeSources
        self.generatedAt = generatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedText = try container.decodeIfPresent(
            String.self,
            forKey: .fountainText
        ) ?? ""
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            title: try container.decodeIfPresent(String.self, forKey: .title)
                ?? "未命名方案",
            approach: try container.decodeIfPresent(
                String.self,
                forKey: .approach
            ) ?? "旧版候选，建议重新生成",
            fountainText: decodedText,
            scenePurpose: try container.decodeIfPresent(
                String.self,
                forKey: .scenePurpose
            ) ?? "",
            emotionalTurn: try container.decodeIfPresent(
                String.self,
                forKey: .emotionalTurn
            ) ?? "",
            beatSummary: try container.decodeIfPresent(
                [String].self,
                forKey: .beatSummary
            ) ?? [],
            continuityWarnings: try container.decodeIfPresent(
                [String].self,
                forKey: .continuityWarnings
            ) ?? [],
            choicesForAuthor: try container.decodeIfPresent(
                [String].self,
                forKey: .choicesForAuthor
            ) ?? [],
            modeRawValue: try container.decodeIfPresent(
                String.self,
                forKey: .modeRawValue
            ) ?? "起草本场",
            sourceSceneFingerprint: try container.decodeIfPresent(
                String.self,
                forKey: .sourceSceneFingerprint
            ) ?? ScreenplayDraftOptionPolicy.fingerprint(decodedText),
            sourceUpstreamSignature: try container.decodeIfPresent(
                String.self,
                forKey: .sourceUpstreamSignature
            ),
            structureAnchor: try container.decodeIfPresent(
                String.self,
                forKey: .structureAnchor
            ) ?? "",
            knowledgeSources: try container.decodeIfPresent(
                [String].self,
                forKey: .knowledgeSources
            ) ?? [],
            generatedAt: try container.decodeIfPresent(
                Date.self,
                forKey: .generatedAt
            ) ?? .now
        )
    }
}

enum ScreenplayDraftOptionPolicy {
    static let requiredOptionCount = 3

    static func fingerprint(_ value: String) -> String {
        let normalized = value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    static func isValidSet(_ options: [ScreenplaySceneDraftOption]) -> Bool {
        guard options.count == requiredOptionCount,
              Set(options.map(\.id)).count == requiredOptionCount,
              Set(options.map { fingerprint($0.fountainText) }).count
                == requiredOptionCount else {
            return false
        }
        return options.allSatisfy(isValidSceneOption)
    }

    static func applying(
        _ option: ScreenplaySceneDraftOption,
        to screenplayText: String,
        at sceneIndex: Int
    ) -> String? {
        let scenes = FountainParser.scenes(in: screenplayText)
        guard scenes.indices.contains(sceneIndex),
              isValidSceneOption(option) else {
            return nil
        }
        return FountainParser.replacingScene(
            at: sceneIndex,
            in: screenplayText,
            with: option.fountainText
        )
    }

    static func isProfessionalSceneText(_ text: String) -> Bool {
        let scenes = FountainParser.scenes(in: text)
        guard scenes.count == 1,
              let scene = scenes.first,
              !SceneCompilationEngine.needsProfessionalDraft(scene) else {
            return false
        }
        let visibleBody = FountainParser.paragraphs(in: scene.text)
            .dropFirst()
            .contains {
                !$0.trimmedText.isEmpty && $0.inferredType != .note
            }
        return visibleBody
    }

    private static func isValidSceneOption(
        _ option: ScreenplaySceneDraftOption
    ) -> Bool {
        let lines = option.fountainText.components(separatedBy: .newlines)
        guard let firstLine = lines.first(where: {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            return false
        }
        return !option.title.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
            && !option.approach.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
            && FountainParser.isSceneHeading(firstLine)
            && FountainParser.scenes(in: option.fountainText).count == 1
    }
}

struct ScreenplaySceneMetadata: Codable, Identifiable, Hashable {
    var id: String {
        sceneID?.uuidString ?? "legacy-scene-\(sceneIndex)"
    }
    var sceneID: UUID?
    var sceneIndex: Int
    var statusRawValue: String
    var lengthRawValue: String
    var emotionalTurn: String
    var aiNote: String
    var authorInstruction: String?
    var continuityWarnings: [String]?
    var choicesForAuthor: [String]?
    var paragraphElementAssignments: [ScreenplayParagraphElementAssignment]?
    var screenplayDraftOptions: [ScreenplaySceneDraftOption]?
    var selectedScreenplayDraftOptionID: UUID?
    var structureAnchor: String?
    var knowledgeSources: [String]?

    init(
        sceneID: UUID? = nil,
        sceneIndex: Int,
        status: ScreenplaySceneStatus = .outline,
        length: ScreenplaySceneLength = .standard,
        emotionalTurn: String = "",
        aiNote: String = "",
        authorInstruction: String = "",
        continuityWarnings: [String] = [],
        choicesForAuthor: [String] = [],
        paragraphElementAssignments: [ScreenplayParagraphElementAssignment] = [],
        screenplayDraftOptions: [ScreenplaySceneDraftOption] = [],
        selectedScreenplayDraftOptionID: UUID? = nil,
        structureAnchor: String = "",
        knowledgeSources: [String] = []
    ) {
        self.sceneID = sceneID
        self.sceneIndex = sceneIndex
        self.statusRawValue = status.rawValue
        self.lengthRawValue = length.rawValue
        self.emotionalTurn = emotionalTurn
        self.aiNote = aiNote
        self.authorInstruction = authorInstruction
        self.continuityWarnings = continuityWarnings
        self.choicesForAuthor = choicesForAuthor
        self.paragraphElementAssignments = paragraphElementAssignments
        self.screenplayDraftOptions = screenplayDraftOptions
        self.selectedScreenplayDraftOptionID = selectedScreenplayDraftOptionID
        self.structureAnchor = structureAnchor
        self.knowledgeSources = knowledgeSources
    }

    var status: ScreenplaySceneStatus {
        get { ScreenplaySceneStatus(rawValue: statusRawValue) ?? .outline }
        set { statusRawValue = newValue.rawValue }
    }

    var length: ScreenplaySceneLength {
        get { ScreenplaySceneLength(rawValue: lengthRawValue) ?? .standard }
        set { lengthRawValue = newValue.rawValue }
    }
}

/// A persistent identity for one screenplay scene.
///
/// The screenplay remains Fountain text, but UI selection, metadata and
/// cross-view synchronization use this UUID instead of a heading or array
/// position. Heading/body fingerprints are reconciliation hints only; they are
/// never exposed as identity or sort keys.
struct ScreenplaySceneRecord: Codable, Identifiable, Hashable {
    let id: UUID
    /// Stable link to the scene node in the story tree. `order` may change.
    var sceneContractID: UUID?
    /// Fingerprint of the upstream scene contract at the last successful
    /// projection. `nil` means this scene predates projection tracking or is
    /// author-owned.
    var lastProjectionSourceFingerprint: String?
    /// Fingerprint of the exact scene text written by the projection engine.
    /// Comparing it with the live scene lets upstream changes update untouched
    /// projections without ever silently overwriting an author's rewrite.
    var lastProjectedTextFingerprint: String?
    var order: Int
    var heading: String
    var headingFingerprint: String
    var bodyFingerprint: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        sceneContractID: UUID? = nil,
        lastProjectionSourceFingerprint: String? = nil,
        lastProjectedTextFingerprint: String? = nil,
        order: Int,
        heading: String,
        headingFingerprint: String,
        bodyFingerprint: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.sceneContractID = sceneContractID
        self.lastProjectionSourceFingerprint = lastProjectionSourceFingerprint
        self.lastProjectedTextFingerprint = lastProjectedTextFingerprint
        self.order = order
        self.heading = heading
        self.headingFingerprint = headingFingerprint
        self.bodyFingerprint = bodyFingerprint
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ScreenplayRevision: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let fountainText: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        fountainText: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.fountainText = fountainText
        self.createdAt = createdAt
    }
}

enum ScreenplayReviewKind: String, CaseIterable, Codable, Identifiable {
    case structure = "结构与场景"
    case continuity = "人物与连续性"
    case dialogue = "对白与节奏"
    case format = "格式与交付"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .structure: "point.3.connected.trianglepath.dotted"
        case .continuity: "person.2.badge.gearshape"
        case .dialogue: "quote.bubble"
        case .format: "checkmark.seal"
        }
    }

    var purpose: String {
        switch self {
        case .structure:
            "检查场景是否执行固定结构，每场是否改变局面，因果链是否闭合。"
        case .continuity:
            "检查人物目标、关系、知识状态、时间与空间是否前后一致。"
        case .dialogue:
            "检查对白是否承担策略、潜台词与节奏功能，而非解释已知信息。"
        case .format:
            "检查 Fountain 元素、占位符、场景标题和交付文件是否完整。"
        }
    }
}

enum ScreenplayReviewSeverity: String, Codable, CaseIterable {
    case blocker = "阻塞"
    case warning = "警告"
    case note = "提示"
}

struct ScreenplayReviewFinding: Codable, Identifiable, Hashable {
    let id: UUID
    var severityRawValue: String
    var title: String
    var detail: String
    var location: String

    init(
        id: UUID = UUID(),
        severity: ScreenplayReviewSeverity,
        title: String,
        detail: String,
        location: String
    ) {
        self.id = id
        severityRawValue = severity.rawValue
        self.title = title
        self.detail = detail
        self.location = location
    }

    var severity: ScreenplayReviewSeverity {
        get { ScreenplayReviewSeverity(rawValue: severityRawValue) ?? .warning }
        set { severityRawValue = newValue.rawValue }
    }
}

struct ScreenplayReviewRound: Codable, Identifiable, Hashable {
    let id: UUID
    var kindRawValue: String
    var screenplayFingerprint: String
    var summary: String
    var findings: [ScreenplayReviewFinding]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: ScreenplayReviewKind,
        screenplayFingerprint: String,
        summary: String,
        findings: [ScreenplayReviewFinding],
        createdAt: Date = .now
    ) {
        self.id = id
        kindRawValue = kind.rawValue
        self.screenplayFingerprint = screenplayFingerprint
        self.summary = summary
        self.findings = findings
        self.createdAt = createdAt
    }

    var kind: ScreenplayReviewKind {
        get { ScreenplayReviewKind(rawValue: kindRawValue) ?? .structure }
        set { kindRawValue = newValue.rawValue }
    }
}

@Model
final class ScreenplayWorkspaceState {
    @Attribute(.unique) var id: UUID
    var projectID: UUID
    var activeSceneIndex: Int
    var metadataData: Data
    var sceneRecordsData: Data = Data()
    var revisionsData: Data
    var activeSceneID: UUID?
    var generationStatus: String = "idle"
    var generationCompletedScenes: Int = 0
    var generationTotalScenes: Int = 0
    var generationCurrentScene: Int = 0
    var generationMessage: String = ""
    var generationStartedAt: Date?
    var generationFinishedAt: Date?
    var elementStylesData: Data = Data()
    var reviewRoundsData: Data = Data()
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        projectID: UUID,
        activeSceneIndex: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.projectID = projectID
        self.activeSceneIndex = activeSceneIndex
        self.metadataData = Data()
        self.sceneRecordsData = Data()
        self.revisionsData = Data()
        self.reviewRoundsData = Data()
        self.activeSceneID = nil
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@MainActor
extension ScreenplayWorkspaceState {
    var metadata: [ScreenplaySceneMetadata] {
        get {
            PersistentPayloadCodec.decode(
                [ScreenplaySceneMetadata].self,
                from: metadataData,
                default: [],
                label: "ScreenplayWorkspaceState.metadata"
            )
        }
        set {
            metadataData = PersistentPayloadCodec.encode(
                newValue,
                preserving: metadataData,
                label: "ScreenplayWorkspaceState.metadata"
            )
            updatedAt = .now
        }
    }

    var revisions: [ScreenplayRevision] {
        get {
            PersistentPayloadCodec.decode(
                [ScreenplayRevision].self,
                from: revisionsData,
                default: [],
                label: "ScreenplayWorkspaceState.revisions"
            )
        }
        set {
            revisionsData = PersistentPayloadCodec.encode(
                newValue,
                preserving: revisionsData,
                label: "ScreenplayWorkspaceState.revisions"
            )
            updatedAt = .now
        }
    }

    var reviewRounds: [ScreenplayReviewRound] {
        get {
            PersistentPayloadCodec.decode(
                [ScreenplayReviewRound].self,
                from: reviewRoundsData,
                default: [],
                label: "ScreenplayWorkspaceState.reviewRounds"
            )
        }
        set {
            reviewRoundsData = PersistentPayloadCodec.encode(
                newValue,
                preserving: reviewRoundsData,
                label: "ScreenplayWorkspaceState.reviewRounds"
            )
            updatedAt = .now
        }
    }

    func addReviewRound(_ round: ScreenplayReviewRound) {
        var all = reviewRounds
        all.insert(round, at: 0)
        reviewRounds = Array(all.prefix(24))
    }

    func latestReview(for kind: ScreenplayReviewKind) -> ScreenplayReviewRound? {
        reviewRounds
            .filter { $0.kind == kind }
            .max { $0.createdAt < $1.createdAt }
    }

    var sceneRecords: [ScreenplaySceneRecord] {
        get {
            PersistentPayloadCodec.decode(
                [ScreenplaySceneRecord].self,
                from: sceneRecordsData,
                default: [],
                label: "ScreenplayWorkspaceState.sceneRecords"
            )
        }
        set {
            sceneRecordsData = PersistentPayloadCodec.encode(
                newValue,
                preserving: sceneRecordsData,
                label: "ScreenplayWorkspaceState.sceneRecords"
            )
            updatedAt = .now
        }
    }

    var elementStyles: [ScreenplayElementStyleDefinition] {
        get {
            let decoded = PersistentPayloadCodec.decode(
                [ScreenplayElementStyleDefinition].self,
                from: elementStylesData,
                default: [],
                label: "ScreenplayWorkspaceState.elementStyles"
            )
            return decoded.isEmpty
                ? ScreenplayElementStyleDefinition.defaultStyles
                : decoded
        }
        set {
            elementStylesData = PersistentPayloadCodec.encode(
                newValue.isEmpty
                    ? ScreenplayElementStyleDefinition.defaultStyles
                    : newValue,
                preserving: elementStylesData,
                label: "ScreenplayWorkspaceState.elementStyles"
            )
            updatedAt = .now
        }
    }

    func sceneMetadata(at index: Int) -> ScreenplaySceneMetadata {
        let stableID = sceneRecords.first { $0.order == index }?.id
        return metadata.first {
            if let stableID {
                return $0.sceneID == stableID
                    || ($0.sceneID == nil && $0.sceneIndex == index)
            }
            return $0.sceneIndex == index
        } ?? ScreenplaySceneMetadata(sceneID: stableID, sceneIndex: index)
    }

    func updateScene(
        at index: Int,
        _ update: (inout ScreenplaySceneMetadata) -> Void
    ) {
        var all = metadata
        let stableID = sceneRecords.first { $0.order == index }?.id
        var item = all.first {
            if let stableID {
                return $0.sceneID == stableID
                    || ($0.sceneID == nil && $0.sceneIndex == index)
            }
            return $0.sceneIndex == index
        } ?? ScreenplaySceneMetadata(sceneID: stableID, sceneIndex: index)
        item.sceneID = stableID ?? item.sceneID
        item.sceneIndex = index
        update(&item)
        all.removeAll {
            if let stableID {
                return $0.sceneID == stableID
                    || ($0.sceneID == nil && $0.sceneIndex == index)
            }
            return $0.sceneIndex == index
        }
        all.append(item)
        metadata = all.sorted { $0.sceneIndex < $1.sceneIndex }
    }

    /// Reconciles parsed Fountain scenes with persistent scene identities.
    ///
    /// Matching uses exact heading/body fingerprints first, followed by a
    /// unique body or heading match and finally the previous position. This
    /// preserves identity when a heading is translated or edited, and also
    /// survives most insertions, deletions and reorder operations.
    @discardableResult
    func reconcileScenes(
        _ snapshots: [FountainSceneSnapshot]
    ) -> [ScreenplaySceneRecord] {
        let oldRecords = sceneRecords.sorted { $0.order < $1.order }
        var usedIDs = Set<UUID>()
        var reconciled: [ScreenplaySceneRecord?] = Array(
            repeating: nil,
            count: snapshots.count
        )

        let candidates = snapshots.map { snapshot in
            (
                heading: Self.fingerprint(snapshot.heading),
                body: Self.fingerprint(Self.sceneBody(snapshot.text))
            )
        }

        func unusedRecord(
            where predicate: (ScreenplaySceneRecord) -> Bool
        ) -> ScreenplaySceneRecord? {
            oldRecords.first { !usedIDs.contains($0.id) && predicate($0) }
        }

        // Exact match is strongest and safely handles reorder operations.
        for index in snapshots.indices {
            let value = candidates[index]
            if let record = unusedRecord(where: {
                $0.headingFingerprint == value.heading
                    && $0.bodyFingerprint == value.body
            }) {
                reconciled[index] = record
                usedIDs.insert(record.id)
            }
        }

        // A body match keeps the UUID stable while the heading is being edited.
        for index in snapshots.indices where reconciled[index] == nil {
            let body = candidates[index].body
            let matches = oldRecords.filter {
                !usedIDs.contains($0.id) && $0.bodyFingerprint == body
            }
            if matches.count == 1, let record = matches.first {
                reconciled[index] = record
                usedIDs.insert(record.id)
            }
        }

        // A heading match keeps identity while the body is rewritten.
        for index in snapshots.indices where reconciled[index] == nil {
            let heading = candidates[index].heading
            let matches = oldRecords.filter {
                !usedIDs.contains($0.id) && $0.headingFingerprint == heading
            }
            if matches.count == 1, let record = matches.first {
                reconciled[index] = record
                usedIDs.insert(record.id)
            }
        }

        // Last-resort positional reconciliation handles editing heading and
        // body in one autosave cycle without manufacturing a new identity.
        for index in snapshots.indices where reconciled[index] == nil {
            if let record = oldRecords.first(where: {
                $0.order == index && !usedIDs.contains($0.id)
            }) {
                reconciled[index] = record
                usedIDs.insert(record.id)
            }
        }

        let now = Date.now
        let finalRecords = snapshots.indices.map { index in
            let snapshot = snapshots[index]
            let fingerprints = candidates[index]
            if var record = reconciled[index] {
                record.order = index
                record.heading = snapshot.heading
                record.headingFingerprint = fingerprints.heading
                record.bodyFingerprint = fingerprints.body
                record.updatedAt = now
                return record
            }
            return ScreenplaySceneRecord(
                order: index,
                heading: snapshot.heading,
                headingFingerprint: fingerprints.heading,
                bodyFingerprint: fingerprints.body,
                updatedAt: now
            )
        }

        sceneRecords = finalRecords
        migrateMetadata(to: finalRecords)

        if let activeSceneID,
           let active = finalRecords.first(where: { $0.id == activeSceneID }) {
            activeSceneIndex = active.order
        } else if finalRecords.indices.contains(activeSceneIndex) {
            activeSceneID = finalRecords[activeSceneIndex].id
        } else {
            activeSceneID = nil
            activeSceneIndex = 0
        }
        return finalRecords
    }

    private func migrateMetadata(to records: [ScreenplaySceneRecord]) {
        let validIDs = Set(records.map(\.id))
        var migrated = metadata.compactMap { item -> ScreenplaySceneMetadata? in
            var value = item
            if let sceneID = value.sceneID {
                guard validIDs.contains(sceneID),
                      let order = records.first(where: { $0.id == sceneID })?.order else {
                    return nil
                }
                value.sceneIndex = order
                return value
            }
            guard records.indices.contains(value.sceneIndex) else {
                return nil
            }
            let record = records[value.sceneIndex]
            value.sceneID = record.id
            value.sceneIndex = record.order
            return value
        }
        migrated.sort { $0.sceneIndex < $1.sceneIndex }
        metadata = migrated
    }

    private static func sceneBody(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        guard lines.count > 1 else { return "" }
        return lines.dropFirst().joined(separator: "\n")
    }

    /// Deterministic FNV-1a rather than Swift's randomized `Hasher`, so stored
    /// fingerprints continue to work across launches.
    private static func fingerprint(_ value: String) -> String {
        let normalized = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    func addRevision(title: String, fountainText: String) {
        guard !fountainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        var all = revisions
        if all.first?.fountainText == fountainText { return }
        all.insert(
            ScreenplayRevision(title: title, fountainText: fountainText),
            at: 0
        )
        revisions = Array(all.prefix(20))
    }

    var generationProgress: Double {
        guard generationTotalScenes > 0 else { return 0 }
        return min(
            1,
            max(0, Double(generationCompletedScenes) / Double(generationTotalScenes))
        )
    }

    func beginGeneration(totalScenes: Int) {
        generationStatus = "running"
        generationCompletedScenes = 0
        generationTotalScenes = max(totalScenes, 0)
        generationCurrentScene = 0
        generationMessage = "正在准备逐场写作"
        generationStartedAt = .now
        generationFinishedAt = nil
        updatedAt = .now
    }

    func updateGeneration(
        completed: Int,
        current: Int,
        message: String
    ) {
        generationCompletedScenes = min(max(completed, 0), generationTotalScenes)
        generationCurrentScene = min(max(current, 0), generationTotalScenes)
        generationMessage = message
        updatedAt = .now
    }

    func finishGeneration(status: String, message: String) {
        generationStatus = status
        generationMessage = message
        if status == "completed" {
            generationCompletedScenes = generationTotalScenes
        }
        generationFinishedAt = .now
        updatedAt = .now
    }
}
