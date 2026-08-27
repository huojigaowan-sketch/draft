@preconcurrency import Foundation

struct RealityResearchRequest: Codable, Sendable {
    let title: String
    let query: String
    let sourceURL: String
    let sourceText: String
    let authorIntent: String
    let depth: String
    let maxSources: Int
    let firecrawlAPIKey: String
}

struct RealityResearchEngine {
    func research(_ request: RealityResearchRequest) async throws -> RealityResearchResult {
        let firecrawlKey = request.firecrawlAPIKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !firecrawlKey.isEmpty {
            return try await FirecrawlResearchBackend().research(
                request,
                apiKey: firecrawlKey
            )
        }
        return try await NativeResearchBackend().research(
            request,
            fallbackReason: "未配置 Firecrawl，使用开放资料源回退。"
        )
    }
}

private struct FirecrawlResearchBackend {
    private struct SearchPayload: Encodable {
        let query: String
        let limit: Int
        let sources: [String]
        let timeout: Int
        let ignoreInvalidURLs: Bool
        let highlights: Bool
    }

    private struct SearchResponse: Decodable {
        struct SearchData: Decodable {
            let web: [SearchItem]?
            let news: [SearchItem]?
        }

        struct SearchItem: Decodable {
            struct Metadata: Decodable {
                let title: String?
                let description: String?
                let sourceURL: String?
                let url: String?
            }

            let title: String?
            let description: String?
            let snippet: String?
            let url: String?
            let date: String?
            let markdown: String?
            let category: String?
            let metadata: Metadata?
        }

        let success: Bool
        let data: SearchData?
        let error: String?
        let warning: String?
    }

    private struct ErrorEnvelope: Decodable {
        let error: String?
        let message: String?
    }

    func research(
        _ request: RealityResearchRequest,
        apiKey: String
    ) async throws -> RealityResearchResult {
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw RealityResearchError.emptyQuery }

        let perSourceLimit = max(
            4,
            min(15, Int(ceil(Double(max(1, request.maxSources)) / 2)))
        )
        let endpoint = URL(string: "https://api.firecrawl.dev/v2/search")!
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 75
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(
            SearchPayload(
                query: String(query.prefix(500)),
                limit: perSourceLimit,
                sources: ["web", "news"],
                timeout: 60_000,
                ignoreInvalidURLs: true,
                highlights: true
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw RealityResearchError.backendFailed(
                "Firecrawl 网络请求失败：\(error.localizedDescription)"
            )
        }
        guard let http = response as? HTTPURLResponse else {
            throw RealityResearchError.backendFailed("Firecrawl 没有返回 HTTP 响应。")
        }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            let detail = envelope?.error
                ?? envelope?.message
                ?? "HTTP \(http.statusCode)"
            throw RealityResearchError.backendFailed(
                "Firecrawl 返回错误（\(http.statusCode)）：\(detail)"
            )
        }

        let decoded: SearchResponse
        do {
            decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        } catch {
            throw RealityResearchError.backendFailed(
                "无法解析 Firecrawl v2 搜索结果：\(error.localizedDescription)"
            )
        }
        guard decoded.success else {
            throw RealityResearchError.backendFailed(
                "Firecrawl 搜索失败：\(decoded.error ?? "未知错误")"
            )
        }

        var sources = (decoded.data?.web ?? []).compactMap {
            source(from: $0, query: query, isNews: false)
        }
        sources += (decoded.data?.news ?? []).compactMap {
            source(from: $0, query: query, isNews: true)
        }

        let sourceText = request.sourceText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !sourceText.isEmpty {
            sources.insert(
                ResearchSourceRecord(
                    id: UUID(),
                    title: request.title.isEmpty ? "用户提供的原始材料" : request.title,
                    url: request.sourceURL,
                    publisher: "用户材料",
                    publishedAt: "",
                    kind: "original",
                    snippet: String(sourceText.prefix(1_200)),
                    query: query,
                    reliability: 0.95,
                    provider: "Local Source"
                ),
                at: 0
            )
        }

        let uniqueSources = Array(
            deduplicate(sources).prefix(max(1, request.maxSources))
        )
        guard !uniqueSources.isEmpty else {
            throw RealityResearchError.noSources
        }
        let noteParts = [
            "Firecrawl v2 Search",
            decoded.warning?.isEmpty == false ? decoded.warning : nil
        ].compactMap { $0 }
        return ResearchResultBuilder.build(
            request: request,
            sources: uniqueSources,
            backendNote: noteParts.joined(separator: " · ")
        )
    }

    private func source(
        from item: SearchResponse.SearchItem,
        query: String,
        isNews: Bool
    ) -> ResearchSourceRecord? {
        let url = item.url
            ?? item.metadata?.sourceURL
            ?? item.metadata?.url
            ?? ""
        let title = item.title
            ?? item.metadata?.title
            ?? URL(string: url)?.host()
            ?? ""
        guard !title.isEmpty, !url.isEmpty else { return nil }
        let host = URL(string: url)?.host() ?? "网页来源"
        let rawSnippet = item.markdown
            ?? item.snippet
            ?? item.description
            ?? item.metadata?.description
            ?? ""
        return ResearchSourceRecord(
            id: UUID(),
            title: title,
            url: url,
            publisher: host,
            publishedAt: item.date ?? "",
            kind: classify(
                url: url,
                category: item.category,
                isNews: isNews
            ),
            snippet: normalizedSnippet(rawSnippet),
            query: query,
            reliability: reliability(for: url, isNews: isNews),
            provider: isNews ? "Firecrawl News" : "Firecrawl Web"
        )
    }

    private func classify(
        url: String,
        category: String?,
        isNews: Bool
    ) -> String {
        if isNews { return "news" }
        let value = "\(url) \(category ?? "")".lowercased()
        if value.contains("wikipedia.org") || value.contains("britannica.com") {
            return "encyclopedia"
        }
        if value.contains("archive.org")
            || value.contains("museum")
            || value.contains("library") {
            return "archive"
        }
        let academicMarkers = [
            "arxiv.org", "doi.org", "pubmed", "nature.com", "science.org",
            "springer.com", "jstor.org", ".edu/", "research"
        ]
        if academicMarkers.contains(where: value.contains) {
            return "academic"
        }
        return "web"
    }

    private func reliability(for url: String, isNews: Bool) -> Double {
        if isNews { return 0.74 }
        let value = url.lowercased()
        if value.contains(".gov")
            || value.contains(".edu")
            || value.contains("doi.org")
            || value.contains("pubmed") {
            return 0.9
        }
        if value.contains("wikipedia.org") { return 0.78 }
        return 0.7
    }

    private func normalizedSnippet(_ value: String) -> String {
        String(
            value
                .replacingOccurrences(
                    of: #"!\[[^\]]*\]\([^)]+\)"#,
                    with: " ",
                    options: .regularExpression
                )
                .replacingOccurrences(
                    of: #"\[([^\]]+)\]\([^)]+\)"#,
                    with: "$1",
                    options: .regularExpression
                )
                .replacingOccurrences(
                    of: #"[#>*_`|]+"#,
                    with: " ",
                    options: .regularExpression
                )
                .replacingOccurrences(
                    of: #"\s+"#,
                    with: " ",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(1_200)
        )
    }

    private func deduplicate(
        _ sources: [ResearchSourceRecord]
    ) -> [ResearchSourceRecord] {
        var seen = Set<String>()
        return sources.filter { source in
            let normalizedURL = source.url
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let key = normalizedURL.isEmpty
                ? "title:\(source.title.lowercased())"
                : "url:\(normalizedURL)"
            return seen.insert(key).inserted
        }
    }
}

private struct NativeResearchBackend {
    func research(
        _ request: RealityResearchRequest,
        fallbackReason: String
    ) async throws -> RealityResearchResult {
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw RealityResearchError.emptyQuery }

        async let gdelt = gdeltSources(query: query, limit: providerLimit(request))
        async let wikipedia = wikipediaSources(query: query, limit: providerLimit(request))
        async let wikidata = wikidataSources(query: query, limit: 6)
        async let openAlex = openAlexSources(query: query, limit: providerLimit(request))
        async let archive = archiveSources(query: query, limit: providerLimit(request))

        var sources = await gdelt + wikipedia + wikidata + openAlex + archive
        if !request.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sources.insert(
                ResearchSourceRecord(
                    id: UUID(),
                    title: request.title.isEmpty ? "用户提供的原始材料" : request.title,
                    url: request.sourceURL,
                    publisher: "用户材料",
                    publishedAt: "",
                    kind: "original",
                    snippet: String(request.sourceText.prefix(1_200)),
                    query: query,
                    reliability: 0.85,
                    provider: "Local Source"
                ),
                at: 0
            )
        }

        let uniqueSources = deduplicate(sources).prefix(request.maxSources)
        guard !uniqueSources.isEmpty else {
            throw RealityResearchError.noSources
        }
        return ResearchResultBuilder.build(
            request: request,
            sources: Array(uniqueSources),
            backendNote: "采用纯 Swift 原生检索来源：\(fallbackReason)"
        )
    }

    private func providerLimit(_ request: RealityResearchRequest) -> Int {
        max(4, min(10, request.maxSources / 4))
    }

    private func gdeltSources(query: String, limit: Int) async -> [ResearchSourceRecord] {
        var components = URLComponents(string: "https://api.gdeltproject.org/api/v2/doc/doc")
        components?.queryItems = [
            .init(name: "query", value: query),
            .init(name: "mode", value: "ArtList"),
            .init(name: "format", value: "json"),
            .init(name: "maxrecords", value: String(limit)),
            .init(name: "sort", value: "HybridRel")
        ]
        guard let url = components?.url,
              let object = try? await fetchJSON(url),
              let root = object as? [String: Any],
              let articles = root["articles"] as? [[String: Any]] else { return [] }
        return articles.compactMap { article in
            guard let title = article["title"] as? String,
                  let url = article["url"] as? String else { return nil }
            return ResearchSourceRecord(
                id: UUID(),
                title: title,
                url: url,
                publisher: (article["domain"] as? String) ?? "新闻来源",
                publishedAt: (article["seendate"] as? String) ?? "",
                kind: "news",
                snippet: [
                    article["sourcecountry"] as? String,
                    article["language"] as? String
                ].compactMap { $0 }.joined(separator: " · "),
                query: query,
                reliability: 0.72,
                provider: "GDELT"
            )
        }
    }

    private func wikipediaSources(query: String, limit: Int) async -> [ResearchSourceRecord] {
        var components = URLComponents(string: "https://zh.wikipedia.org/w/api.php")
        components?.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "list", value: "search"),
            .init(name: "srsearch", value: query),
            .init(name: "srlimit", value: String(limit)),
            .init(name: "format", value: "json"),
            .init(name: "utf8", value: "1")
        ]
        guard let url = components?.url,
              let object = try? await fetchJSON(url),
              let root = object as? [String: Any],
              let queryObject = root["query"] as? [String: Any],
              let results = queryObject["search"] as? [[String: Any]] else { return [] }
        return results.compactMap { item in
            guard let title = item["title"] as? String else { return nil }
            let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
            return ResearchSourceRecord(
                id: UUID(),
                title: title,
                url: "https://zh.wikipedia.org/wiki/\(encoded)",
                publisher: "Wikipedia",
                publishedAt: (item["timestamp"] as? String) ?? "",
                kind: "encyclopedia",
                snippet: cleanHTML((item["snippet"] as? String) ?? ""),
                query: query,
                reliability: 0.78,
                provider: "MediaWiki"
            )
        }
    }

    private func wikidataSources(query: String, limit: Int) async -> [ResearchSourceRecord] {
        var components = URLComponents(string: "https://www.wikidata.org/w/api.php")
        components?.queryItems = [
            .init(name: "action", value: "wbsearchentities"),
            .init(name: "search", value: query),
            .init(name: "language", value: "zh"),
            .init(name: "uselang", value: "zh"),
            .init(name: "limit", value: String(limit)),
            .init(name: "format", value: "json")
        ]
        guard let url = components?.url,
              let object = try? await fetchJSON(url),
              let root = object as? [String: Any],
              let results = root["search"] as? [[String: Any]] else { return [] }
        return results.compactMap { item in
            guard let label = item["label"] as? String else { return nil }
            return ResearchSourceRecord(
                id: UUID(),
                title: label,
                url: (item["concepturi"] as? String) ?? "",
                publisher: "Wikidata",
                publishedAt: "",
                kind: "entity",
                snippet: (item["description"] as? String) ?? "",
                query: query,
                reliability: 0.82,
                provider: "Wikidata"
            )
        }
    }

    private func openAlexSources(query: String, limit: Int) async -> [ResearchSourceRecord] {
        var components = URLComponents(string: "https://api.openalex.org/works")
        components?.queryItems = [
            .init(name: "search", value: query),
            .init(name: "per-page", value: String(limit))
        ]
        guard let url = components?.url,
              let object = try? await fetchJSON(url),
              let root = object as? [String: Any],
              let results = root["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { item in
            guard let title = item["display_name"] as? String else { return nil }
            let location = item["primary_location"] as? [String: Any]
            return ResearchSourceRecord(
                id: UUID(),
                title: title,
                url: (item["doi"] as? String)
                    ?? (location?["landing_page_url"] as? String)
                    ?? (item["id"] as? String)
                    ?? "",
                publisher: "OpenAlex",
                publishedAt: (item["publication_year"] as? Int).map(String.init) ?? "",
                kind: "academic",
                snippet: (item["type"] as? String) ?? "学术研究",
                query: query,
                reliability: 0.88,
                provider: "OpenAlex"
            )
        }
    }

    private func archiveSources(query: String, limit: Int) async -> [ResearchSourceRecord] {
        var components = URLComponents(string: "https://archive.org/advancedsearch.php")
        components?.queryItems = [
            .init(name: "q", value: query),
            .init(name: "fl[]", value: "identifier,title,description,creator,date,mediatype"),
            .init(name: "rows", value: String(limit)),
            .init(name: "page", value: "1"),
            .init(name: "output", value: "json")
        ]
        guard let url = components?.url,
              let object = try? await fetchJSON(url),
              let root = object as? [String: Any],
              let response = root["response"] as? [String: Any],
              let docs = response["docs"] as? [[String: Any]] else { return [] }
        return docs.compactMap { item in
            guard let identifier = item["identifier"] as? String else { return nil }
            let title = (item["title"] as? String) ?? identifier
            return ResearchSourceRecord(
                id: UUID(),
                title: title,
                url: "https://archive.org/details/\(identifier)",
                publisher: stringify(item["creator"], fallback: "Internet Archive"),
                publishedAt: stringify(item["date"], fallback: ""),
                kind: "archive",
                snippet: String(stringify(item["description"], fallback: "开放档案").prefix(500)),
                query: query,
                reliability: 0.84,
                provider: "Internet Archive"
            )
        }
    }

    private func fetchJSON(_ url: URL) async throws -> Any {
        var request = URLRequest(url: url)
        request.timeoutInterval = 18
        request.setValue(
            "StoryMentor/1.0 (macOS research assistant)",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw RealityResearchError.network
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    private func deduplicate(_ sources: [ResearchSourceRecord]) -> [ResearchSourceRecord] {
        var seen = Set<String>()
        return sources.filter { source in
            let key = source.url.isEmpty
                ? source.title.lowercased()
                : source.url.lowercased()
            return seen.insert(key).inserted
        }
    }

    private func cleanHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stringify(_ value: Any?, fallback: String) -> String {
        if let string = value as? String { return string }
        if let strings = value as? [String] { return strings.joined(separator: "、") }
        return fallback
    }
}

private enum ResearchResultBuilder {
    static func build(
        request: RealityResearchRequest,
        sources: [ResearchSourceRecord],
        backendNote: String
    ) -> RealityResearchResult {
        let claims = Array(sources.prefix(16)).map { source in
            EvidenceClaim(
                id: UUID(),
                text: source.snippet.isEmpty ? source.title : "\(source.title)：\(source.snippet)",
                dimension: dimension(for: source),
                confidence: source.reliability,
                sourceIDs: [source.id]
            )
        }
        let entities = Array(
            sources
                .filter { ["entity", "encyclopedia"].contains($0.kind) }
                .prefix(10)
        ).map {
            ResearchEntity(
                id: UUID(),
                name: $0.title,
                kind: $0.kind == "entity" ? "人物 / 组织 / 地点" : "知识实体",
                detail: $0.snippet,
                sourceIDs: [$0.id]
            )
        }
        let timeline = Array(
            sources
                .filter { !$0.publishedAt.isEmpty }
                .sorted { $0.publishedAt < $1.publishedAt }
                .prefix(10)
        ).map {
            ResearchTimelineItem(
                id: UUID(),
                date: $0.publishedAt,
                event: $0.title,
                sourceIDs: [$0.id]
            )
        }
        let analogues = sources
            .filter { ["archive", "academic", "encyclopedia"].contains($0.kind) }
            .prefix(8)
            .map(\.title)
        let providers = Array(Set(sources.map(\.provider))).sorted()
        let pressures = dramaticPressures(sources)
        let coverage = coverage(sources)
        let openQuestions = openQuestions(coverage)
        let promptContext = promptContext(
            request: request,
            sources: sources,
            claims: claims,
            analogues: Array(analogues),
            openQuestions: openQuestions
        )
        return RealityResearchResult(
            summary: "围绕“\(request.query)”从 \(providers.count) 类资料渠道汇集了 \(sources.count) 个去重来源，并建立了事实、人物、制度与历史回声的可追溯底座。",
            sources: sources,
            claims: claims,
            entities: entities,
            timeline: timeline,
            analogues: Array(analogues),
            dramaticPressures: pressures,
            openQuestions: openQuestions,
            coverage: coverage,
            providers: providers,
            promptContext: promptContext,
            backendNote: backendNote
        )
    }

    private static func dimension(for source: ResearchSourceRecord) -> String {
        switch source.kind {
        case "news": "事实与争议"
        case "academic": "制度与专业"
        case "archive": "历史回声"
        case "entity", "encyclopedia": "人物与关系"
        case "original": "原始材料"
        default: "现实细节"
        }
    }

    private static func dramaticPressures(
        _ sources: [ResearchSourceRecord]
    ) -> [DramaticPressure] {
        let relation = sources.first { ["entity", "encyclopedia"].contains($0.kind) }
        let institution = sources.first { ["academic", "news"].contains($0.kind) }
        let history = sources.first { $0.kind == "archive" }
        let material = sources.first { !$0.snippet.isEmpty }
        let candidates: [(String, String, String, ResearchSourceRecord?)] = [
            ("关系裂缝", "谁与谁需要彼此，却会因这件事被迫站到对立面？", "人物关系", relation),
            ("制度齿轮", "哪条真实规则会让一个正确选择变得代价高昂？", "制度冲突", institution),
            ("历史回声", "过去发生过什么，使今天的人误以为结局早已注定？", "历史类比", history),
            ("可拍细节", "哪个地点、物件或流程能让观众立刻相信这个世界？", "生活质感", material)
        ]
        return candidates.map { title, question, angle, source in
            DramaticPressure(
                id: UUID(),
                title: title,
                question: question,
                angle: angle,
                sourceIDs: source.map { [$0.id] } ?? []
            )
        }
    }

    private static func coverage(
        _ sources: [ResearchSourceRecord]
    ) -> [ResearchCoverageDimension] {
        let kinds = Dictionary(grouping: sources, by: \.kind)
        let publishers = Set(sources.map(\.publisher)).count
        func score(_ value: Double) -> Double { min(max(value, 0), 1) }
        return [
            .init(
                id: "facts",
                label: "事实基础",
                score: score(Double(sources.count) / 16),
                note: "\(sources.count) 个去重来源"
            ),
            .init(
                id: "people",
                label: "人物关系",
                score: score(Double((kinds["entity"]?.count ?? 0) + (kinds["encyclopedia"]?.count ?? 0)) / 6),
                note: "人物、组织与地点实体"
            ),
            .init(
                id: "institution",
                label: "制度细节",
                score: score(Double((kinds["academic"]?.count ?? 0) + (kinds["news"]?.count ?? 0)) / 10),
                note: "新闻与研究交叉支持"
            ),
            .init(
                id: "history",
                label: "历史背景",
                score: score(Double((kinds["archive"]?.count ?? 0) + (kinds["encyclopedia"]?.count ?? 0)) / 8),
                note: "档案、书籍与知识条目"
            ),
            .init(
                id: "opposition",
                label: "视角多样",
                score: score(Double(publishers) / 12),
                note: "\(publishers) 个不同发布者"
            ),
            .init(
                id: "texture",
                label: "生活质感",
                score: score(Double(sources.filter { $0.snippet.count > 80 }.count) / 10),
                note: "可用于人物与场景的具体资料"
            )
        ]
    }

    private static func openQuestions(
        _ coverage: [ResearchCoverageDimension]
    ) -> [String] {
        var questions = [
            "哪些报道来自同一通讯社转载，不能被误当成相互独立的证据？",
            "真实人物没有公开说明的动机，哪些必须保留为未知或改写为虚构？"
        ]
        if let weakest = coverage.min(by: { $0.score < $1.score }), weakest.score < 0.55 {
            questions.append("“\(weakest.label)”目前覆盖最低，是否继续深挖这一维度？")
        }
        return questions
    }

    private static func promptContext(
        request: RealityResearchRequest,
        sources: [ResearchSourceRecord],
        claims: [EvidenceClaim],
        analogues: [String],
        openQuestions: [String]
    ) -> String {
        let sourceIndex = Dictionary(
            uniqueKeysWithValues: sources.enumerated().map { ($0.element.id, $0.offset + 1) }
        )
        let evidenceText = claims.prefix(14).map { claim in
            let references = claim.sourceIDs.compactMap { sourceIndex[$0] }
                .map { "[S\($0)]" }
                .joined(separator: " ")
            return "- \(references) \(claim.text)"
        }.joined(separator: "\n")
        let sourceText = sources.prefix(24).enumerated().map { index, source in
            "[S\(index + 1)] \(source.publisher)｜\(source.title)｜\(source.publishedAt)｜\(source.url)"
        }.joined(separator: "\n")
        return """
        【现实资料包】
        研究主题：\(request.query)
        作者关注：\(request.authorIntent.isEmpty ? "从资料本身寻找戏剧性" : request.authorIntent)
        研究要求：事实与推测分开；不得把真实人物未公开的动机写成事实；引用编号必须能在来源表中找到。

        【可核实证据】
        \(evidenceText)

        【历史与跨领域类比】
        \(analogues.isEmpty ? "暂未发现可靠类比。" : analogues.map { "- \($0)" }.joined(separator: "\n"))

        【仍需核实】
        \(openQuestions.map { "- \($0)" }.joined(separator: "\n"))

        【来源索引】
        \(sourceText)
        """
    }
}

enum RealityResearchError: LocalizedError {
    case emptyQuery
    case backendFailed(String)
    case noSources
    case network

    var errorDescription: String? {
        switch self {
        case .emptyQuery: "请先输入要调查的事件、人物、新闻或历史主题。"
        case .backendFailed(let detail): "研究模块未能完成：\(detail)"
        case .noSources: "暂时没有找到可用资料，请换一个更具体的关键词。"
        case .network: "资料源暂时无法访问。"
        }
    }
}
