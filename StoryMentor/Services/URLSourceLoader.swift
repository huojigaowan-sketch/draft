import AppKit
import Foundation

struct LoadedWebSource {
    let title: String
    let text: String
}

enum URLSourceLoader {
    static func load(_ value: String) async throws -> LoadedWebSource {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            throw URLSourceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(
            "Mozilla/5.0 (Macintosh; Apple Silicon Mac OS X) StoryMentor/1.0",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLSourceError.unreadablePage
        }

        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .unicode)
            ?? ""
        guard !html.isEmpty else {
            throw URLSourceError.unreadablePage
        }

        let title = firstMatch(
            in: html,
            pattern: "<title[^>]*>(.*?)</title>"
        )
        let stripped = html
            .replacingOccurrences(
                of: "<script[\\s\\S]*?</script>",
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: "<style[\\s\\S]*?</style>",
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: "<[^>]+>",
                with: "\n",
                options: .regularExpression
            )
        let decoded = decodeHTMLEntities(stripped)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard decoded.count > 80 else {
            throw URLSourceError.unreadablePage
        }
        return LoadedWebSource(
            title: decodeHTMLEntities(title).trimmingCharacters(in: .whitespacesAndNewlines),
            text: String(decoded.prefix(80_000))
        )
    }

    private static func firstMatch(in text: String, pattern: String) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { return "" }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = expression.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: text) else {
            return ""
        }
        return String(text[capture])
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return text
        }
        return attributed.string
    }
}

enum URLSourceError: LocalizedError {
    case invalidURL
    case unreadablePage

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "请输入完整的 http 或 https 网页地址。"
        case .unreadablePage:
            "无法读取这个网页。可以直接复制正文到素材框。"
        }
    }
}
