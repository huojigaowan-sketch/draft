import Foundation

struct StoryCase: Codable, Identifiable {
    let title: String
    let year: Int
    let genres: [String]
    let archetype: String
    let protagonist: String
    let externalGoal: String
    let internalNeed: String
    let flaw: String
    let antagonistFunction: String
    let themeConflict: String
    let arc: String
    let patternTags: [String]
    let culture: String?
    let form: String?

    var id: String { title }

    var cultureLabel: String { culture ?? "全球影视" }
    var formLabel: String { form ?? "影视" }

    var promptBlock: String {
        """
        \(title)（\(year)）
        来源：\(cultureLabel) · \(formLabel)
        类型：\(genres.joined(separator: "/"))
        模式：\(archetype)
        主角功能：\(protagonist)
        目标/需求：\(externalGoal) / \(internalNeed)
        缺陷：\(flaw)
        对抗功能：\(antagonistFunction)
        主题冲突：\(themeConflict)
        弧线：\(arc)
        """
    }
}

@MainActor
final class StoryDNAService {
    static let shared = StoryDNAService()
    let cases: [StoryCase]

    private init() {
        guard let url = Bundle.main.url(forResource: "StoryDNA", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([StoryCase].self, from: data) else {
            cases = []
            return
        }
        cases = decoded
    }

    func matches(query: String, genre: String, limit: Int) -> [StoryCase] {
        let normalized = query.lowercased()
        let ranked = cases.map { item -> (StoryCase, Int) in
            var score = item.genres.contains(genre) ? 5 : 0
            for tag in item.patternTags where normalized.contains(tag.lowercased()) {
                score += 3
            }
            if normalized.contains(item.archetype.lowercased()) {
                score += 2
            }
            if normalized.contains(item.cultureLabel.lowercased())
                || normalized.contains(item.formLabel.lowercased()) {
                score += 2
            }
            return (item, score)
        }
        .sorted { lhs, rhs in
            if lhs.1 == rhs.1 { return lhs.0.year > rhs.0.year }
            return lhs.1 > rhs.1
        }

        let positive = ranked.filter { $0.1 > 0 }
        return (positive.isEmpty ? ranked : positive)
            .prefix(limit)
            .map(\.0)
    }
}
