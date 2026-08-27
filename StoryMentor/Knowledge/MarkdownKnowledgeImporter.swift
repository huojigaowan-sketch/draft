import CryptoKit
import Foundation

actor MarkdownKnowledgeImporter {
    func parse(urls: [URL]) throws -> [TheoryDocumentInput] {
        var documents: [TheoryDocumentInput] = []

        for rootURL in urls {
            let accessed = rootURL.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    rootURL.stopAccessingSecurityScopedResource()
                }
            }

            for fileURL in markdownFiles(at: rootURL) {
                let document = try parseFile(at: fileURL)
                documents.append(document)
            }
        }

        return documents.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func markdownFiles(at url: URL) -> [URL] {
        let fileManager = FileManager.default
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return []
        }

        if !isDirectory.boolValue {
            return url.pathExtension.lowercased() == "md" ? [url] : []
        }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isHiddenKey]
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        return enumerator.compactMap { $0 as? URL }
            .filter { candidate in
                guard candidate.pathExtension.lowercased() == "md" else { return false }
                let values = try? candidate.resourceValues(forKeys: keys)
                return values?.isRegularFile == true && values?.isHidden != true
            }
            .sorted { $0.path < $1.path }
    }

    private func parseFile(at url: URL) throws -> TheoryDocumentInput {
        let data = try Data(contentsOf: url)
        guard let rawText = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .unicode) else {
            throw MarkdownImportError.unsupportedEncoding(url.lastPathComponent)
        }

        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        let title = metadataTitle(in: rawText) ?? cleanInline(fallbackTitle)
        let sourceFingerprint = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        let sections = parseSections(rawText, defaultTitle: title)
        let parsedChunks = sections.flatMap { section in
            makeChunks(from: section, title: title)
        }
        let chunks = parsedChunks.enumerated().map { index, chunk in
            TheoryChunkInput(
                sequence: index,
                headingPath: chunk.headingPath,
                topics: chunk.topics,
                content: chunk.content
            )
        }
        let topicCounts = Dictionary(grouping: chunks.flatMap(\.topics), by: \.self)
            .sorted { $0.value.count > $1.value.count }
            .prefix(5)
            .map { $0.key.displayName }

        guard !chunks.isEmpty else {
            throw MarkdownImportError.noUsableText(url.lastPathComponent)
        }

        return TheoryDocumentInput(
            title: title,
            sourceFilename: url.lastPathComponent,
            sourceFingerprint: sourceFingerprint,
            sourceType: "markdown",
            characterCount: rawText.count,
            sectionCount: sections.count,
            topicSummary: topicCounts.joined(separator: " · "),
            chunks: chunks
        )
    }

    private func metadataTitle(in text: String) -> String? {
        for line in text.split(separator: "\n").prefix(40) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix("**title:**") {
                return cleanInline(String(trimmed.dropFirst("**Title:**".count)))
            }
            if trimmed.lowercased().hasPrefix("title:") {
                return cleanInline(String(trimmed.dropFirst("title:".count)))
            }
        }
        return nil
    }

    private func parseSections(_ rawText: String, defaultTitle: String) -> [MarkdownSection] {
        let normalized = rawText.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var sections: [MarkdownSection] = []
        var headingStack: [(level: Int, title: String)] = [(0, defaultTitle)]
        var body: [String] = []

        func flush() {
            let text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let path = headingStack.map(\.title).filter { !$0.isEmpty }
            guard text.count >= 180, !isNavigationPath(path) else {
                body.removeAll(keepingCapacity: true)
                return
            }
            sections.append(MarkdownSection(headingPath: path.joined(separator: " > "), content: text))
            body.removeAll(keepingCapacity: true)
        }

        for index in lines.indices {
            let original = lines[index]
            let previousBlank = index == lines.startIndex || lines[index - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let nextBlank = index == lines.index(before: lines.endIndex) || lines[index + 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            if let heading = markdownHeading(in: original) {
                flush()
                headingStack.removeAll { $0.level >= heading.level }
                headingStack.append((heading.level, heading.title))
                continue
            }

            if previousBlank, nextBlank, let heading = standaloneHeading(in: original) {
                flush()
                headingStack.removeAll { $0.level >= 2 }
                headingStack.append((2, heading))
                continue
            }

            let cleaned = cleanBodyLine(original)
            if cleaned.isEmpty {
                if !body.isEmpty, body.last != "" {
                    body.append("")
                }
            } else {
                body.append(cleaned)
            }
        }
        flush()

        if sections.isEmpty {
            let fallback = lines.map(cleanBodyLine).filter { !$0.isEmpty }.joined(separator: "\n")
            if fallback.count >= 180 {
                sections = [MarkdownSection(headingPath: defaultTitle, content: fallback)]
            }
        }
        return sections
    }

    private func markdownHeading(in line: String) -> (level: Int, title: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var level = 0
        for character in trimmed {
            guard character == "#" else { break }
            level += 1
        }
        guard (1...6).contains(level),
              trimmed.dropFirst(level).first?.isWhitespace == true else {
            return nil
        }
        let title = cleanInline(String(trimmed.dropFirst(level)))
        guard title.count >= 2, !title.hasPrefix("![") else { return nil }
        return (level, title)
    }

    private func standaloneHeading(in line: String) -> String? {
        let title = cleanInline(line)
        guard title.count >= 3, title.count <= 140,
              !title.contains(".") || title.hasPrefix("CHAPTER") || title.hasPrefix("Chapter") else {
            return nil
        }
        let uppercase = title.filter { $0.isLetter && $0.isUppercase }.count
        let letters = title.filter(\.isLetter).count
        let uppercaseRatio = letters == 0 ? 0 : Double(uppercase) / Double(letters)
        let upper = title.uppercased()
        let known = ["PART ", "CHAPTER ", "ACT ", "SCENE ", "INTRODUCTION", "CONCLUSION", "EPILOGUE", "PREFACE", "PROLOGUE"]
        guard known.contains(where: { upper.hasPrefix($0) }) || uppercaseRatio > 0.78 else {
            return nil
        }
        return title
    }

    private func makeChunks(from section: MarkdownSection, title: String) -> [TheoryChunkInput] {
        let paragraphs = section.content
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 20 }
            .flatMap { splitLongParagraph($0, maximumLength: 760) }
        guard !paragraphs.isEmpty else { return [] }

        var result: [TheoryChunkInput] = []
        var buffer = ""
        var sequence = 0

        func emit(_ text: String) {
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized.count >= 180 else { return }
            let topics = TheoryTopicClassifier.classify(title: title, headingPath: section.headingPath, content: normalized)
            result.append(
                TheoryChunkInput(
                    sequence: sequence,
                    headingPath: section.headingPath,
                    topics: topics,
                    content: normalized
                )
            )
            sequence += 1
        }

        for paragraph in paragraphs {
            if buffer.count + paragraph.count + 2 > 950, !buffer.isEmpty {
                emit(buffer)
                let overlap = String(buffer.suffix(160))
                buffer = overlap + "\n\n" + paragraph
            } else {
                buffer += buffer.isEmpty ? paragraph : "\n\n" + paragraph
            }
        }
        emit(buffer)
        return result
    }

    private func splitLongParagraph(_ paragraph: String, maximumLength: Int) -> [String] {
        guard paragraph.count > maximumLength else { return [paragraph] }

        var pieces: [String] = []
        var remaining = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = ["\n", ". ", "。", "！", "？", "; ", "；", ", ", "，", " "]

        while remaining.count > maximumLength {
            let limit = remaining.index(remaining.startIndex, offsetBy: maximumLength)
            let prefix = String(remaining[..<limit])
            var cut = limit

            for separator in separators {
                if let range = prefix.range(of: separator, options: .backwards), range.upperBound > prefix.startIndex {
                    cut = range.upperBound
                    break
                }
            }

            let piece = String(remaining[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty {
                pieces.append(piece)
            }
            remaining = String(remaining[cut...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if !remaining.isEmpty {
            pieces.append(remaining)
        }
        return pieces
    }

    private func isNavigationPath(_ path: [String]) -> Bool {
        let joined = path.joined(separator: " ").lowercased()
        return ["contents", "table of contents", "copyright", "acknowledgments", "bibliography", "index", "notes"].contains {
            joined.contains($0)
        }
    }

    private func cleanBodyLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("!["),
              !trimmed.lowercased().hasPrefix("copyright"),
              !trimmed.lowercased().hasPrefix("isbn"),
              !trimmed.hasPrefix("**Title:"),
              !trimmed.hasPrefix("**Authors:"),
              !trimmed.hasPrefix("**Publisher:") else {
            return ""
        }
        return cleanInline(trimmed)
    }

    private func cleanInline(_ value: String) -> String {
        var result = value
        let pattern = #"\[([^\]]+)\]\([^)]+\)"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1")
        }
        result = result
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "<br>", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }
}

private struct MarkdownSection {
    let headingPath: String
    let content: String
}

enum MarkdownImportError: LocalizedError {
    case unsupportedEncoding(String)
    case noUsableText(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedEncoding(let file):
            "无法读取 \(file) 的文字编码。"
        case .noUsableText(let file):
            "\(file) 中没有可用于理论检索的正文。"
        }
    }
}
