import Foundation
import SwiftData

@Model
final class KnowledgeDocument {
    @Attribute(.unique) var id: UUID
    var title: String
    var sourceFilename: String
    var sourceType: String = "pdf"
    var sourceFingerprint: String = ""
    var importedAt: Date
    var pageCount: Int
    var sectionCount: Int = 0
    var characterCount: Int
    var indexedChunkCount: Int = 0
    var topicSummary: String = ""

    @Relationship(deleteRule: .cascade, inverse: \KnowledgeChunk.document)
    var chunks: [KnowledgeChunk] = []

    init(
        id: UUID = UUID(),
        title: String,
        sourceFilename: String,
        sourceType: String = "pdf",
        sourceFingerprint: String = "",
        importedAt: Date = .now,
        pageCount: Int,
        sectionCount: Int = 0,
        characterCount: Int,
        indexedChunkCount: Int = 0,
        topicSummary: String = ""
    ) {
        self.id = id
        self.title = title
        self.sourceFilename = sourceFilename
        self.sourceType = sourceType
        self.sourceFingerprint = sourceFingerprint
        self.importedAt = importedAt
        self.pageCount = pageCount
        self.sectionCount = sectionCount
        self.characterCount = characterCount
        self.indexedChunkCount = indexedChunkCount
        self.topicSummary = topicSummary
    }
}

extension KnowledgeDocument {
    var totalChunkCount: Int {
        max(indexedChunkCount, chunks.count)
    }
}

@Model
final class KnowledgeChunk {
    @Attribute(.unique) var id: UUID
    var pageNumber: Int
    var sequence: Int
    var content: String
    var document: KnowledgeDocument?

    init(
        id: UUID = UUID(),
        pageNumber: Int,
        sequence: Int,
        content: String,
        document: KnowledgeDocument? = nil
    ) {
        self.id = id
        self.pageNumber = pageNumber
        self.sequence = sequence
        self.content = content
        self.document = document
    }
}
