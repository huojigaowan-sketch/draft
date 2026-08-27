import Foundation

enum ScreenplayBulkEditScope: String, CaseIterable, Identifiable {
    case fullScript = "全剧文本"
    case sceneHeadings = "场景标题"
    case characterNames = "人物名"

    var id: String { rawValue }
}

struct ScreenplaySearchResult: Identifiable, Hashable {
    let id: Int
    let sceneIndex: Int
    let heading: String
    let excerpt: String
    let occurrenceCount: Int
}

enum ScreenplayBulkEditor {
    static func search(
        _ query: String,
        scope: ScreenplayBulkEditScope,
        caseSensitive: Bool,
        in text: String
    ) -> [ScreenplaySearchResult] {
        guard !query.isEmpty else { return [] }
        return FountainParser.scenes(in: text).compactMap { scene in
            let searchable = scopedText(for: scene, scope: scope)
            let count = occurrenceCount(
                of: query,
                in: searchable,
                caseSensitive: caseSensitive
            )
            guard count > 0 else { return nil }
            return ScreenplaySearchResult(
                id: scene.index,
                sceneIndex: scene.index,
                heading: scene.heading,
                excerpt: excerpt(
                    around: query,
                    in: searchable,
                    caseSensitive: caseSensitive
                ),
                occurrenceCount: count
            )
        }
    }

    static func replacing(
        _ query: String,
        with replacement: String,
        scope: ScreenplayBulkEditScope,
        caseSensitive: Bool,
        in text: String
    ) -> String {
        guard !query.isEmpty else { return text }
        let lines = text.components(separatedBy: "\n")
        let replaced: [String]

        switch scope {
        case .fullScript:
            return FountainParser.localizingSceneHeadings(
                in: replace(
                    query,
                    with: replacement,
                    in: text,
                    caseSensitive: caseSensitive
                )
            )
        case .sceneHeadings:
            replaced = lines.map { line in
                guard FountainParser.isSceneHeading(line) else { return line }
                return replace(
                    query,
                    with: replacement,
                    in: line,
                    caseSensitive: caseSensitive
                )
            }
        case .characterNames:
            replaced = lines.map { line in
                let trimmed = line.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard FountainParser.isCharacterCue(trimmed) else { return line }
                return replace(
                    query,
                    with: replacement,
                    in: line,
                    caseSensitive: caseSensitive
                )
            }
        }
        return FountainParser.localizingSceneHeadings(
            in: replaced.joined(separator: "\n")
        )
    }

    static func occurrenceCount(
        of query: String,
        in text: String,
        caseSensitive: Bool
    ) -> Int {
        guard !query.isEmpty else { return 0 }
        let options: String.CompareOptions = caseSensitive
            ? []
            : [.caseInsensitive, .diacriticInsensitive]
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(
            of: query,
            options: options,
            range: searchRange
        ) {
            count += 1
            searchRange = range.upperBound..<text.endIndex
        }
        return count
    }

    private static func scopedText(
        for scene: FountainSceneSnapshot,
        scope: ScreenplayBulkEditScope
    ) -> String {
        switch scope {
        case .fullScript:
            scene.text
        case .sceneHeadings:
            scene.heading
        case .characterNames:
            scene.characterNames.joined(separator: "\n")
        }
    }

    private static func replace(
        _ query: String,
        with replacement: String,
        in text: String,
        caseSensitive: Bool
    ) -> String {
        guard !caseSensitive else {
            return text.replacingOccurrences(of: query, with: replacement)
        }
        let pattern = NSRegularExpression.escapedPattern(for: query)
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let template = NSRegularExpression.escapedTemplate(for: replacement)
        return regex.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: template
        )
    }

    private static func excerpt(
        around query: String,
        in text: String,
        caseSensitive: Bool
    ) -> String {
        let options: String.CompareOptions = caseSensitive
            ? []
            : [.caseInsensitive, .diacriticInsensitive]
        guard let range = text.range(of: query, options: options) else {
            return String(text.prefix(90))
        }
        let lower = text.index(
            range.lowerBound,
            offsetBy: -40,
            limitedBy: text.startIndex
        ) ?? text.startIndex
        let upper = text.index(
            range.upperBound,
            offsetBy: 60,
            limitedBy: text.endIndex
        ) ?? text.endIndex
        return text[lower..<upper]
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
