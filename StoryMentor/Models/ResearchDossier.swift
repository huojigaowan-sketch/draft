import Foundation
import SwiftData

enum ResearchDepth: String, CaseIterable, Codable, Identifiable, Sendable {
    case quick = "快速探索"
    case deep = "深度研究"
    case archive = "档案研究"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .quick: "快速建立事实底座"
        case .deep: "跨来源建立人物与制度关系"
        case .archive: "加入历史、书籍与学术回声"
        }
    }

    var sourceLimit: Int {
        switch self {
        case .quick: 12
        case .deep: 30
        case .archive: 50
        }
    }

    var systemImage: String {
        switch self {
        case .quick: "bolt.fill"
        case .deep: "point.3.filled.connected.trianglepath.dotted"
        case .archive: "archivebox.fill"
        }
    }
}

enum ResearchDossierStatus: String, Codable {
    case draft
    case researching
    case ready
    case failed
}

struct ResearchSourceRecord: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let url: String
    let publisher: String
    let publishedAt: String
    let kind: String
    let snippet: String
    let query: String
    let reliability: Double
    let provider: String
}

struct EvidenceClaim: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let text: String
    let dimension: String
    let confidence: Double
    let sourceIDs: [UUID]
}

struct ResearchEntity: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let kind: String
    let detail: String
    let sourceIDs: [UUID]
}

struct ResearchTimelineItem: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let date: String
    let event: String
    let sourceIDs: [UUID]
}

struct DramaticPressure: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let question: String
    let angle: String
    let sourceIDs: [UUID]
}

struct ResearchCoverageDimension: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let score: Double
    let note: String
}

struct RealityResearchResult: Codable, Hashable, Sendable {
    let summary: String
    let sources: [ResearchSourceRecord]
    let claims: [EvidenceClaim]
    let entities: [ResearchEntity]
    let timeline: [ResearchTimelineItem]
    let analogues: [String]
    let dramaticPressures: [DramaticPressure]
    let openQuestions: [String]
    let coverage: [ResearchCoverageDimension]
    let providers: [String]
    let promptContext: String
    let backendNote: String

    var averageCoverage: Double {
        guard !coverage.isEmpty else { return 0 }
        return coverage.reduce(0) { $0 + $1.score } / Double(coverage.count)
    }
}

@Model
final class ResearchDossier {
    @Attribute(.unique) var id: UUID
    var title: String
    var query: String
    var sourceURL: String
    var sourceText: String
    var authorIntent: String
    var depthRawValue: String
    var statusRawValue: String
    var resultData: Data
    var errorMessage: String
    var linkedSeedID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "未命名调查",
        query: String = "",
        sourceURL: String = "",
        sourceText: String = "",
        authorIntent: String = "",
        depth: ResearchDepth = .deep,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.query = query
        self.sourceURL = sourceURL
        self.sourceText = sourceText
        self.authorIntent = authorIntent
        self.depthRawValue = depth.rawValue
        self.statusRawValue = ResearchDossierStatus.draft.rawValue
        self.resultData = Data()
        self.errorMessage = ""
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@MainActor
extension ResearchDossier {
    var depth: ResearchDepth {
        get { ResearchDepth(rawValue: depthRawValue) ?? .deep }
        set { depthRawValue = newValue.rawValue }
    }

    var status: ResearchDossierStatus {
        get { ResearchDossierStatus(rawValue: statusRawValue) ?? .draft }
        set { statusRawValue = newValue.rawValue }
    }

    var result: RealityResearchResult? {
        get {
            PersistentPayloadCodec.decodeOptional(
                RealityResearchResult.self,
                from: resultData,
                label: "ResearchDossier.result"
            )
        }
        set {
            if let newValue {
                resultData = PersistentPayloadCodec.encode(
                    newValue,
                    preserving: resultData,
                    label: "ResearchDossier.result"
                )
            } else {
                resultData = Data()
            }
        }
    }

    func beginResearch() {
        status = .researching
        errorMessage = ""
        updatedAt = .now
    }

    func apply(_ result: RealityResearchResult) {
        self.result = result
        status = .ready
        errorMessage = ""
        updatedAt = .now
    }

    func fail(_ error: Error) {
        status = .failed
        errorMessage = error.localizedDescription
        updatedAt = .now
    }
}
