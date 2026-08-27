import Foundation
import PDFKit

struct ParsedKnowledgeDocument: Sendable {
    struct Chunk: Sendable {
        let pageNumber: Int
        let sequence: Int
        let content: String
    }

    let title: String
    let sourceFilename: String
    let pageCount: Int
    let characterCount: Int
    let chunks: [Chunk]
}

actor PDFKnowledgeImporter {
    func parse(url: URL) throws -> ParsedKnowledgeDocument {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let document = PDFDocument(url: url) else {
            throw PDFImportError.cannotOpen
        }

        var chunks: [ParsedKnowledgeDocument.Chunk] = []
        var totalCharacters = 0
        var sequence = 0

        for pageIndex in 0..<document.pageCount {
            guard let pageText = document.page(at: pageIndex)?.string else { continue }
            let cleaned = clean(pageText)
            totalCharacters += cleaned.count
            for part in split(cleaned, maximumLength: 1_200, overlap: 160) where !part.isEmpty {
                chunks.append(
                    .init(
                        pageNumber: pageIndex + 1,
                        sequence: sequence,
                        content: part
                    )
                )
                sequence += 1
            }
        }

        guard !chunks.isEmpty else {
            throw PDFImportError.noExtractableText
        }

        return ParsedKnowledgeDocument(
            title: url.deletingPathExtension().lastPathComponent,
            sourceFilename: url.lastPathComponent,
            pageCount: document.pageCount,
            characterCount: totalCharacters,
            chunks: chunks
        )
    }

    private func clean(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func split(_ text: String, maximumLength: Int, overlap: Int) -> [String] {
        guard text.count > maximumLength else { return [text] }
        var chunks: [String] = []
        var start = text.startIndex

        while start < text.endIndex {
            let end = text.index(start, offsetBy: maximumLength, limitedBy: text.endIndex)
                ?? text.endIndex
            chunks.append(String(text[start..<end]))
            guard end < text.endIndex else { break }
            let overlapped = text.index(end, offsetBy: -overlap, limitedBy: start) ?? end
            start = overlapped > start ? overlapped : end
        }
        return chunks
    }
}

enum PDFImportError: LocalizedError {
    case cannotOpen
    case noExtractableText

    var errorDescription: String? {
        switch self {
        case .cannotOpen:
            "无法打开这个 PDF。"
        case .noExtractableText:
            "PDF 中没有可提取文字；扫描版资料需要先进行 OCR。"
        }
    }
}

