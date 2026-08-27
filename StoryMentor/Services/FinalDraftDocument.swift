import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    nonisolated static var finalDraftDocument: UTType {
        UTType(filenameExtension: "fdx")
            ?? UTType(
                exportedAs: "com.liuyicheng.storymentor.final-draft-xml",
                conformingTo: .xml
            )
    }
}

/// A native Final Draft XML document. Fountain remains the editable source of
/// truth inside StoryMentor; FDX is generated only at the delivery boundary so
/// its paragraph element types cannot drift from the current screenplay.
struct FinalDraftDocument: FileDocument {
    nonisolated static var readableContentTypes: [UTType] {
        [.finalDraftDocument, .xml]
    }

    nonisolated static var writableContentTypes: [UTType] {
        [.finalDraftDocument]
    }

    private let data: Data

    init(xml: String) {
        data = Data(xml.utf8)
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum FinalDraftXMLExporter {
    static func xml(title: String, screenplayText: String) -> String {
        let standardized = FountainParser.standardizingSceneFlow(
            in: screenplayText
        )
        let paragraphs = FountainParser.paragraphs(in: standardized)
        let contentStart = paragraphs.firstIndex {
            $0.inferredType == .sceneHeading
        } ?? paragraphs.startIndex
        let body = paragraphs[contentStart...]
            .compactMap(paragraphXML)
            .joined(separator: "\n")
        let cleanTitle = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let titlePage = cleanTitle.isEmpty ? "" : """

          <TitlePage>
            <Content>
              <Paragraph Type="Title"><Text>\(xmlEscaped(cleanTitle))</Text></Paragraph>
            </Content>
          </TitlePage>
        """

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <FinalDraft DocumentType="Script" Template="No" Version="1">
          <Content>
        \(body)
          </Content>\(titlePage)
        </FinalDraft>
        """
    }

    private static func paragraphXML(
        _ paragraph: FountainParagraphSnapshot
    ) -> String? {
        var text = paragraph.trimmedText
        guard !text.isEmpty, text != "===" else { return nil }
        guard paragraph.inferredType != .note else { return nil }

        let type: String
        switch paragraph.inferredType {
        case .sceneHeading:
            type = "Scene Heading"
        case .action:
            type = "Action"
        case .character:
            type = "Character"
            text = text.trimmingCharacters(
                in: CharacterSet(charactersIn: "@^ ")
            )
        case .parenthetical:
            type = "Parenthetical"
        case .dialogue:
            type = "Dialogue"
        case .transition:
            type = "Transition"
            text = text.trimmingCharacters(
                in: CharacterSet(charactersIn: ">< ")
            )
        case .note:
            return nil
        }

        guard !text.isEmpty else { return nil }
        return "    <Paragraph Type=\"\(type)\"><Text>\(xmlEscaped(text))</Text></Paragraph>"
    }

    private static func xmlEscaped(_ value: String) -> String {
        let validScalars = value.unicodeScalars.filter { scalar in
            scalar.value == 0x9
                || scalar.value == 0xA
                || scalar.value == 0xD
                || (0x20...0xD7FF).contains(scalar.value)
                || (0xE000...0xFFFD).contains(scalar.value)
                || (0x10000...0x10FFFF).contains(scalar.value)
        }
        return String(String.UnicodeScalarView(validScalars))
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
