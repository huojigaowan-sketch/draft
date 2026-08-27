import Foundation

enum DramaticAnchorResolver {
    static func anchor(
        quotedText: String,
        sceneText: String,
        sceneRecordID: UUID?,
        sceneContractID: UUID?
    ) -> DramaticSourceAnchor {
        let source = sceneText as NSString
        let quote = quotedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let exactRange = quote.isEmpty
            ? NSRange(location: 0, length: 0)
            : source.range(of: quote)
        let resolvedRange: NSRange
        if exactRange.location != NSNotFound {
            resolvedRange = exactRange
        } else if let fuzzy = fuzzyRange(of: quote, in: sceneText) {
            resolvedRange = fuzzy
        } else {
            resolvedRange = NSRange(location: 0, length: min(source.length, 1))
        }

        let paragraphs = FountainParser.paragraphs(in: sceneText)
        let intersecting = paragraphs.filter {
            resolvedRange.length == 0
                ? $0.utf16Range.location == resolvedRange.location
                : NSIntersectionRange($0.utf16Range, resolvedRange).length > 0
        }
        let startParagraph = intersecting.first?.index ?? 0
        let endParagraph = intersecting.last?.index ?? startParagraph
        let leadingStart = max(resolvedRange.location - 80, 0)
        let trailingEnd = min(NSMaxRange(resolvedRange) + 80, source.length)
        let leading = source.substring(
            with: NSRange(
                location: leadingStart,
                length: max(resolvedRange.location - leadingStart, 0)
            )
        )
        let trailing = source.substring(
            with: NSRange(
                location: min(NSMaxRange(resolvedRange), source.length),
                length: max(trailingEnd - min(NSMaxRange(resolvedRange), source.length), 0)
            )
        )

        return DramaticSourceAnchor(
            sceneRecordID: sceneRecordID,
            sceneContractID: sceneContractID,
            localUTF16Location: resolvedRange.location,
            localUTF16Length: resolvedRange.length,
            startParagraph: startParagraph,
            endParagraph: endParagraph,
            quotedText: quote,
            leadingContext: String(leading.suffix(80)),
            trailingContext: String(trailing.prefix(80)),
            sourceFingerprint: ScreenplayReviewEngine.fingerprint(sceneText)
        )
    }

    static func reconciled(
        _ anchor: DramaticSourceAnchor,
        in sceneText: String
    ) -> DramaticSourceAnchor? {
        let currentFingerprint = ScreenplayReviewEngine.fingerprint(sceneText)
        if anchor.sourceFingerprint == currentFingerprint { return anchor }
        let candidate = self.anchor(
            quotedText: anchor.quotedText,
            sceneText: sceneText,
            sceneRecordID: anchor.sceneRecordID,
            sceneContractID: anchor.sceneContractID
        )
        guard candidate.localUTF16Length > 0 else { return nil }
        return candidate
    }

    private static func fuzzyRange(of quote: String, in source: String) -> NSRange? {
        let compactQuote = compact(quote)
        guard compactQuote.count >= 4 else { return nil }
        let paragraphs = FountainParser.paragraphs(in: source)
        if let paragraph = paragraphs.first(where: {
            let candidate = compact($0.trimmedText)
            return candidate.contains(compactQuote) || compactQuote.contains(candidate)
        }) {
            return paragraph.utf16Range
        }
        return nil
    }

    private static func compact(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .trimmingCharacters(in: .punctuationCharacters)
    }
}
