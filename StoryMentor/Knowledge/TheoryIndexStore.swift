@preconcurrency import SQLite3
import Foundation

struct TheoryIndexStatistics: Sendable {
    let documentCount: Int
    let chunkCount: Int
    let characterCount: Int
}

actor TheoryIndexStore {
    static let shared = TheoryIndexStore()
    private static let bundledLibraryVersion = "writer-library-2026-07-26"

    private var database: OpaquePointer?

    isolated deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func index(documentID: UUID, document: TheoryDocumentInput) throws -> Int {
        let database = try connection()
        try execute("BEGIN IMMEDIATE TRANSACTION", database: database)

        do {
            try delete(documentID: documentID, database: database)
            let statement = try prepare(
                """
                INSERT INTO theory_fts
                (chunk_id, document_id, title, heading_path, topic_tokens, display_topics, content, sequence, char_count)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                database: database
            )
            defer { sqlite3_finalize(statement) }

            for (offset, chunk) in document.chunks.enumerated() {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                try bind("\(documentID.uuidString)-\(offset)", at: 1, statement: statement, database: database)
                try bind(documentID.uuidString, at: 2, statement: statement, database: database)
                try bind(document.title, at: 3, statement: statement, database: database)
                try bind(chunk.headingPath, at: 4, statement: statement, database: database)
                try bind(chunk.topicTokens, at: 5, statement: statement, database: database)
                try bind(chunk.displayTopics, at: 6, statement: statement, database: database)
                try bind(chunk.content, at: 7, statement: statement, database: database)
                try bind(Int64(chunk.sequence), at: 8, statement: statement, database: database)
                try bind(Int64(chunk.content.count), at: 9, statement: statement, database: database)
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw indexError(database: database)
                }
            }

            try execute("COMMIT", database: database)
            return document.chunks.count
        } catch {
            try? execute("ROLLBACK", database: database)
            throw error
        }
    }

    func remove(documentID: UUID) throws {
        let database = try connection()
        try delete(documentID: documentID, database: database)
    }

    func search(
        query: String,
        route: TheoryRetrievalRoute,
        maximumMatches: Int = 6,
        maximumCharacters: Int = 3_600
    ) throws -> [TheoryEvidence] {
        let database = try connection()
        let directTerms = englishTerms(in: query)
        let expression = (
            route.ftsTerms.map { "topic_tokens:\($0)" }
                + directTerms.map { "content:\($0)" }
        )
            .joined(separator: " OR ")
        guard !expression.isEmpty else { return [] }

        let statement = try prepare(
            """
            SELECT chunk_id, document_id, title, heading_path, display_topics, content, bm25(theory_fts)
            FROM theory_fts
            WHERE theory_fts MATCH ?
            ORDER BY bm25(theory_fts)
            LIMIT 240
            """,
            database: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(expression, at: 1, statement: statement, database: database)

        let relevanceTerms = Array(
            Set(route.topics.flatMap(\.keywords) + directTerms)
        )
        var candidates: [TheoryEvidence] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let title = columnText(statement, at: 2)
            let heading = columnText(statement, at: 3)
            let topics = columnText(statement, at: 4)
            let content = columnText(statement, at: 5)
            let searchable = "\(heading) \(content.prefix(2_400))".lowercased()
            let lexicalHits = relevanceTerms.reduce(into: 0) { total, term in
                if searchable.contains(term) {
                    total += term.contains(" ") ? 2 : 1
                }
            }
            let evidence = TheoryEvidence(
                id: columnText(statement, at: 0),
                documentID: columnText(statement, at: 1),
                title: title,
                headingPath: heading,
                topics: topics,
                content: content,
                score: Double(lexicalHits * 100) - sqlite3_column_double(statement, 6),
                estimatedTokens: estimatedTokens(for: content)
            )
            candidates.append(evidence)
        }

        let rankedCandidates = candidates.sorted { lhs, rhs in
            lhs.score == rhs.score ? lhs.id < rhs.id : lhs.score > rhs.score
        }
        return diversified(
            candidates: rankedCandidates,
            maximumMatches: maximumMatches,
            maximumCharacters: maximumCharacters
        )
    }

    func statistics() throws -> TheoryIndexStatistics {
        let database = try connection()
        let statement = try prepare(
            "SELECT COUNT(DISTINCT document_id), COUNT(*), COALESCE(SUM(char_count), 0) FROM theory_fts",
            database: database
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw indexError(database: database)
        }
        return TheoryIndexStatistics(
            documentCount: Int(sqlite3_column_int64(statement, 0)),
            chunkCount: Int(sqlite3_column_int64(statement, 1)),
            characterCount: Int(sqlite3_column_int64(statement, 2))
        )
    }

    private func diversified(
        candidates: [TheoryEvidence],
        maximumMatches: Int,
        maximumCharacters: Int
    ) -> [TheoryEvidence] {
        var selected: [TheoryEvidence] = []
        var documentUseCount: [String: Int] = [:]
        var headingUseCount: [String: Int] = [:]
        var remainingCharacters = maximumCharacters

        for candidate in candidates {
            guard selected.count < maximumMatches, remainingCharacters >= 220 else { break }
            guard documentUseCount[candidate.documentID, default: 0] < 2 else { continue }
            let headingKey = "\(candidate.documentID)::\(candidate.headingPath)"
            guard headingUseCount[headingKey, default: 0] < 1 else { continue }

            let maximumExcerpt = min(650, remainingCharacters)
            let excerpt = String(candidate.content.prefix(maximumExcerpt))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard excerpt.count >= 180 else { continue }
            let selectedEvidence = TheoryEvidence(
                id: candidate.id,
                documentID: candidate.documentID,
                title: candidate.title,
                headingPath: candidate.headingPath,
                topics: candidate.topics,
                content: excerpt,
                score: candidate.score,
                estimatedTokens: estimatedTokens(for: excerpt)
            )
            selected.append(selectedEvidence)
            documentUseCount[candidate.documentID, default: 0] += 1
            headingUseCount[headingKey, default: 0] += 1
            remainingCharacters -= excerpt.count
        }
        return selected
    }

    private func connection() throws -> OpaquePointer {
        if let database { return database }

        let fileManager = FileManager.default
        let directory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("StoryMentor", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("TheoryIndex.sqlite")

        var handle: OpaquePointer?
        let status = sqlite3_open_v2(
            url.path,
            &handle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard status == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw TheoryIndexError.openFailed
        }

        database = handle
        try execute("PRAGMA journal_mode = WAL", database: handle)
        try execute("PRAGMA synchronous = NORMAL", database: handle)
        try execute(
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS theory_fts USING fts5(
                chunk_id UNINDEXED,
                document_id UNINDEXED,
                title,
                heading_path,
                topic_tokens,
                display_topics UNINDEXED,
                content,
                sequence UNINDEXED,
                char_count UNINDEXED,
                tokenize = 'unicode61 remove_diacritics 2'
            )
            """,
            database: handle
        )
        try execute(
            "CREATE TABLE IF NOT EXISTS theory_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
            database: handle
        )
        try installBundledLibraryIfNeeded(database: handle)
        return handle
    }

    private func installBundledLibraryIfNeeded(database: OpaquePointer) throws {
        guard let seedURL = Bundle.main.url(forResource: "TheoryIndexSeed", withExtension: "sqlite"),
              try metadataValue(for: "bundledLibraryVersion", database: database) != Self.bundledLibraryVersion else {
            return
        }

        try attachSeedDatabase(at: seedURL, database: database)
        do {
            try execute("BEGIN IMMEDIATE TRANSACTION", database: database)
            try execute("DELETE FROM theory_fts WHERE document_id LIKE 'builtin-%'", database: database)
            try execute(
                """
                INSERT INTO theory_fts
                (chunk_id, document_id, title, heading_path, topic_tokens, display_topics, content, sequence, char_count)
                SELECT chunk_id, document_id, title, heading_path, topic_tokens, display_topics, content, sequence, char_count
                FROM bundled_theory.theory_fts
                """,
                database: database
            )
            try setMetadata(
                Self.bundledLibraryVersion,
                for: "bundledLibraryVersion",
                database: database
            )
            try execute("COMMIT", database: database)
            try execute("DETACH DATABASE bundled_theory", database: database)
        } catch {
            try? execute("ROLLBACK", database: database)
            try? execute("DETACH DATABASE bundled_theory", database: database)
            throw error
        }
    }

    private func attachSeedDatabase(at url: URL, database: OpaquePointer) throws {
        let statement = try prepare("ATTACH DATABASE ? AS bundled_theory", database: database)
        defer { sqlite3_finalize(statement) }
        try bind(url.path, at: 1, statement: statement, database: database)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw indexError(database: database)
        }
    }

    private func metadataValue(for key: String, database: OpaquePointer) throws -> String? {
        let statement = try prepare("SELECT value FROM theory_metadata WHERE key = ?", database: database)
        defer { sqlite3_finalize(statement) }
        try bind(key, at: 1, statement: statement, database: database)
        return sqlite3_step(statement) == SQLITE_ROW ? columnText(statement, at: 0) : nil
    }

    private func setMetadata(_ value: String, for key: String, database: OpaquePointer) throws {
        let statement = try prepare(
            "INSERT OR REPLACE INTO theory_metadata (key, value) VALUES (?, ?)",
            database: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(key, at: 1, statement: statement, database: database)
        try bind(value, at: 2, statement: statement, database: database)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw indexError(database: database)
        }
    }

    private func delete(documentID: UUID, database: OpaquePointer) throws {
        let statement = try prepare("DELETE FROM theory_fts WHERE document_id = ?", database: database)
        defer { sqlite3_finalize(statement) }
        try bind(documentID.uuidString, at: 1, statement: statement, database: database)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw indexError(database: database)
        }
    }

    private func prepare(_ sql: String, database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw indexError(database: database)
        }
        return statement
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw indexError(database: database)
        }
    }

    private func bind(
        _ value: String,
        at index: Int32,
        statement: OpaquePointer,
        database: OpaquePointer
    ) throws {
        let status = value.withCString {
            sqlite3_bind_text(statement, index, $0, -1, sqliteTransient)
        }
        guard status == SQLITE_OK else {
            throw indexError(database: database)
        }
    }

    private func bind(
        _ value: Int64,
        at index: Int32,
        statement: OpaquePointer,
        database: OpaquePointer
    ) throws {
        guard sqlite3_bind_int64(statement, index, value) == SQLITE_OK else {
            throw indexError(database: database)
        }
    }

    private func columnText(_ statement: OpaquePointer, at index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    private func englishTerms(in query: String) -> [String] {
        query.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 && $0.allSatisfy { $0.isLetter || $0.isNumber } }
            .prefix(8)
            .map { $0 }
    }

    private func estimatedTokens(for text: String) -> Int {
        max(1, Int((Double(text.count) * 0.68).rounded(.up)))
    }

    private func indexError(database: OpaquePointer) -> TheoryIndexError {
        let message = String(cString: sqlite3_errmsg(database))
        return .sqlite(message)
    }
}

nonisolated(unsafe) private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum TheoryIndexError: LocalizedError {
    case openFailed
    case sqlite(String)

    nonisolated var errorDescription: String? {
        switch self {
        case .openFailed:
            "无法创建本地理论索引。"
        case .sqlite(let message):
            "本地理论索引错误：\(message)"
        }
    }
}
