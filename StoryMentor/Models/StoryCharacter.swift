import Foundation
import SwiftData

@Model
final class StoryCharacter {
    @Attribute(.unique) var id: UUID
    var name: String
    var roleRawValue: String
    var age: String
    var occupation: String
    var seedText: String
    var background: String
    var externalGoal: String
    var internalNeed: String
    var fear: String
    var trauma: String
    var secret: String
    var falseBelief: String
    var flaw: String
    var strength: String
    var arc: String
    var createdAt: Date
    var updatedAt: Date
    var project: StoryProject?

    init(
        id: UUID = UUID(),
        name: String = "未命名人物",
        role: CharacterRole = .protagonist,
        age: String = "",
        occupation: String = "",
        seedText: String = "",
        background: String = "",
        externalGoal: String = "",
        internalNeed: String = "",
        fear: String = "",
        trauma: String = "",
        secret: String = "",
        falseBelief: String = "",
        flaw: String = "",
        strength: String = "",
        arc: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        project: StoryProject? = nil
    ) {
        self.id = id
        self.name = name
        self.roleRawValue = role.rawValue
        self.age = age
        self.occupation = occupation
        self.seedText = seedText
        self.background = background
        self.externalGoal = externalGoal
        self.internalNeed = internalNeed
        self.fear = fear
        self.trauma = trauma
        self.secret = secret
        self.falseBelief = falseBelief
        self.flaw = flaw
        self.strength = strength
        self.arc = arc
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.project = project
    }
}

extension StoryCharacter {
    var role: CharacterRole {
        get { CharacterRole(rawValue: roleRawValue) ?? .supporting }
        set { roleRawValue = newValue.rawValue }
    }

    var readinessFraction: Double {
        let values = [
            seedText,
            externalGoal,
            internalNeed,
            fear,
            falseBelief,
            flaw,
            arc
        ]
        let completed = values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        return Double(completed) / Double(values.count)
    }

    func touch() {
        updatedAt = .now
        project?.touch()
    }
}

enum CharacterRelationshipKind: String, CaseIterable, Codable, Identifiable {
    case family = "亲属"
    case love = "爱恋"
    case alliance = "同盟"
    case rivalry = "竞争"
    case control = "控制"
    case debt = "亏欠"
    case mentor = "师徒"
    case secret = "秘密关联"
    case hostility = "敌对"

    var id: String { rawValue }
}

struct CharacterRelationship: Codable, Identifiable, Hashable {
    var id: UUID
    var fromCharacterID: UUID
    var toCharacterID: UUID
    var kindRawValue: String
    var detail: String
    var tension: Int
    var isSecret: Bool

    init(
        id: UUID = UUID(),
        fromCharacterID: UUID,
        toCharacterID: UUID,
        kind: CharacterRelationshipKind = .alliance,
        detail: String = "",
        tension: Int = 50,
        isSecret: Bool = false
    ) {
        self.id = id
        self.fromCharacterID = fromCharacterID
        self.toCharacterID = toCharacterID
        kindRawValue = kind.rawValue
        self.detail = detail
        self.tension = tension
        self.isSecret = isSecret
    }

    var kind: CharacterRelationshipKind {
        get { CharacterRelationshipKind(rawValue: kindRawValue) ?? .alliance }
        set { kindRawValue = newValue.rawValue }
    }
}

struct CharacterGraphLayoutPoint: Codable, Hashable {
    var x: Double
    var y: Double
}

struct GraphCharacterProposal: Codable, Hashable {
    let name: String
    let role: String
    let seedText: String
    let externalGoal: String
    let secret: String

    private enum CodingKeys: String, CodingKey {
        case name, role, seedText, externalGoal, secret
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名人物"
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? CharacterRole.supporting.rawValue
        seedText = try container.decodeIfPresent(String.self, forKey: .seedText) ?? ""
        externalGoal = try container.decodeIfPresent(String.self, forKey: .externalGoal) ?? ""
        secret = try container.decodeIfPresent(String.self, forKey: .secret) ?? ""
    }
}

struct GraphCharacterChange: Codable, Hashable {
    let name: String
    let adjustment: String

    private enum CodingKeys: String, CodingKey { case name, adjustment }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        adjustment = try container.decodeIfPresent(String.self, forKey: .adjustment) ?? ""
    }
}

struct GraphRelationshipProposal: Codable, Hashable {
    let from: String
    let to: String
    let type: String
    let detail: String
    let tension: Int
    let isSecret: Bool

    private enum CodingKeys: String, CodingKey {
        case from, to, type, detail, tension, isSecret
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = try container.decodeIfPresent(String.self, forKey: .from) ?? ""
        to = try container.decodeIfPresent(String.self, forKey: .to) ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? CharacterRelationshipKind.alliance.rawValue
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        tension = min(100, max(0, try container.decodeIfPresent(Int.self, forKey: .tension) ?? 50))
        isSecret = try container.decodeIfPresent(Bool.self, forKey: .isSecret) ?? false
    }
}

struct CharacterGraphAdjustmentOption: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let thesis: String
    let newCharacters: [GraphCharacterProposal]
    let characterChanges: [GraphCharacterChange]
    let relationshipChanges: [GraphRelationshipProposal]
    let structureEffect: String
    let emotionalEffect: String
    let risk: String

    private enum CodingKeys: String, CodingKey {
        case id, title, thesis, newCharacters, characterChanges, relationshipChanges
        case structureEffect, emotionalEffect, risk
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "关系调整"
        thesis = try container.decodeIfPresent(String.self, forKey: .thesis) ?? ""
        newCharacters = try container.decodeIfPresent(
            [GraphCharacterProposal].self,
            forKey: .newCharacters
        ) ?? []
        characterChanges = try container.decodeIfPresent(
            [GraphCharacterChange].self,
            forKey: .characterChanges
        ) ?? []
        relationshipChanges = try container.decodeIfPresent(
            [GraphRelationshipProposal].self,
            forKey: .relationshipChanges
        ) ?? []
        structureEffect = try container.decodeIfPresent(String.self, forKey: .structureEffect) ?? ""
        emotionalEffect = try container.decodeIfPresent(String.self, forKey: .emotionalEffect) ?? ""
        risk = try container.decodeIfPresent(String.self, forKey: .risk) ?? ""
    }
}

struct CharacterGraphOptionsResult: Codable, Hashable {
    let question: String
    let coachNote: String
    let options: [CharacterGraphAdjustmentOption]

    private enum CodingKeys: String, CodingKey { case question, coachNote, options }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        question = try container.decodeIfPresent(String.self, forKey: .question) ?? "哪一种人物关系更能推动全本？"
        coachNote = try container.decodeIfPresent(String.self, forKey: .coachNote) ?? ""
        options = try container.decodeIfPresent(
            [CharacterGraphAdjustmentOption].self,
            forKey: .options
        ) ?? []
    }
}

struct CharacterGraphRevision: Codable, Identifiable, Hashable {
    let id: UUID
    let optionTitle: String
    let authorInstruction: String
    let relationshipsBefore: [CharacterRelationship]
    let createdAt: Date

    init(
        optionTitle: String,
        authorInstruction: String,
        relationshipsBefore: [CharacterRelationship]
    ) {
        id = UUID()
        self.optionTitle = optionTitle
        self.authorInstruction = authorInstruction
        self.relationshipsBefore = relationshipsBefore
        createdAt = .now
    }
}
