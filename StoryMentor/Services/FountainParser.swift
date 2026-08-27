import Foundation

enum FountainElementType: String, CaseIterable, Identifiable {
    case sceneHeading = "场景标题"
    case action = "动作"
    case character = "人物"
    case parenthetical = "括号提示"
    case dialogue = "对白"
    case transition = "转场"
    case note = "注释"

    var id: String { rawValue }
}

struct FountainParagraphSnapshot: Identifiable {
    var id: Int { index }

    /// Zero-based logical paragraph index.
    let index: Int

    /// UTF-16 range in the source string. For non-terminal paragraphs this
    /// follows `NSString.lineRange(for:)` and therefore includes the line
    /// terminator. A trailing empty paragraph has a zero-length range at EOF.
    let utf16Range: NSRange

    /// Source text covered by `utf16Range`, including any line terminator.
    let rawText: String

    /// `rawText` without surrounding whitespace or line terminators.
    let trimmedText: String

    /// Base screenplay element inferred from the plain Fountain context.
    let inferredType: FountainElementType
}

struct FountainSceneSnapshot: Identifiable, Hashable {
    var id: Int { index }
    let index: Int
    let heading: String
    let summary: String
    let text: String
    let startLine: Int
    let endLine: Int
    let estimatedPages: Int
    let estimatedDurationSeconds: Double
    let characterNames: [String]

    var isSkeleton: Bool {
        let contentLines = text
            .components(separatedBy: .newlines)
            .dropFirst()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return contentLines.isEmpty || contentLines.allSatisfy {
            $0.hasPrefix("[[")
                || $0 == "==="
                || $0 == "动作从一个具体、可见的变化开始。"
                || $0 == "写下一个具体、可见的动作。"
        }
    }
}

enum FountainSceneLocationKind: String, Codable, CaseIterable, Identifiable {
    case interior = "内"
    case exterior = "外"
    case mixed = "内/外"
    case unknown = "未标注"

    var id: String { rawValue }
}

struct FountainSceneHeadingComponents: Hashable {
    let locationKind: FountainSceneLocationKind
    let locationName: String
    let timeOfDay: String
}

struct SceneCardReference: Identifiable, Hashable {
    var id: Int { number }
    let number: Int
    var title: String
    var purpose: String
    var conflict: String
    var turningPoint: String
    var endingHook: String

    var promptBlock: String {
        """
        场景 \(number)：\(title)
        目的：\(purpose)
        冲突：\(conflict)
        转折：\(turningPoint)
        离场钩子：\(endingHook)
        """
    }
}

enum FountainParser {
    private enum SceneLocation {
        case interior
        case exterior
        case mixed

        var localizedMarker: String {
            switch self {
            case .interior: "内."
            case .exterior: "外."
            case .mixed: "内/外."
            }
        }
    }

    private struct SceneHeadingMatch {
        let location: SceneLocation
        let remainder: String
    }

    private static let sceneHeadingPrefixes: [(String, SceneLocation)] = [
        // Longer alternatives must precede their shorter prefixes.
        ("INT./EXT.", .mixed),
        ("EXT./INT.", .mixed),
        ("INT/EXT.", .mixed),
        ("EXT/INT.", .mixed),
        ("内景/外景", .mixed),
        ("外景/内景", .mixed),
        ("内/外景", .mixed),
        ("外/内景", .mixed),
        ("内/外.", .mixed),
        ("外/内.", .mixed),
        ("内/外。", .mixed),
        ("外/内。", .mixed),
        ("内/外", .mixed),
        ("外/内", .mixed),
        ("I/E.", .mixed),
        ("INT.", .interior),
        ("EXT.", .exterior),
        ("EST.", .exterior),
        ("内景", .interior),
        ("外景", .exterior),
        ("内.", .interior),
        ("外.", .exterior),
        ("内。", .interior),
        ("外。", .exterior),
        ("INT", .interior),
        ("EXT", .exterior),
        ("内", .interior),
        ("外", .exterior),
    ]

    static func paragraphs(in text: String) -> [FountainParagraphSnapshot] {
        let value = text as NSString
        var snapshots: [FountainParagraphSnapshot] = []
        var location = 0
        var previousWasCharacter = false

        while location < value.length {
            let range = value.lineRange(
                for: NSRange(location: location, length: 0)
            )
            let rawText = value.substring(with: range)
            let trimmedText = rawText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let inferredType = elementType(
                for: trimmedText,
                previousWasCharacter: previousWasCharacter
            )

            snapshots.append(
                FountainParagraphSnapshot(
                    index: snapshots.count,
                    utf16Range: range,
                    rawText: rawText,
                    trimmedText: trimmedText,
                    inferredType: inferredType
                )
            )

            previousWasCharacter = inferredType == .character
                || inferredType == .parenthetical
            if trimmedText.isEmpty {
                previousWasCharacter = false
            }
            location = NSMaxRange(range)
        }

        if value.length == 0 || endsWithLineTerminator(value) {
            let inferredType = elementType(
                for: "",
                previousWasCharacter: previousWasCharacter
            )
            snapshots.append(
                FountainParagraphSnapshot(
                    index: snapshots.count,
                    utf16Range: NSRange(location: value.length, length: 0),
                    rawText: "",
                    trimmedText: "",
                    inferredType: inferredType
                )
            )
        }

        return snapshots
    }

    static func paragraph(
        atUTF16Location location: Int,
        in text: String
    ) -> FountainParagraphSnapshot? {
        let value = text as NSString
        guard location >= 0, location <= value.length else { return nil }

        let snapshots = paragraphs(in: text)
        if location == value.length {
            return snapshots.last
        }

        return snapshots.first {
            location >= $0.utf16Range.location
                && location < NSMaxRange($0.utf16Range)
        }
    }

    static func scenes(in text: String) -> [FountainSceneSnapshot] {
        let lines = text.components(separatedBy: "\n")
        var starts = lines.indices.filter {
            isSceneHeading(lines[$0])
        }
        if starts.isEmpty {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return []
            }
            starts = [0]
        }

        return starts.enumerated().map { offset, start in
            let end = offset + 1 < starts.count ? starts[offset + 1] : lines.count
            let sceneLines = Array(lines[start..<end])
            var visibleSceneLines = sceneLines
            while let last = visibleSceneLines.last,
                  last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || isForcedPageBreak(last) {
                visibleSceneLines.removeLast()
            }
            let sceneText = visibleSceneLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let heading = localizedSceneHeading(lines[start])
                ?? "未建立场景标题"
            let summary = visibleSceneLines
                .dropFirst()
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first {
                    !$0.isEmpty
                        && !$0.hasPrefix("[[")
                        && elementType(for: $0, previousWasCharacter: false) == .action
                } ?? "等待动作发生"
            let duration = ChineseScreenplayTiming.estimatedSeconds(in: sceneText)
            let linePages = Int(ceil(Double(max(visibleSceneLines.count, 1)) / 54.0))
            let durationPages = Int(ceil(max(duration, 1) / 60.0))
            let characterNames = characterCues(in: visibleSceneLines)
            return FountainSceneSnapshot(
                index: offset,
                heading: heading,
                summary: String(summary.prefix(90)),
                text: sceneText,
                startLine: start,
                endLine: end,
                estimatedPages: max(1, max(linePages, durationPages)),
                estimatedDurationSeconds: duration,
                characterNames: characterNames
            )
        }
    }

    static func replacingScene(
        at index: Int,
        in fullText: String,
        with replacement: String
    ) -> String {
        let snapshots = scenes(in: fullText)
        guard snapshots.indices.contains(index) else {
            let separator = fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? ""
                : "\n\n"
            return fullText + separator + replacement
        }
        var lines = fullText.components(separatedBy: "\n")
        let scene = snapshots[index]
        var replacementLines = localizingSceneHeadings(in: replacement)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
        let firstContentLine = replacementLines.firstIndex {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if let firstContentLine {
            if !isSceneHeading(replacementLines[firstContentLine]) {
                let preservedHeading = localizedSceneHeading(scene.heading)
                    ?? "内. 未定地点 - 日"
                replacementLines.insert(preservedHeading, at: firstContentLine)
            }
        } else {
            replacementLines = [
                localizedSceneHeading(scene.heading) ?? "内. 未定地点 - 日"
            ]
        }
        lines.replaceSubrange(scene.startLine..<scene.endLine, with: replacementLines)
        let replaced = lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return standardizingSceneFlow(in: replaced)
    }

    static func replacingSceneHeading(
        at index: Int,
        in fullText: String,
        with heading: String
    ) -> String {
        let snapshots = scenes(in: fullText)
        guard snapshots.indices.contains(index) else { return fullText }
        var lines = fullText.components(separatedBy: "\n")
        let scene = snapshots[index]
        let localized = localizedSceneHeading(heading)
            ?? "内. \(heading.trimmingCharacters(in: .whitespacesAndNewlines))"
        guard lines.indices.contains(scene.startLine) else { return fullText }
        lines[scene.startLine] = localized
        return standardizingSceneFlow(in: lines.joined(separator: "\n"))
    }

    /// Normalizes a screenplay into one continuous industry-standard page
    /// flow. Earlier builds inserted a Fountain forced page break before every
    /// scene; professional screenplays allow a scene heading to continue on
    /// the current page, so those generated separators are removed here.
    static func standardizingSceneFlow(in text: String) -> String {
        let localizedText = localizingSceneHeadings(in: text)
        let lines = localizedText.components(separatedBy: "\n")
        let starts = lines.indices.filter { isSceneHeading(lines[$0]) }
        guard starts.count > 1, let firstStart = starts.first else {
            return localizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let prefix = lines[..<firstStart]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let sceneBlocks = starts.enumerated().map { offset, start -> String in
            let end = offset + 1 < starts.count ? starts[offset + 1] : lines.count
            var block = Array(lines[start..<end])
            while let last = block.last,
                  last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || isForcedPageBreak(last) {
                block.removeLast()
            }
            return block.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let body = sceneBlocks.joined(separator: "\n\n")
        return prefix.isEmpty ? body : "\(prefix)\n\n\(body)"
    }

    /// Compatibility entry point for saved call sites from earlier versions.
    /// The result now follows continuous Final Draft page flow.
    static func enforcingScenePageBreaks(in text: String) -> String {
        standardizingSceneFlow(in: text)
    }

    static func characterRange(
        forSceneAt index: Int,
        in text: String
    ) -> NSRange? {
        let snapshots = scenes(in: text)
        guard snapshots.indices.contains(index) else { return nil }
        let lines = text.components(separatedBy: "\n")
        let scene = snapshots[index]
        let prefix = lines.prefix(scene.startLine).joined(separator: "\n")
        let location = (prefix as NSString).length + (scene.startLine > 0 ? 1 : 0)
        return NSRange(location: location, length: (scene.text as NSString).length)
    }

    static func isSceneHeading(_ line: String) -> Bool {
        sceneHeadingMatch(in: line) != nil
    }

    /// Returns the app's canonical Chinese scene-heading form.
    ///
    /// Both legacy Fountain prefixes (`INT.`, `EXT.`) and common Chinese
    /// variants (`内景`, `外景`, `内.`, `外.`) remain readable, while everything
    /// displayed or newly saved by the app uses `内.`, `外.` or `内/外.`.
    static func localizedSceneHeading(_ line: String) -> String? {
        guard let match = sceneHeadingMatch(in: line) else { return nil }
        let remainder = normalizedSceneHeadingRemainder(match.remainder)
        return remainder.isEmpty
            ? match.location.localizedMarker
            : "\(match.location.localizedMarker) \(remainder)"
    }

    static func sceneHeadingComponents(
        _ line: String
    ) -> FountainSceneHeadingComponents? {
        guard let match = sceneHeadingMatch(in: line) else { return nil }
        let remainder = normalizedSceneHeadingRemainder(match.remainder)

        let separators = [" - ", " — ", " – ", "-", "—", "–"]
        var locationName = remainder
        var timeOfDay = ""
        for separator in separators {
            guard let range = remainder.range(
                of: separator,
                options: .backwards
            ) else { continue }
            let trailing = remainder[range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trailing.isEmpty, trailing.count <= 12 else { continue }
            locationName = remainder[..<range.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            timeOfDay = trailing
            break
        }

        let kind: FountainSceneLocationKind = switch match.location {
        case .interior: .interior
        case .exterior: .exterior
        case .mixed: .mixed
        }
        return FountainSceneHeadingComponents(
            locationKind: kind,
            locationName: locationName.isEmpty ? "未定地点" : locationName,
            timeOfDay: timeOfDay.isEmpty ? "未标注" : timeOfDay
        )
    }

    static func localizingSceneHeadings(in text: String) -> String {
        text.components(separatedBy: "\n")
            .map { localizedSceneHeading($0) ?? $0 }
            .joined(separator: "\n")
    }

    private static func sceneHeadingMatch(
        in line: String
    ) -> SceneHeadingMatch? {
        let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let uppercaseValue = value.uppercased()

        for (prefix, location) in sceneHeadingPrefixes {
            guard uppercaseValue.hasPrefix(prefix) else { continue }
            let end = value.index(value.startIndex, offsetBy: prefix.count)
            let remainder = String(value[end...])
            if prefix.last?.isLetter == true,
               !hasSceneHeadingBoundary(remainder) {
                continue
            }
            return SceneHeadingMatch(
                location: location,
                remainder: remainder
            )
        }
        return nil
    }

    private static func hasSceneHeadingBoundary(_ remainder: String) -> Bool {
        guard let first = remainder.first else { return true }
        return first.isWhitespace
            || first.isNumber
            || ".。:：-—–/·•".contains(first)
    }

    private static func normalizedSceneHeadingRemainder(
        _ rawValue: String
    ) -> String {
        var remainder = rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        while let first = remainder.first, ".。:：·•".contains(first) {
            remainder.removeFirst()
            remainder = remainder.trimmingCharacters(in: .whitespaces)
        }

        let hasStandardTimeSeparator = [" - ", " — ", " – ", "-", "—", "–"]
            .contains { remainder.contains($0) }
        if !hasStandardTimeSeparator,
           let separatorIndex = remainder.lastIndex(where: {
               $0 == "·" || $0 == "•"
           }) {
            let time = remainder[remainder.index(after: separatorIndex)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !time.isEmpty, time.count <= 12 {
                let location = remainder[..<separatorIndex]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                remainder = "\(location) - \(time)"
            }
        }
        return remainder
    }

    static func isForcedPageBreak(_ line: String) -> Bool {
        let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.count >= 3 && value.allSatisfy { $0 == "=" }
    }

    private static func endsWithLineTerminator(_ value: NSString) -> Bool {
        guard value.length > 0 else { return false }
        let lastRange = NSRange(location: value.length - 1, length: 1)
        let lastCharacter = value.substring(with: lastRange)
        return lastCharacter.rangeOfCharacter(from: .newlines) != nil
    }

    static func elementType(
        for line: String,
        previousWasCharacter: Bool
    ) -> FountainElementType {
        let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if isSceneHeading(value) { return .sceneHeading }
        if value.hasPrefix("[[") { return .note }
        if value.hasPrefix("(") || value.hasPrefix("（") { return .parenthetical }
        if value.uppercased().hasSuffix(" TO:")
            || value.hasSuffix("转场：")
            || value == "CUT TO:" {
            return .transition
        }
        if previousWasCharacter { return .dialogue }
        if isCharacterCue(value) { return .character }
        return .action
    }

    static func isCharacterCue(_ line: String) -> Bool {
        let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 24 else { return false }
        if value.hasPrefix("@") { return true }
        if value.contains("。") || value.contains("！") || value.contains("？")
            || value.contains(",") || value.contains("，") || value.contains(":")
            || value.contains("：") {
            return false
        }
        let letters = value.unicodeScalars.filter {
            CharacterSet.letters.contains($0)
        }
        guard !letters.isEmpty else { return false }
        let hasLatin = value.unicodeScalars.contains { $0.value < 128 && CharacterSet.letters.contains($0) }
        return hasLatin ? value == value.uppercased() : value.count <= 8
    }

    private static func characterCues(in lines: [String]) -> [String] {
        var names: [String] = []
        for line in lines {
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if isCharacterCue(value) {
                let clean = value.trimmingCharacters(in: CharacterSet(charactersIn: "@^ "))
                if !names.contains(clean) { names.append(clean) }
            }
        }
        return names
    }
}

enum SceneCardImporter {
    static func cards(from text: String) -> [SceneCardReference] {
        let lines = text.components(separatedBy: .newlines)
        let headerPatterns = [
            #"^(?:【)?场景\s*(\d+)(?:】)?[\s：:｜|\-]*(.*)$"#,
            #"^(\d+)[.、]\s*(.+)$"#
        ]
        let headerRegexes = headerPatterns.compactMap {
            try? NSRegularExpression(pattern: $0)
        }
        var cards: [SceneCardReference] = []
        var current: SceneCardReference?

        func flush() {
            if let current { cards.append(current) }
        }

        func sceneHeader(in line: String) -> (number: Int, title: String)? {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            for regex in headerRegexes {
                guard let match = regex.firstMatch(in: line, range: range),
                      let numberRange = Range(match.range(at: 1), in: line) else {
                    continue
                }
                let number = Int(line[numberRange]) ?? cards.count + 1
                let title = Range(match.range(at: 2), in: line)
                    .map { String(line[$0]) }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    ?? ""
                return (number, title)
            }
            return nil
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if let header = sceneHeader(in: line) {
                flush()
                current = SceneCardReference(
                    number: header.number,
                    title: header.title,
                    purpose: "",
                    conflict: "",
                    turningPoint: "",
                    endingHook: ""
                )
                continue
            }

            guard current != nil else { continue }
            if let value = value(after: ["目的：", "目的:", "功能：", "功能:"], in: line) {
                current?.purpose = value
            } else if let value = value(after: ["冲突：", "冲突:"], in: line) {
                current?.conflict = value
            } else if let value = value(after: ["转折：", "转折:"], in: line) {
                current?.turningPoint = value
            } else if let value = value(
                after: ["钩子：", "钩子:", "结尾钩子：", "endingHook："],
                in: line
            ) {
                current?.endingHook = value
            } else if current?.title.isEmpty == true {
                current?.title = line
            }
        }
        flush()

        if cards.isEmpty,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let blocks = text.components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            cards = blocks.enumerated().map { index, block in
                let first = block.components(separatedBy: .newlines).first ?? "未定地点"
                return SceneCardReference(
                    number: index + 1,
                    title: String(first.prefix(70)),
                    purpose: block,
                    conflict: "",
                    turningPoint: "",
                    endingHook: ""
                )
            }
        }
        return cards
    }

    static func fountainSkeleton(
        projectTitle: String,
        sceneCardsText: String
    ) -> String {
        var cards = cards(from: sceneCardsText)
        if cards.isEmpty {
            cards = [
                SceneCardReference(
                    number: 1,
                    title: "未定地点",
                    purpose: "确定本场必须发生的变化",
                    conflict: "谁阻止谁得到什么",
                    turningPoint: "局面必须发生变化",
                    endingHook: "把压力送入下一场"
                )
            ]
        }
        let titlePage = """
        Title: \(projectTitle)
        Credit: Screenplay
        Draft date: \(Date.now.formatted(date: .abbreviated, time: .omitted))
        """
        let body = cards.map { card in
            let heading = FountainParser.localizedSceneHeading(card.title)
                ?? "内. \(card.title.isEmpty ? "未定地点" : card.title) - 日"
            return """
            \(heading)

            [[场景目标：\(card.purpose)]]
            [[冲突：\(card.conflict)]]
            [[转折：\(card.turningPoint)]]
            [[离场钩子：\(card.endingHook)]]

            动作从一个具体、可见的变化开始。
            """
        }.joined(separator: "\n\n")
        return "\(titlePage)\n\n\(body)"
    }

    private static func value(after prefixes: [String], in line: String) -> String? {
        guard let prefix = prefixes.first(where: { line.hasPrefix($0) }) else {
            return nil
        }
        return String(line.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ChineseScreenplayTiming {
    /// 中文电影剧本的基础校准值。实际时长仍会随表演、停顿和动作复杂度变化。
    static let effectiveCharactersPerMinute = 350.0
    static let dialogueCharactersPerSecond = 4.0
    static let actionCharactersPerSecond = effectiveCharactersPerMinute / 60.0

    static func estimatedSeconds(in text: String) -> Double {
        var total = 0.0
        var previousWasCharacter = false

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                previousWasCharacter = false
                continue
            }
            guard !FountainParser.isForcedPageBreak(line) else { continue }

            let type = FountainParser.elementType(
                for: line,
                previousWasCharacter: previousWasCharacter
            )
            let count = Double(effectiveCharacterCount(in: line))

            switch type {
            case .sceneHeading:
                total += 2
            case .action:
                let beats = Double(
                    line.filter { "。！？!?；;".contains($0) }.count
                )
                total += max(count / actionCharactersPerSecond, max(beats, 1) * 1.8)
            case .character:
                total += 0.2
            case .parenthetical:
                total += max(0.4, count / 5.0)
            case .dialogue:
                total += max(0.8, count / dialogueCharactersPerSecond)
            case .transition:
                total += 1
            case .note:
                break
            }

            previousWasCharacter = type == .character || type == .parenthetical
        }
        return max(total, 1)
    }

    static func formattedDuration(_ seconds: Double) -> String {
        let rounded = max(Int(seconds.rounded()), 1)
        let minutes = rounded / 60
        let remainingSeconds = rounded % 60
        if minutes == 0 { return "约 \(remainingSeconds) 秒" }
        if remainingSeconds == 0 { return "约 \(minutes) 分钟" }
        return "约 \(minutes) 分 \(remainingSeconds) 秒"
    }

    private static func effectiveCharacterCount(in text: String) -> Int {
        text.reduce(into: 0) { count, character in
            if character.unicodeScalars.contains(where: {
                CharacterSet.letters.contains($0)
                    || CharacterSet.decimalDigits.contains($0)
            }) {
                count += 1
            }
        }
    }
}
