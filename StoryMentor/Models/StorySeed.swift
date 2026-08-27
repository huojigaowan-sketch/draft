import Foundation
import SwiftData

struct DramaticElement: Codable, Identifiable, Hashable {
    let id: UUID
    let label: String
    let finding: String

    init(id: UUID = UUID(), label: String, finding: String) {
        self.id = id
        self.label = label
        self.finding = finding
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, finding
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        label = container.flexibleString(forKey: .label, fallback: "戏剧元素")
        finding = container.flexibleString(forKey: .finding)
    }
}

struct AdaptationDirection: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let genre: String
    let protagonist: String
    let desire: String
    let antagonistForce: String
    let stakes: String
    let dramaticQuestion: String
    let logline: String
    let fictionalizationNote: String
    let nextTaskTitle: String
    let nextTaskPrompt: String
    let evidenceBasis: [String]
    let sourceCount: Int
    let realityTexture: String

    init(
        id: UUID = UUID(),
        title: String,
        genre: String,
        protagonist: String,
        desire: String,
        antagonistForce: String,
        stakes: String,
        dramaticQuestion: String,
        logline: String,
        fictionalizationNote: String,
        nextTaskTitle: String,
        nextTaskPrompt: String,
        evidenceBasis: [String] = [],
        sourceCount: Int = 0,
        realityTexture: String = ""
    ) {
        self.id = id
        self.title = title
        self.genre = genre
        self.protagonist = protagonist
        self.desire = desire
        self.antagonistForce = antagonistForce
        self.stakes = stakes
        self.dramaticQuestion = dramaticQuestion
        self.logline = logline
        self.fictionalizationNote = fictionalizationNote
        self.nextTaskTitle = nextTaskTitle
        self.nextTaskPrompt = nextTaskPrompt
        self.evidenceBasis = evidenceBasis
        self.sourceCount = sourceCount
        self.realityTexture = realityTexture
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, genre, protagonist, desire, antagonistForce, stakes
        case dramaticQuestion, logline, fictionalizationNote, nextTaskTitle, nextTaskPrompt
        case evidenceBasis, sourceCount, realityTexture
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        title = container.flexibleString(forKey: .title, fallback: "未命名方向")
        genre = container.flexibleString(forKey: .genre, fallback: "剧情")
        protagonist = container.flexibleString(forKey: .protagonist)
        desire = container.flexibleString(forKey: .desire)
        antagonistForce = container.flexibleString(forKey: .antagonistForce)
        stakes = container.flexibleString(forKey: .stakes)
        dramaticQuestion = container.flexibleString(forKey: .dramaticQuestion)
        logline = container.flexibleString(forKey: .logline)
        fictionalizationNote = container.flexibleString(forKey: .fictionalizationNote)
        nextTaskTitle = container.flexibleString(forKey: .nextTaskTitle, fallback: "继续生长")
        nextTaskPrompt = container.flexibleString(forKey: .nextTaskPrompt)
        evidenceBasis = container.flexibleStringArray(forKey: .evidenceBasis)
        sourceCount = container.flexibleInt(forKey: .sourceCount)
        realityTexture = container.flexibleString(forKey: .realityTexture)
    }
}

struct DramatizationResult: Decodable {
    let factualSummary: String
    let dramaticCore: String
    let dramaticElements: [DramaticElement]
    let directions: [AdaptationDirection]
    let questions: [String]

    private enum CodingKeys: String, CodingKey {
        case factualSummary, dramaticCore, dramaticElements, directions, questions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        factualSummary = container.flexibleString(forKey: .factualSummary)
        dramaticCore = container.flexibleString(forKey: .dramaticCore)
        dramaticElements = container.flexibleArray(forKey: .dramaticElements)
        directions = container.flexibleArray(forKey: .directions)
        questions = container.flexibleStringArray(forKey: .questions)
    }
}

private extension KeyedDecodingContainer {
    func flexibleString(forKey key: Key, fallback: String = "") -> String {
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) { return String(value) }
        if let value = try? decode(Bool.self, forKey: key) { return value ? "true" : "false" }
        return fallback
    }

    func flexibleStringArray(forKey key: Key) -> [String] {
        if let values = try? decode([String].self, forKey: key) { return values }
        if let value = try? decode(String.self, forKey: key), !value.isEmpty { return [value] }
        return []
    }

    func flexibleInt(forKey key: Key) -> Int {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(Double.self, forKey: key) { return Int(value) }
        if let value = try? decode(String.self, forKey: key) {
            let digits = value.filter(\.isNumber)
            return Int(digits) ?? 0
        }
        return 0
    }

    func flexibleArray<Element: Decodable>(forKey key: Key) -> [Element] {
        if let values = try? decode([Element].self, forKey: key) { return values }
        if let value = try? decode(Element.self, forKey: key) { return [value] }
        return []
    }
}

@Model
final class StorySeed {
    @Attribute(.unique) var id: UUID
    var title: String
    var sourceTypeRawValue: String
    var sourceURL: String
    var sourceText: String
    var authorIntent: String
    var factualSummary: String
    var dramaticCore: String
    var dramaticElementsData: Data
    var directionsData: Data
    var questionsText: String
    var scienceLabData: Data = Data()
    var pendingExperimentData: Data = Data()
    var preparationNote: String
    var promptTokens: Int
    var completionTokens: Int
    var linkedProjectID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "未命名素材",
        sourceType: StorySourceType = .news,
        sourceURL: String = "",
        sourceText: String = "",
        authorIntent: String = "",
        projectID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.sourceTypeRawValue = sourceType.rawValue
        self.sourceURL = sourceURL
        self.sourceText = sourceText
        self.authorIntent = authorIntent
        self.factualSummary = ""
        self.dramaticCore = ""
        self.dramaticElementsData = Data()
        self.directionsData = Data()
        self.questionsText = ""
        self.preparationNote = ""
        self.promptTokens = 0
        self.completionTokens = 0
        self.linkedProjectID = projectID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension StorySeed {
    /// The owning aggregate root. `linkedProjectID` remains the persisted
    /// column name so existing SwiftData stores migrate without a rename.
    var projectID: UUID? {
        get { linkedProjectID }
        set { linkedProjectID = newValue }
    }

    func belongs(to projectID: UUID) -> Bool {
        linkedProjectID == projectID
    }

    var cultivationSnapshot: StoryCultivationSnapshot {
        get {
            PersistentPayloadCodec.decode(
                StoryCultivationSnapshot.self,
                from: scienceLabData,
                default: .empty(rawIdea: sourceText),
                label: "StorySeed.cultivationSnapshot"
            )
        }
        set {
            scienceLabData = PersistentPayloadCodec.encode(
                newValue,
                preserving: scienceLabData,
                label: "StorySeed.cultivationSnapshot"
            )
            updatedAt = .now
        }
    }

    var pendingExperimentCandidate: StoryExperimentCandidate? {
        get {
            PersistentPayloadCodec.decodeOptional(
                StoryExperimentCandidate.self,
                from: pendingExperimentData,
                label: "StorySeed.pendingExperimentCandidate"
            )
        }
        set {
            if let newValue {
                pendingExperimentData = PersistentPayloadCodec.encode(
                    newValue,
                    preserving: pendingExperimentData,
                    label: "StorySeed.pendingExperimentCandidate"
                )
            } else {
                pendingExperimentData = Data()
            }
            updatedAt = .now
        }
    }

    var sourceType: StorySourceType {
        get { StorySourceType(rawValue: sourceTypeRawValue) ?? .freeIdea }
        set { sourceTypeRawValue = newValue.rawValue }
    }

    var dramaticElements: [DramaticElement] {
        get {
            PersistentPayloadCodec.decode(
                [DramaticElement].self,
                from: dramaticElementsData,
                default: [],
                label: "StorySeed.dramaticElements"
            )
        }
        set {
            dramaticElementsData = PersistentPayloadCodec.encode(
                newValue,
                preserving: dramaticElementsData,
                label: "StorySeed.dramaticElements"
            )
        }
    }

    var directions: [AdaptationDirection] {
        get {
            PersistentPayloadCodec.decode(
                [AdaptationDirection].self,
                from: directionsData,
                default: [],
                label: "StorySeed.directions"
            )
        }
        set {
            directionsData = PersistentPayloadCodec.encode(
                newValue,
                preserving: directionsData,
                label: "StorySeed.directions"
            )
        }
    }

    var questions: [String] {
        questionsText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func apply(
        _ result: DramatizationResult,
        preparationNote: String,
        usage: TokenUsage
    ) {
        factualSummary = result.factualSummary
        dramaticCore = result.dramaticCore
        dramaticElements = result.dramaticElements
        directions = result.directions
        questionsText = result.questions.joined(separator: "\n")
        self.preparationNote = preparationNote
        promptTokens = usage.promptTokens
        completionTokens = usage.completionTokens
        updatedAt = .now
    }
}
