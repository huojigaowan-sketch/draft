import Foundation
import FoundationModels
import CoreFoundation

/// DeepSeek 通过 macOS 27 的统一 LanguageModel 协议接入。
///
/// 上层只使用 `LanguageModelSession.respond(generating:)` 和 `@Generable`
/// 的 Swift 类型。HTTP 中的 JSON 只是供应商协议，不进入故事业务模型。
nonisolated struct DeepSeekLanguageModel: LanguageModel {
    let executorConfiguration: AIConfiguration

    var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities([.guidedGeneration, .reasoning])
    }

    typealias Executor = DeepSeekLanguageModelExecutor
}

nonisolated struct DeepSeekLanguageModelExecutor: LanguageModelExecutor {
    typealias Configuration = AIConfiguration
    typealias Model = DeepSeekLanguageModel

    private let configuration: AIConfiguration

    private let simplifiedChinesePolicy = """
    所有面向作者的中文自然语言内容必须使用现代标准简体中文。禁止使用繁体中文；
    即使输入资料包含繁体中文，也必须用简体中文输出。
    """

    init(configuration: AIConfiguration) throws {
        self.configuration = configuration
    }

    func prewarm(model: Model, transcript: Transcript) {}

    nonisolated(nonsending)
    func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: Model,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        let schemaText: String?
        if let schema = request.schema,
           let data = try? JSONEncoder().encode(schema) {
            schemaText = String(data: data, encoding: .utf8)
        } else {
            schemaText = nil
        }
        let messages = transcriptMessages(
            from: request.transcript,
            schemaText: schemaText
        )
        let completion = try await DeepSeekLanguageTransport(configuration: configuration)
            .complete(
                messages: messages,
                maximumResponseTokens: request.generationOptions.maximumResponseTokens ?? 4_096,
                temperature: request.generationOptions.temperature ?? 0.35,
                guidedSchema: schemaText
            )

        await channel.send(
            .response(
                action: .appendText(
                    completion.content,
                    tokenCount: completion.outputTokens
                )
            )
        )
        // macOS 27 beta 系统库与 Xcode 27 beta SDK 的 updateUsage 符号
        // 曾出现版本错位。文本响应是解析 @Generable 的唯一必要事件，
        // 因此暂不发送可选的供应商 token 统计，避免应用在旧 beta 上启动失败。
    }

    private func transcriptMessages(
        from transcript: Transcript,
        schemaText: String?
    ) -> [DeepSeekLanguageTransport.Message] {
        var messages: [DeepSeekLanguageTransport.Message] = []

        for entry in transcript {
            switch entry {
            case .instructions(let instructions):
                append(
                    role: "system",
                    segments: instructions.segments,
                    to: &messages
                )
            case .prompt(let prompt):
                append(role: "user", segments: prompt.segments, to: &messages)
            case .response(let response):
                append(role: "assistant", segments: response.segments, to: &messages)
            case .reasoning:
                continue
            case .toolCalls, .toolOutput:
                continue
            @unknown default:
                continue
            }
        }

        if let schemaText {
            let guide = """
            Output exactly one valid JSON object.
            The JSON object must conform to the JSON schema below.
            Return JSON only. Do not use Markdown or add any explanation.

            必须只返回一个合法的 JSON 对象，并严格服从下面的 Foundation Models
            生成模式。不要使用 Markdown，不要添加任何解释。

            JSON schema:
            \(schemaText)
            """
            if let systemIndex = messages.firstIndex(where: { $0.role == "system" }) {
                messages[systemIndex].content += "\n\n\(guide)"
            } else {
                messages.insert(.init(role: "system", content: guide), at: 0)
            }
        }

        if let systemIndex = messages.firstIndex(where: { $0.role == "system" }) {
            messages[systemIndex].content += "\n\n\(simplifiedChinesePolicy)"
        } else {
            messages.insert(.init(role: "system", content: simplifiedChinesePolicy), at: 0)
        }

        return messages
    }

    private func append(
        role: String,
        segments: [Transcript.Segment],
        to messages: inout [DeepSeekLanguageTransport.Message]
    ) {
        let content = segments.compactMap { segment -> String? in
            switch segment {
            case .text(let text):
                return text.content
            case .structure(let structure):
                return String(describing: structure.content)
            case .attachment:
                return "[当前执行器尚不传输附件]"
            @unknown default:
                return nil
            }
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !content.isEmpty else { return }
        if let last = messages.indices.last, messages[last].role == role {
            messages[last].content += "\n\n\(content)"
        } else {
            messages.append(.init(role: role, content: content))
        }
    }
}

nonisolated private struct DeepSeekLanguageTransport: Sendable {
    nonisolated struct Message: Codable, Sendable {
        let role: String
        var content: String
    }

    nonisolated struct Completion: Sendable {
        let content: String
        let inputTokens: Int
        let outputTokens: Int
        let reasoningTokens: Int
    }

    nonisolated private struct Payload: Encodable {
        nonisolated struct Thinking: Encodable { let type: String }
        nonisolated struct ResponseFormat: Encodable { let type: String }

        let model: String
        let messages: [Message]
        let thinking: Thinking?
        let maxTokens: Int
        let temperature: Double
        let responseFormat: ResponseFormat?
        let stream: Bool

        enum CodingKeys: String, CodingKey {
            case model, messages, thinking, temperature, stream
            case maxTokens = "max_tokens"
            case responseFormat = "response_format"
        }
    }

    nonisolated private struct Response: Decodable {
        nonisolated struct Choice: Decodable {
            nonisolated struct Message: Decodable {
                let content: String?
                let reasoningContent: String?

                enum CodingKeys: String, CodingKey {
                    case content
                    case reasoningContent = "reasoning_content"
                }
            }
            let message: Message
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case message
                case finishReason = "finish_reason"
            }
        }

        nonisolated struct Usage: Decodable {
            let promptTokens: Int?
            let completionTokens: Int?
            let reasoningTokens: Int?

            enum CodingKeys: String, CodingKey {
                case promptTokens = "prompt_tokens"
                case completionTokens = "completion_tokens"
                case reasoningTokens = "reasoning_tokens"
            }
        }

        let choices: [Choice]
        let usage: Usage?
    }

    nonisolated private struct ProviderCompletion {
        let content: String
        let finishReason: String?
        let inputTokens: Int
        let outputTokens: Int
        let reasoningTokens: Int
    }

    nonisolated private struct ErrorEnvelope: Decodable {
        nonisolated struct Body: Decodable { let message: String? }
        let error: Body?
    }

    let configuration: AIConfiguration

    func complete(
        messages: [Message],
        maximumResponseTokens: Int,
        temperature: Double,
        guidedSchema: String?
    ) async throws -> Completion {
        let first = try await requestCompletion(
            messages: messages,
            maximumResponseTokens: maximumResponseTokens,
            temperature: temperature,
            thinkingEnabled: configuration.thinkingEnabled,
            guided: guidedSchema != nil
        )

        guard let guidedSchema else {
            return completion(from: first)
        }

        let firstValidation = validatedGuidedContent(
            first.content,
            schemaText: guidedSchema
        )
        if first.finishReason != "length",
           case .success(let content) = firstValidation {
            return completion(from: first, content: content)
        }

        let failureReason: String
        if first.finishReason == "length" {
            failureReason = "上一次输出达到长度上限，JSON 没有完整结束。"
        } else if case .failure(let error) = firstValidation {
            failureReason = error.localizedDescription
        } else {
            failureReason = "上一次输出未满足结构化结果要求。"
        }

        var retryMessages = messages
        retryMessages.append(
            Message(
                role: "user",
                content: """
                上一次结构化输出不可用：\(failureReason)
                请从头重新生成同一任务。必须保留全部必填字段并严格服从 JSON schema。
                内容要具体但紧凑：每个普通字符串不超过 180 个汉字；只返回 JSON 对象。
                """
            )
        )
        let retry = try await requestCompletion(
            messages: retryMessages,
            maximumResponseTokens: min(
                8_192,
                max(4_096, maximumResponseTokens * 2)
            ),
            temperature: min(0.22, temperature),
            thinkingEnabled: false,
            guided: true
        )
        guard retry.finishReason != "length" else {
            throw DeepSeekError.outputTruncated
        }
        switch validatedGuidedContent(retry.content, schemaText: guidedSchema) {
        case .success(let content):
            return completion(from: retry, content: content)
        case .failure(let error):
            throw DeepSeekError.decoding(
                "自动重试后仍未满足强类型结构：\(error.localizedDescription)"
            )
        }
    }

    private func requestCompletion(
        messages: [Message],
        maximumResponseTokens: Int,
        temperature: Double,
        thinkingEnabled: Bool,
        guided: Bool
    ) async throws -> ProviderCompletion {
        let endpoint = configuration.chatCompletionsEndpoint
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            Payload(
                model: configuration.model,
                messages: messages,
                thinking: configuration.provider.supportsDeepSeekThinking
                    ? .init(type: thinkingEnabled ? "enabled" : "disabled")
                    : nil,
                maxTokens: maximumResponseTokens,
                temperature: temperature,
                responseFormat: guided ? .init(type: "json_object") : nil,
                stream: false
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw DeepSeekError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            let message = envelope?.error?.message
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(http.statusCode)"
            throw DeepSeekError.api(status: http.statusCode, message: message)
        }

        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw DeepSeekError.decoding(error.localizedDescription)
        }
        guard let choice = decoded.choices.first else {
            throw DeepSeekError.invalidResponse
        }
        let content = choice.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty || choice.finishReason == "length" else {
            throw DeepSeekError.emptyContent
        }
        return ProviderCompletion(
            content: content.simplifiedChinese,
            finishReason: choice.finishReason,
            inputTokens: decoded.usage?.promptTokens ?? 0,
            outputTokens: decoded.usage?.completionTokens ?? 0,
            reasoningTokens: decoded.usage?.reasoningTokens ?? 0
        )
    }

    private func completion(
        from provider: ProviderCompletion,
        content: String? = nil
    ) -> Completion {
        Completion(
            content: content ?? provider.content,
            inputTokens: provider.inputTokens,
            outputTokens: provider.outputTokens,
            reasoningTokens: provider.reasoningTokens
        )
    }

    private func validatedGuidedContent(
        _ content: String,
        schemaText: String
    ) -> Result<String, GuidedOutputError> {
        do {
            let jsonText = extractJSONObject(from: content)
            guard let contentData = jsonText.data(using: .utf8),
                  let schemaData = schemaText.data(using: .utf8) else {
                throw GuidedOutputError.invalidJSON
            }
            let object = try JSONSerialization.jsonObject(with: contentData)
            let schemaObject = try JSONSerialization.jsonObject(with: schemaData)
            guard let root = object as? [String: Any],
                  let schema = schemaObject as? [String: Any] else {
                throw GuidedOutputError.rootMustBeObject
            }
            if let violation = JSONSchemaContract.firstViolation(
                value: root,
                schema: schema,
                rootSchema: schema,
                path: "$"
            ) {
                throw GuidedOutputError.schema(violation)
            }
            let canonicalData = try JSONSerialization.data(
                withJSONObject: root,
                options: [.sortedKeys]
            )
            guard let canonical = String(data: canonicalData, encoding: .utf8) else {
                throw GuidedOutputError.invalidJSON
            }
            _ = try GeneratedContent(json: canonical)
            return .success(canonical)
        } catch let error as GuidedOutputError {
            return .failure(error)
        } catch {
            return .failure(.schema(error.localizedDescription))
        }
    }

    private func extractJSONObject(from text: String) -> String {
        var start: String.Index?
        var depth = 0
        var insideString = false
        var escaped = false

        for index in text.indices {
            let character = text[index]
            if insideString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    insideString = false
                }
                continue
            }
            if character == "\"" {
                insideString = true
            } else if character == "{" {
                if start == nil { start = index }
                depth += 1
            } else if character == "}", start != nil {
                depth -= 1
                if depth == 0, let start {
                    return String(text[start...index])
                }
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated private enum GuidedOutputError: LocalizedError {
    case invalidJSON
    case rootMustBeObject
    case schema(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            "供应商没有返回完整的 JSON。"
        case .rootMustBeObject:
            "供应商返回的根内容不是 JSON 对象。"
        case .schema(let message):
            "供应商结果不符合 Swift 类型：\(message)"
        }
    }
}

nonisolated private enum JSONSchemaContract {
    static func firstViolation(
        value: Any,
        schema: [String: Any],
        rootSchema: [String: Any],
        path: String
    ) -> String? {
        if let reference = schema["$ref"] as? String {
            guard let target = resolve(reference, in: rootSchema) else {
                return "\(path) 使用了无法解析的 schema 引用 \(reference)"
            }
            return firstViolation(
                value: value,
                schema: target,
                rootSchema: rootSchema,
                path: path
            )
        }

        if let anyOf = schema["anyOf"] as? [[String: Any]],
           !anyOf.contains(where: {
               firstViolation(
                   value: value,
                   schema: $0,
                   rootSchema: rootSchema,
                   path: path
               ) == nil
           }) {
            return "\(path) 不符合任何允许的类型"
        }

        if let allowed = schema["enum"] as? [Any],
           !allowed.contains(where: { jsonValuesEqual($0, value) }) {
            return "\(path) 不是允许的枚举值"
        }

        guard let type = schema["type"] as? String else { return nil }
        switch type {
        case "object":
            guard let object = value as? [String: Any] else {
                return "\(path) 应为对象"
            }
            let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
            let required = schema["required"] as? [String] ?? []
            for key in required where object[key] == nil {
                return "\(path).\(key) 缺失"
            }
            if schema["additionalProperties"] as? Bool == false,
               let unexpected = object.keys.first(where: { properties[$0] == nil }) {
                return "\(path).\(unexpected) 不是允许的字段"
            }
            for key in object.keys.sorted() {
                guard let propertySchema = properties[key],
                      let propertyValue = object[key] else { continue }
                if let violation = firstViolation(
                    value: propertyValue,
                    schema: propertySchema,
                    rootSchema: rootSchema,
                    path: "\(path).\(key)"
                ) {
                    return violation
                }
            }
        case "array":
            guard let array = value as? [Any] else {
                return "\(path) 应为数组"
            }
            if let minimum = schema["minItems"] as? NSNumber,
               array.count < minimum.intValue {
                return "\(path) 至少需要 \(minimum.intValue) 项"
            }
            if let maximum = schema["maxItems"] as? NSNumber,
               array.count > maximum.intValue {
                return "\(path) 最多允许 \(maximum.intValue) 项"
            }
            if let itemSchema = schema["items"] as? [String: Any] {
                for (index, item) in array.enumerated() {
                    if let violation = firstViolation(
                        value: item,
                        schema: itemSchema,
                        rootSchema: rootSchema,
                        path: "\(path)[\(index)]"
                    ) {
                        return violation
                    }
                }
            }
        case "string":
            guard let string = value as? String else {
                return "\(path) 应为字符串"
            }
            if let minimum = schema["minLength"] as? NSNumber,
               string.count < minimum.intValue {
                return "\(path) 字符数少于 \(minimum.intValue)"
            }
            if let maximum = schema["maxLength"] as? NSNumber,
               string.count > maximum.intValue {
                return "\(path) 字符数超过 \(maximum.intValue)"
            }
        case "integer":
            guard let number = value as? NSNumber,
                  !isBoolean(number),
                  number.doubleValue.rounded(.towardZero) == number.doubleValue else {
                return "\(path) 应为整数"
            }
        case "number":
            guard let number = value as? NSNumber, !isBoolean(number) else {
                return "\(path) 应为数字"
            }
        case "boolean":
            guard let number = value as? NSNumber, isBoolean(number) else {
                return "\(path) 应为布尔值"
            }
        case "null":
            guard value is NSNull else { return "\(path) 应为空值" }
        default:
            break
        }
        return nil
    }

    private static func resolve(
        _ reference: String,
        in rootSchema: [String: Any]
    ) -> [String: Any]? {
        guard reference.hasPrefix("#/") else { return nil }
        var current: Any = rootSchema
        for component in reference.dropFirst(2).split(separator: "/") {
            let key = component
                .replacingOccurrences(of: "~1", with: "/")
                .replacingOccurrences(of: "~0", with: "~")
            guard let object = current as? [String: Any],
                  let next = object[key] else { return nil }
            current = next
        }
        return current as? [String: Any]
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func jsonValuesEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        guard JSONSerialization.isValidJSONObject([lhs]),
              JSONSerialization.isValidJSONObject([rhs]),
              let leftData = try? JSONSerialization.data(withJSONObject: [lhs]),
              let rightData = try? JSONSerialization.data(withJSONObject: [rhs]) else {
            return false
        }
        return leftData == rightData
    }
}

enum StoryLanguageRuntime {
    static func session(
        configuration: AIConfiguration,
        instructions: String
    ) -> LanguageModelSession {
        LanguageModelSession(
            model: DeepSeekLanguageModel(executorConfiguration: configuration),
            instructions: instructions
        )
    }
}
