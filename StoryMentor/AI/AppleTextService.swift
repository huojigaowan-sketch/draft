import Foundation
import FoundationModels

struct AppleModelAvailability {
    let isAvailable: Bool
    let label: String
}

struct ApplePreparation {
    let text: String
    let note: String
}

@MainActor
enum AppleTextService {
    static var availability: AppleModelAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return AppleModelAvailability(isAvailable: true, label: "Apple 智能可用")
        case .unavailable(let reason):
            let detail: String
            switch reason {
            case .deviceNotEligible:
                detail = "设备不支持"
            case .appleIntelligenceNotEnabled:
                detail = "尚未启用 Apple 智能"
            case .modelNotReady:
                detail = "本地模型尚未就绪"
            @unknown default:
                detail = "暂不可用"
            }
            return AppleModelAvailability(isAvailable: false, label: detail)
        }
    }

    static func prepareForAnalysis(_ text: String, enabled: Bool) async -> ApplePreparation {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard enabled, cleaned.count > 1_200 else {
            return ApplePreparation(
                text: deterministicLimit(cleaned),
                note: enabled ? "材料较短，无需本地压缩" : "Apple 本地预处理已关闭"
            )
        }
        guard availability.isAvailable else {
            return ApplePreparation(
                text: deterministicLimit(cleaned),
                note: "Apple 智能不可用，已使用本地确定性截取"
            )
        }

        let session = LanguageModelSession(
            model: .default,
            instructions: """
            你是私人写作资料整理器。只压缩作者已经写出的事实，不评价、不续写、不添加设定。
            保留人物目标、需求、恐惧、秘密、关系、世界规则、主题命题、关键转折和所有不确定性。
            任何标注为“作者创意方向”“后来注入”“作者命令”“作者补充”或“硬约束”的内容
            都是不可丢失的创作指令，必须逐条保留原意，并与故事事实明确区分。
            输出紧凑的现代标准简体中文纯文本，禁止使用繁体中文，最多1800字。
            """
        )

        do {
            let response = try await session.respond(to: deterministicLimit(cleaned, limit: 8_000))
            let result = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .simplifiedChinese
            guard !result.isEmpty else {
                return ApplePreparation(text: deterministicLimit(cleaned), note: "本地模型未返回内容，使用截取")
            }
            return ApplePreparation(text: result, note: "已由 Apple Foundation Models 在本机压缩")
        } catch {
            return ApplePreparation(text: deterministicLimit(cleaned), note: "本地压缩失败，已安全回退")
        }
    }

    static func polish(_ text: String) async throws -> String {
        guard availability.isAvailable else {
            throw AppleTextError.unavailable(availability.label)
        }
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            throw AppleTextError.emptyInput
        }

        let session = LanguageModelSession(
            model: .default,
            instructions: """
            你是本地写作整理器。整理语序、去除重复、提高可读性，但绝不添加人物事实、
            情节、评价或写作建议。保留作者语气和所有含糊之处。只输出整理后的现代标准
            简体中文正文，禁止使用繁体中文。
            """
        )
        let response = try await session.respond(to: deterministicLimit(source, limit: 8_000))
        let result = response.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .simplifiedChinese
        guard !result.isEmpty else {
            throw AppleTextError.emptyResponse
        }
        return result
    }

    static func projectStoryBible(_ text: String) async -> String? {
        guard availability.isAvailable else { return nil }
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return nil }

        let session = LanguageModelSession(
            model: .default,
            instructions: """
            你是完全在本机运行的剧本圣经整理器。只依据作者已锁定的选择更新摘要，
            绝不续写剧情，绝不增加新人物、地点、关系或事实。冲突处以较新的锁定选择为准，
            但保留作者手写内容。输出必须恰好包含以下四个标题，每段最多220字：
            【人物小传】
            【世界规则】
            【主题命题】
            【核心冲突】
            没有足够依据的段落写“尚待后续选择确认”。所有中文使用现代标准简体中文，
            禁止使用繁体中文。
            """
        )

        do {
            let response = try await session.respond(to: deterministicLimit(source, limit: 9_000))
            let result = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .simplifiedChinese
            return result.isEmpty ? nil : result
        } catch {
            return nil
        }
    }

    private static func deterministicLimit(_ text: String, limit: Int = 4_800) -> String {
        guard text.count > limit else { return text }
        let headCount = Int(Double(limit) * 0.72)
        let tailCount = limit - headCount
        return String(text.prefix(headCount))
            + "\n\n[中间内容由本地预处理省略]\n\n"
            + String(text.suffix(tailCount))
    }
}

enum AppleTextError: LocalizedError {
    case unavailable(String)
    case emptyInput
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            "Apple 本地模型不可用：\(reason)"
        case .emptyInput:
            "没有可整理的文字。"
        case .emptyResponse:
            "Apple 本地模型没有返回内容。"
        }
    }
}
