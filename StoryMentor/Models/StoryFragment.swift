import Foundation
import SwiftData

enum StoryFragmentKind: String, CaseIterable, Codable, Identifiable {
    case adaptationDirection = "改编方向"
    case storyChoice = "故事选项"
    case analysis = "AI诊断"
    case blueprint = "故事蓝图"
    case free = "自由碎片"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .adaptationDirection: "leaf.arrow.triangle.circlepath"
        case .storyChoice: "signpost.right.and.left.fill"
        case .analysis: "sparkles"
        case .blueprint: "tree.fill"
        case .free: "note.text.badge.plus"
        }
    }
}

@Model
final class StoryFragment {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var sourceID: String
    var title: String
    var content: String
    var kindRawValue: String
    var projectID: UUID?
    var projectTitle: String
    var tagsText: String
    var note: String
    var grownProjectID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        sourceID: String,
        title: String,
        content: String,
        kind: StoryFragmentKind,
        projectID: UUID? = nil,
        projectTitle: String = "",
        tagsText: String = "",
        note: String = "",
        grownProjectID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.sourceID = sourceID
        self.title = title
        self.content = content
        self.kindRawValue = kind.rawValue
        self.projectID = projectID
        self.projectTitle = projectTitle
        self.tagsText = tagsText
        self.note = note
        self.grownProjectID = grownProjectID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension StoryFragment {
    var kind: StoryFragmentKind {
        get { StoryFragmentKind(rawValue: kindRawValue) ?? .free }
        set { kindRawValue = newValue.rawValue }
    }

    var tags: [String] {
        tagsText
            .components(separatedBy: CharacterSet(charactersIn: "，,、\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

@MainActor
enum StoryFragmentCollector {
    static func contains(sourceID: String, in fragments: [StoryFragment]) -> Bool {
        fragments.contains { $0.sourceID == sourceID }
    }

    @discardableResult
    static func toggle(
        sourceID: String,
        title: String,
        content: String,
        kind: StoryFragmentKind,
        projectID: UUID? = nil,
        projectTitle: String = "",
        fragments: [StoryFragment],
        modelContext: ModelContext
    ) throws -> Bool {
        if let existing = fragments.first(where: { $0.sourceID == sourceID }) {
            modelContext.delete(existing)
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            return false
        }

        let fragment = StoryFragment(
            sourceID: sourceID,
            title: title,
            content: content,
            kind: kind,
            projectID: projectID,
            projectTitle: projectTitle
        )
        modelContext.insert(fragment)
        try ProjectPersistenceStore.savePendingChanges(in: modelContext)
        return true
    }
}
