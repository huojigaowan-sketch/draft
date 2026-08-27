import Foundation

struct KnowledgeMatch {
    let title: String
    let pageNumber: Int
    let content: String
    let score: Double

    var promptBlock: String {
        "[\(title) p.\(pageNumber)]\n\(content)"
    }
}

enum KnowledgeRetriever {
    @MainActor
    static func search(
        query: String,
        chunks: [KnowledgeChunk],
        limit: Int
    ) -> [KnowledgeMatch] {
        let queryTerms = terms(from: query)
        guard !queryTerms.isEmpty else { return [] }

        return chunks.compactMap { chunk -> KnowledgeMatch? in
            let body = chunk.content.lowercased()
            let title = chunk.document?.title ?? "私人资料"
            let titleText = title.lowercased()
            var score = 0.0

            for term in queryTerms {
                if body.contains(term) {
                    score += term.count >= 4 ? 2.2 : 1.0
                }
                if titleText.contains(term) {
                    score += 1.8
                }
            }
            guard score > 0 else { return nil }
            return KnowledgeMatch(
                title: title,
                pageNumber: chunk.pageNumber,
                content: String(chunk.content.prefix(900)),
                score: score / Double(max(queryTerms.count, 1))
            )
        }
        .sorted { $0.score > $1.score }
        .prefix(limit)
        .map { $0 }
    }

    private static func terms(from text: String) -> Set<String> {
        let lowered = text.lowercased()
        var result = Set(
            lowered.split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count >= 2 && $0.count <= 24 }
        )

        let cjk = lowered.unicodeScalars
            .filter(\.isCJK)
            .map(String.init)
        if cjk.count >= 2 {
            for index in 0..<(cjk.count - 1) {
                result.insert(cjk[index] + cjk[index + 1])
            }
        }
        return Set(result.prefix(100))
    }
}

private extension Unicode.Scalar {
    var isCJK: Bool {
        switch value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
            true
        default:
            false
        }
    }
}

