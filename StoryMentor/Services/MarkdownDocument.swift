import SwiftUI
import UniformTypeIdentifiers

/// The only writable document type exposed by StoryMentor.
///
/// Fountain-style screenplay text is valid plain-text Markdown, so it remains
/// directly editable after import into Ulysses without creating a second,
/// lossy export representation.
struct MarkdownDocument: FileDocument {
    nonisolated static var readableContentTypes: [UTType] {
        [.storyMentorMarkdownExport, .plainText]
    }

    nonisolated static var writableContentTypes: [UTType] {
        [.storyMentorMarkdownExport]
    }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

extension UTType {
    nonisolated static var storyMentorMarkdownExport: UTType {
        UTType(filenameExtension: "md") ?? .plainText
    }

    nonisolated static var fountainScript: UTType {
        UTType(filenameExtension: "fountain") ?? .plainText
    }
}

struct FountainDocument: FileDocument {
    nonisolated static var readableContentTypes: [UTType] {
        [.fountainScript, .plainText]
    }

    nonisolated static var writableContentTypes: [UTType] {
        [.fountainScript]
    }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
