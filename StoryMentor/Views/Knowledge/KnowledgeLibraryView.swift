import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct KnowledgeLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \KnowledgeDocument.importedAt, order: .reverse)
    private var documents: [KnowledgeDocument]

    @State private var showingMarkdownImporter = false
    @State private var isImporting = false
    @State private var importStatus = ""
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var pendingDeletion: KnowledgeDocument?

    private let markdownImporter = MarkdownKnowledgeImporter()

    private var builtInKnowledgeLibraryURL: URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("KnowledgeBooks")
            .appendingPathComponent("Markdown")
            .standardized
    }

    private var totalChunks: Int {
        documents.reduce(0) { $0 + $1.totalChunkCount }
    }

    private var totalCharacters: Int {
        documents.reduce(0) { $0 + $1.characterCount }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                privacyCard

                if documents.isEmpty {
                    emptyState
                } else {
                    documentGrid
                }
            }
            .padding(28)
            .frame(maxWidth: 1_050)
            .frame(maxWidth: .infinity)
        }
        .fileImporter(
            isPresented: $showingMarkdownImporter,
            allowedContentTypes: [.folder, .storyMentorMarkdown],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importMarkdownSources(urls)
            case .failure(let error):
                present(error)
            }
        }
        .confirmationDialog(
            "删除“\(pendingDeletion?.title ?? "资料")”？",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                deletePendingDocument()
            }
            .keyboardShortcut(.defaultAction)
            Button("取消", role: .cancel) {
                pendingDeletion = nil
            }
            .keyboardShortcut(.cancelAction)
        }
        .alert("知识库操作失败", isPresented: $showingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                EyebrowLabel(text: "Private Theory RAG")
                Text("私人编剧理论库")
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                Text("\(documents.count) 本资料 · \(totalChunks.formatted()) 个本地理论片段 · \(totalCharacters.formatted()) 字符")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 10) {
                if builtInKnowledgeLibraryURL != nil {
                    Button {
                        importBuiltInKnowledgeLibrary()
                    } label: {
                        if isImporting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("导入内置书库", systemImage: "books.vertical")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isImporting)
                }
                Button {
                    showingMarkdownImporter = true
                } label: {
                    if isImporting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("导入 Markdown 文件夹", systemImage: "folder.badge.plus")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isImporting)
            }
        }
    }

    private var privacyCard: some View {
        StudioCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "lock.square.stack.fill")
                    .font(.title2)
                    .foregroundStyle(StudioTheme.mint)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Markdown 优先，本地索引")
                        .font(.headline)
                    Text("导入时会按章节和段落切片，自动标记人物、欲望、对抗、结构、场景、对白、改编等理论主题。整本书不会发送给 DeepSeek；每次诊断只会检索最多 6 条、多书分散的证据，默认总预算约 3,600 字符。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !importStatus.isEmpty {
                        Text(importStatus)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(StudioTheme.accent)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        StudioCard {
            VStack(spacing: 16) {
                Image(systemName: "text.document.fill")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(StudioTheme.accent)
                Text("导入你的编剧理论书库")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                Text("选择单个 `.md` 文件，或直接选择包含整套资料的文件夹。")
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("选择 Markdown 文件夹", systemImage: "folder") {
                        showingMarkdownImporter = true
                    }
                    .buttonStyle(.borderedProminent)

                    if builtInKnowledgeLibraryURL != nil {
                        Button("导入内置书库", systemImage: "books.vertical") {
                            importBuiltInKnowledgeLibrary()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isImporting)
                    }
                }
                if builtInKnowledgeLibraryURL != nil {
                    Text("已检测到内置书库目录。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(34)
        }
    }

    private func importBuiltInKnowledgeLibrary() {
        guard let url = builtInKnowledgeLibraryURL else { return }
        importMarkdownSources([url])
    }

    private var documentGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
            ForEach(documents) { document in
                StudioCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            Image(systemName: document.sourceType == "markdown" ? "text.document.fill" : "doc.richtext.fill")
                                .foregroundStyle(StudioTheme.accent)
                                .font(.title3)
                            Spacer()
                            Button(role: .destructive) {
                                pendingDeletion = document
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }

                        Text(document.title)
                            .font(.headline)
                            .lineLimit(2)
                        Text("\(document.sourceType.uppercased()) · \(document.totalChunkCount) 片段 · \(document.sectionCount) 节")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !document.topicSummary.isEmpty {
                            Text(document.topicSummary)
                                .font(.caption2)
                                .foregroundStyle(StudioTheme.sky)
                                .lineLimit(2)
                        }
                        Text(document.importedAt, format: .dateTime.year().month().day())
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func importMarkdownSources(_ urls: [URL]) {
        Task {
            isImporting = true
            defer { isImporting = false }

            do {
                importStatus = "正在扫描 Markdown 章节结构…"
                let parsedDocuments = try await markdownImporter.parse(urls: urls)
                var knownFingerprints = Set(documents.map(\.sourceFingerprint).filter { !$0.isEmpty })
                var importedCount = 0
                var skippedCount = 0
                var failedNames: [String] = []

                for (index, parsed) in parsedDocuments.enumerated() {
                    importStatus = "正在建立 \(index + 1)/\(parsedDocuments.count)：\(parsed.title)"
                    guard !knownFingerprints.contains(parsed.sourceFingerprint) else {
                        skippedCount += 1
                        continue
                    }

                    let document = KnowledgeDocument(
                        title: parsed.title,
                        sourceFilename: parsed.sourceFilename,
                        sourceType: parsed.sourceType,
                        sourceFingerprint: parsed.sourceFingerprint,
                        pageCount: 0,
                        sectionCount: parsed.sectionCount,
                        characterCount: parsed.characterCount,
                        topicSummary: parsed.topicSummary
                    )
                    modelContext.insert(document)

                    do {
                        document.indexedChunkCount = try await TheoryIndexStore.shared.index(
                            documentID: document.id,
                            document: parsed
                        )
                        knownFingerprints.insert(parsed.sourceFingerprint)
                        importedCount += 1
                    } catch {
                        modelContext.delete(document)
                        failedNames.append(parsed.title)
                    }
                }

                try ProjectPersistenceStore.savePendingChanges(in: modelContext)
                var result = "导入完成：\(importedCount) 本"
                if skippedCount > 0 { result += "，跳过 \(skippedCount) 本重复资料" }
                if !failedNames.isEmpty { result += "，\(failedNames.count) 本未能索引" }
                importStatus = result
            } catch {
                present(error)
            }
        }
    }

    private func deletePendingDocument() {
        guard let pendingDeletion else { return }
        Task {
            do {
                try await TheoryIndexStore.shared.remove(documentID: pendingDeletion.id)
                modelContext.delete(pendingDeletion)
                try ProjectPersistenceStore.savePendingChanges(in: modelContext)
                self.pendingDeletion = nil
            } catch {
                present(error)
            }
        }
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
        importStatus = ""
    }
}

private extension UTType {
    static var storyMentorMarkdown: UTType {
        UTType(filenameExtension: "md") ?? .plainText
    }
}
