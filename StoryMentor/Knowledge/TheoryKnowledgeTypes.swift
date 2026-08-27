import Foundation

enum TheoryTopic: String, CaseIterable, Sendable {
    case character
    case desire
    case flaw
    case arc
    case relationship
    case antagonism
    case theme
    case world
    case structure
    case sequence
    case scene
    case dialogue
    case exposition
    case genre
    case revision
    case visual
    case adaptation
    case comedy
    case psychology
    case craft

    nonisolated var displayName: String {
        switch self {
        case .character: "人物设计"
        case .desire: "欲望与需求"
        case .flaw: "缺陷与信念"
        case .arc: "人物弧线"
        case .relationship: "人物关系"
        case .antagonism: "对抗力量"
        case .theme: "主题与价值"
        case .world: "世界与设定"
        case .structure: "故事结构"
        case .sequence: "段落与节拍"
        case .scene: "场景设计"
        case .dialogue: "对白"
        case .exposition: "信息与悬念"
        case .genre: "类型"
        case .revision: "重写"
        case .visual: "视觉叙事"
        case .adaptation: "改编"
        case .comedy: "喜剧"
        case .psychology: "人物心理"
        case .craft: "写作方法"
        }
    }

    nonisolated var keywords: [String] {
        switch self {
        case .character: ["character", "protagonist", "hero", "role", "cast", "characterization"]
        case .desire: ["desire", "want", "goal", "need", "motivation", "objective"]
        case .flaw: ["flaw", "weakness", "belief", "self-deception", "moral", "blindness"]
        case .arc: ["arc", "change", "transformation", "growth", "evolve"]
        case .relationship: ["relationship", "love", "family", "friend", "ally", "partner"]
        case .antagonism: ["antagonist", "antagonism", "opponent", "conflict", "enemy", "obstacle"]
        case .theme: ["theme", "meaning", "value", "premise", "moral", "argument"]
        case .world: ["world", "setting", "society", "environment", "rule", "culture"]
        case .structure: ["structure", "act", "plot", "inciting", "climax", "crisis", "resolution"]
        case .sequence: ["sequence", "beat", "turning point", "progression", "midpoint"]
        case .scene: ["scene", "beat", "moment", "entrance", "exit"]
        case .dialogue: ["dialogue", "speech", "subtext", "talk", "conversation", "verbal"]
        case .exposition: ["exposition", "information", "reveal", "mystery", "suspense"]
        case .genre: ["genre", "thriller", "comedy", "romance", "crime", "action", "horror"]
        case .revision: ["rewrite", "revision", "draft", "editing", "diagnosis"]
        case .visual: ["visual", "image", "picture", "camera", "space", "composition"]
        case .adaptation: ["adaptation", "adapt", "source material", "novel"]
        case .comedy: ["comedy", "comic", "funny", "humor", "joke"]
        case .psychology: ["psychology", "trauma", "emotion", "mind", "behavior", "fear"]
        case .craft: ["screenplay", "screenwriting", "story", "writer", "writing", "dramatic"]
        }
    }
}

struct TheoryDocumentInput: Sendable {
    let title: String
    let sourceFilename: String
    let sourceFingerprint: String
    let sourceType: String
    let characterCount: Int
    let sectionCount: Int
    let topicSummary: String
    let chunks: [TheoryChunkInput]
}

struct TheoryChunkInput: Sendable {
    let sequence: Int
    let headingPath: String
    let topics: [TheoryTopic]
    let content: String

    nonisolated var topicTokens: String {
        topics.map(\.rawValue).joined(separator: " ")
    }

    nonisolated var displayTopics: String {
        topics.map(\.displayName).joined(separator: " · ")
    }
}

struct TheoryEvidence: Sendable, Identifiable {
    let id: String
    let documentID: String
    let title: String
    let headingPath: String
    let topics: String
    let content: String
    let score: Double
    let estimatedTokens: Int

    nonisolated var sourceLabel: String {
        "\(title) > \(headingPath)"
    }

    nonisolated var promptBlock: String {
        "【理论证据：\(sourceLabel)｜\(topics)】\n\(content)"
    }
}

struct TheoryRetrievalRoute: Sendable {
    let section: WorkspaceSection
    let topics: [TheoryTopic]
    let focus: String

    nonisolated var ftsTerms: [String] {
        Array(Set(topics.map(\.rawValue) + [TheoryTopic.craft.rawValue]))
    }
}

enum TheoryRouting {
    nonisolated static func route(for section: WorkspaceSection) -> TheoryRetrievalRoute {
        switch section {
        case .home, .seeds, .classics, .fragments:
            TheoryRetrievalRoute(
                section: section,
                topics: [.structure, .character, .desire, .antagonism, .theme, .genre],
                focus: "素材戏剧化：从现实事实中辨认欲望、阻碍、代价、关系压力、价值冲突和可持续升级的故事问题。"
            )
        case .journey:
            TheoryRetrievalRoute(
                section: section,
                topics: [.structure, .character, .desire, .antagonism, .relationship, .scene, .theme],
                focus: "互动故事推进：每次只解决一个高杠杆选择，让选择产生具体代价、关系变化和下一层因果压力。"
            )
        case .templates:
            TheoryRetrievalRoute(
                section: section,
                topics: [.structure, .sequence, .character, .genre, .theme],
                focus: "结构模板选择：比较不同结构如何控制观众期待、转折密度、人物变化和叙事风险，并根据素材选择合适的创作规则。"
            )
        case .compiler, .overview, .ideas:
            TheoryRetrievalRoute(
                section: section,
                topics: [.structure, .character, .desire, .antagonism, .theme, .genre],
                focus: "故事整体诊断：检查欲望、对抗、因果升级、价值选择、人物变化与类型承诺是否连成同一台叙事发动机。"
            )
        case .characters, .relationships:
            TheoryRetrievalRoute(
                section: section,
                topics: [.character, .desire, .flaw, .arc, .relationship, .antagonism, .psychology],
                focus: "人物诊断：检查外部目标与内在需求的错位、恐惧或错误信念、选择代价、关系压力、反派功能与可见的弧线。"
            )
        case .world:
            TheoryRetrievalRoute(
                section: section,
                topics: [.world, .genre, .theme, .visual, .antagonism],
                focus: "世界诊断：检查规则是否限制选择、资源是否稀缺、权力如何运作，以及设定是否持续制造冲突而非仅作装饰。"
            )
        case .theme:
            TheoryRetrievalRoute(
                section: section,
                topics: [.theme, .character, .antagonism, .structure],
                focus: "主题诊断：把关键词转换成可被人物行动检验的价值命题，并让主角与对抗力量给出相反答案。"
            )
        case .structure:
            TheoryRetrievalRoute(
                section: section,
                topics: [.structure, .sequence, .scene, .antagonism, .genre],
                focus: "结构诊断：检查引发事件、不可逆选择、中点改写、危机、高潮和结局之间的因果升级，而不是机械套模板。"
            )
        case .scenes:
            TheoryRetrievalRoute(
                section: section,
                topics: [.scene, .sequence, .dialogue, .exposition, .visual],
                focus: "场景诊断：检查每场戏的即时目标、阻力、策略变化、信息控制、情绪转折和离场后的局面变化。"
            )
        case .screenplay, .versions, .delivery:
            TheoryRetrievalRoute(
                section: section,
                topics: [.scene, .dialogue, .visual, .exposition, .revision],
                focus: "剧本正文诊断：检查可拍性、动作与对白的分工、潜台词、视觉信息、节奏与重写优先级。"
            )
        case .knowledge:
            TheoryRetrievalRoute(section: section, topics: [.craft], focus: "知识库管理")
        }
    }
}

enum TheoryTopicClassifier {
    nonisolated static func classify(title: String, headingPath: String, content: String) -> [TheoryTopic] {
        let sample = "\(title) \(headingPath) \(content.prefix(2_200))".lowercased()
        let scored = TheoryTopic.allCases.map { topic in
            let score = topic.keywords.reduce(into: 0) { partial, keyword in
                if sample.contains(keyword) {
                    partial += keyword.contains(" ") ? 3 : 1
                }
            }
            return (topic, score)
        }
        let selected = scored
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                lhs.1 == rhs.1 ? lhs.0.rawValue < rhs.0.rawValue : lhs.1 > rhs.1
            }
            .prefix(4)
            .map(\.0)
        return selected.isEmpty ? [.craft] : selected
    }
}
