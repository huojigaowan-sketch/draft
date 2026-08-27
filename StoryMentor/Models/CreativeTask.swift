import Foundation
import SwiftData

@Model
final class CreativeTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var prompt: String
    var constraintsText: String
    var rationale: String
    var difficulty: Int
    var statusRawValue: String
    var subjectID: UUID?
    var createdAt: Date
    var completedAt: Date?
    var project: StoryProject?

    init(
        id: UUID = UUID(),
        title: String,
        prompt: String,
        constraintsText: String = "",
        rationale: String = "",
        difficulty: Int = 1,
        status: CreativeTaskStatus = .proposed,
        subjectID: UUID? = nil,
        createdAt: Date = .now,
        completedAt: Date? = nil,
        project: StoryProject? = nil
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.constraintsText = constraintsText
        self.rationale = rationale
        self.difficulty = difficulty
        self.statusRawValue = status.rawValue
        self.subjectID = subjectID
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.project = project
    }
}

extension CreativeTask {
    var status: CreativeTaskStatus {
        get { CreativeTaskStatus(rawValue: statusRawValue) ?? .proposed }
        set {
            statusRawValue = newValue.rawValue
            completedAt = newValue == .completed ? .now : nil
        }
    }
}

