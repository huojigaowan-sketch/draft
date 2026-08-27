import Foundation

nonisolated struct SiliconFlowModelCatalogClient: Sendable {
    nonisolated private struct ModelListResponse: Decodable {
        nonisolated struct Model: Decodable {
            let id: String
        }

        let data: [Model]
    }

    nonisolated private struct ErrorResponse: Decodable {
        nonisolated struct APIError: Decodable {
            let message: String?
        }

        let error: APIError?
        let message: String?
    }

    let configuration: AIConfiguration
    let session: URLSession

    init(configuration: AIConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func fetchChatModelIDs() async throws -> [String] {
        var request = URLRequest(url: configuration.modelsEndpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Bearer \(configuration.apiKey)",
            forHTTPHeaderField: "Authorization"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SiliconFlowCatalogError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SiliconFlowCatalogError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let envelope = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            let rawMessage = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message = envelope?.error?.message
                ?? envelope?.message
                ?? rawMessage
                ?? "HTTP \(httpResponse.statusCode)"
            throw SiliconFlowCatalogError.api(
                status: httpResponse.statusCode,
                message: message
            )
        }

        return try Self.decodeModelIDs(from: data)
    }

    static func decodeModelIDs(from data: Data) throws -> [String] {
        let decoded: ModelListResponse
        do {
            decoded = try JSONDecoder().decode(ModelListResponse.self, from: data)
        } catch {
            throw SiliconFlowCatalogError.decoding(error.localizedDescription)
        }

        let modelIDs = Set(
            decoded.data.compactMap { model -> String? in
                let id = model.id.trimmingCharacters(in: .whitespacesAndNewlines)
                return id.isEmpty ? nil : id
            }
        ).sorted()
        guard !modelIDs.isEmpty else {
            throw SiliconFlowCatalogError.emptyCatalog
        }
        return modelIDs
    }
}

nonisolated enum SiliconFlowCatalogError: LocalizedError {
    case network(String)
    case invalidResponse
    case api(status: Int, message: String)
    case decoding(String)
    case emptyCatalog

    var errorDescription: String? {
        switch self {
        case .network(let message):
            "无法连接硅基流动：\(message)"
        case .invalidResponse:
            "硅基流动返回了无法识别的响应。"
        case .api(let status, let message):
            if status == 401 {
                "API Key 无效或已失效，请重新保存后再试。"
            } else if status == 403 {
                "此 API Key 没有读取模型列表的权限：\(message)"
            } else {
                "获取硅基流动模型失败（HTTP \(status)）：\(message)"
            }
        case .decoding(let message):
            "无法解析硅基流动模型列表：\(message)"
        case .emptyCatalog:
            "硅基流动没有返回可用的对话模型。"
        }
    }
}
