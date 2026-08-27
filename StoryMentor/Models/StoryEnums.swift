import Foundation

enum StoryGenre: String, CaseIterable, Codable, Identifiable {
    case unselected = "尚未选择"
    case drama = "剧情"
    case crime = "犯罪"
    case thriller = "惊悚"
    case mystery = "悬疑"
    case romance = "爱情"
    case comedy = "喜剧"
    case scienceFiction = "科幻"
    case fantasy = "奇幻"
    case action = "动作"
    case shortDrama = "短剧"

    var id: String { rawValue }
}

enum CharacterRole: String, CaseIterable, Codable, Identifiable {
    case protagonist = "主角"
    case antagonist = "反派"
    case ally = "伙伴"
    case mentor = "导师"
    case mirror = "镜像人物"
    case loveInterest = "情感关系"
    case supporting = "配角"

    var id: String { rawValue }
}

enum StorySourceType: String, CaseIterable, Codable, Identifiable {
    case news = "新闻"
    case newsURL = "网页新闻"
    case history = "历史"
    case realEvent = "真实事件"
    case information = "资讯"
    case observation = "生活观察"
    case document = "文档"
    case novelMarkdown = "小说 Markdown"
    case researchMarkdown = "资料 Markdown"
    case plainText = "TXT 资料"
    case referenceScreenplay = "参考剧本 Markdown"
    case classic = "经典研究"
    case freeIdea = "自由灵感"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .news, .newsURL: "newspaper"
        case .history: "clock.arrow.circlepath"
        case .realEvent: "person.2.wave.2"
        case .information: "doc.text.magnifyingglass"
        case .observation: "eye"
        case .document: "doc.richtext"
        case .novelMarkdown: "text.book.closed"
        case .researchMarkdown: "doc.text.magnifyingglass"
        case .plainText: "doc.plaintext"
        case .referenceScreenplay: "film.stack"
        case .classic: "theatermasks"
        case .freeIdea: "lightbulb"
        }
    }
}

enum WorkspaceSection: String, CaseIterable, Identifiable, Sendable {
    case home = "所有项目"
    case seeds = "现实变故事"
    case classics = "经典研究"
    case fragments = "灵感碎片"
    case knowledge = "知识库"
    case compiler = "叙事编译台"
    case overview = "项目全景"
    case ideas = "新想法"
    case templates = "结构选择"
    case journey = "大节拍选择"
    case characters = "人物"
    case relationships = "人物关系图"
    case world = "世界"
    case theme = "主题"
    case structure = "全本路线"
    case scenes = "场景工作台"
    case screenplay = "Final Draft 正文"
    case versions = "版本"
    case delivery = "检查与交付"

    var id: String { rawValue }

    static let discoverySections: [WorkspaceSection] = [
        .home, .seeds, .classics, .fragments, .knowledge
    ]

    static let projectSections: [WorkspaceSection] = [
        .compiler, .overview, .ideas, .templates, .journey, .characters, .relationships,
        .world, .theme, .structure, .scenes, .screenplay, .versions, .delivery
    ]

    var requiresProject: Bool {
        Self.projectSections.contains(self)
    }

    var systemImage: String {
        switch self {
        case .home: "square.grid.2x2.fill"
        case .seeds: "sparkles.rectangle.stack"
        case .classics: "theatermasks.fill"
        case .fragments: "heart.text.square.fill"
        case .knowledge: "books.vertical.fill"
        case .compiler: "function"
        case .overview: "square.grid.2x2"
        case .ideas: "lightbulb.max.fill"
        case .templates: "square.grid.3x3.topleft.filled"
        case .journey: "signpost.right.and.left.fill"
        case .characters: "person.2"
        case .relationships: "point.3.connected.trianglepath.dotted"
        case .world: "globe.asia.australia"
        case .theme: "scope"
        case .structure: "point.3.connected.trianglepath.dotted"
        case .scenes: "rectangle.stack"
        case .screenplay: "text.book.closed"
        case .versions: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .delivery: "checkmark.seal"
        }
    }

    var phaseLabel: String? {
        switch self {
        case .seeds: "AI"
        case .classics: "DNA"
        case .fragments: "MEMORY"
        case .knowledge: "LOCAL"
        case .compiler: "NSIR"
        case .templates: "RULES"
        case .journey: "CHOICE"
        case .screenplay: "BEATS"
        case .versions: "SNAPSHOT"
        case .delivery: "DELIVERY"
        case .relationships: "MAP"
        case .ideas: "IMPACT"
        case .home, .overview, .characters, .world, .theme, .structure, .scenes: nil
        }
    }
}

enum AnalysisKind: String, Codable {
    case character
    case story
    case antagonist
    case world
    case theme
    case structure
    case scene
    case screenplay
}

enum CreativeTaskStatus: String, Codable {
    case proposed
    case active
    case completed
    case skipped
}
