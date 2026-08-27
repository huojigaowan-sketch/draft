import Foundation
import SwiftData

@Model
final class AnalysisReport {
    @Attribute(.unique) var id: UUID
    var kindRawValue: String
    var subjectID: UUID?
    var score: Int
    var summary: String
    var strengthsText: String
    var gapsText: String
    var recommendationText: String
    var evidenceText: String
    var providerName: String
    var commercialPatternsText: String = ""
    var theoryBasisText: String = ""
    var antagonistSuggestion: String = ""
    var nextTaskTitle: String = ""
    var nextTaskPrompt: String = ""
    var questionsText: String = ""
    var localPreparationNote: String = ""
    var promptTokens: Int = 0
    var completionTokens: Int = 0
    var createdAt: Date
    var project: StoryProject?

    init(
        id: UUID = UUID(),
        kind: AnalysisKind,
        subjectID: UUID? = nil,
        score: Int,
        summary: String,
        strengthsText: String = "",
        gapsText: String = "",
        recommendationText: String = "",
        evidenceText: String = "",
        providerName: String,
        commercialPatternsText: String = "",
        theoryBasisText: String = "",
        antagonistSuggestion: String = "",
        nextTaskTitle: String = "",
        nextTaskPrompt: String = "",
        questionsText: String = "",
        localPreparationNote: String = "",
        promptTokens: Int = 0,
        completionTokens: Int = 0,
        createdAt: Date = .now,
        project: StoryProject? = nil
    ) {
        self.id = id
        self.kindRawValue = kind.rawValue
        self.subjectID = subjectID
        self.score = score
        self.summary = summary
        self.strengthsText = strengthsText
        self.gapsText = gapsText
        self.recommendationText = recommendationText
        self.evidenceText = evidenceText
        self.providerName = providerName
        self.commercialPatternsText = commercialPatternsText
        self.theoryBasisText = theoryBasisText
        self.antagonistSuggestion = antagonistSuggestion
        self.nextTaskTitle = nextTaskTitle
        self.nextTaskPrompt = nextTaskPrompt
        self.questionsText = questionsText
        self.localPreparationNote = localPreparationNote
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.createdAt = createdAt
        self.project = project
    }
}

extension AnalysisReport {
    var kind: AnalysisKind {
        AnalysisKind(rawValue: kindRawValue) ?? .story
    }

    var strengths: [String] { strengthsText.nonemptyLines }
    var gaps: [String] { gapsText.nonemptyLines }
    var recommendations: [String] { recommendationText.nonemptyLines }
    var commercialPatterns: [String] { commercialPatternsText.nonemptyLines }
    var theoryBasis: [String] { theoryBasisText.nonemptyLines }
    var questions: [String] { questionsText.nonemptyLines }
}

private extension String {
    nonisolated var nonemptyLines: [String] {
        components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
