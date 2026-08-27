import Foundation
import Observation

nonisolated enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case deepSeek
    case siliconFlow

    var id: Self { self }

    var displayName: String {
        switch self {
        case .deepSeek:
            "DeepSeek"
        case .siliconFlow:
            "硅基流动"
        }
    }

    var supportsDeepSeekThinking: Bool {
        self == .deepSeek
    }
}

@Observable
@MainActor
final class AISettingsStore {
    private enum DefaultsKey {
        static let provider = "ai.provider"
        static let model = "ai.deepseek.model"
        static let baseURL = "ai.deepseek.baseURL"
        static let thinking = "ai.deepseek.thinking"
        static let siliconFlowModel = "ai.siliconFlow.model"
        static let siliconFlowBaseURL = "ai.siliconFlow.baseURL"
        static let legacyOpenAICompatibleModel = "ai.openAICompatible.model"
        static let legacyOpenAICompatibleBaseURL = "ai.openAICompatible.baseURL"
        static let siliconFlowLegacyCredentialMigrated =
            "ai.siliconFlow.legacyCredentialMigrated"
        static let applePreprocessing = "ai.apple.preprocessing"
        static let knowledgeBase = "ai.knowledge.enabled"
        static let automaticDramaticAnalysis = "ai.dramaticUpdates.automatic"
    }

    private(set) var apiKey: String
    private(set) var siliconFlowAPIKey: String

    var provider: AIProvider {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: DefaultsKey.provider) }
    }

    var model: String {
        didSet { UserDefaults.standard.set(model, forKey: DefaultsKey.model) }
    }

    var baseURLString: String {
        didSet { UserDefaults.standard.set(baseURLString, forKey: DefaultsKey.baseURL) }
    }

    var siliconFlowModel: String {
        didSet {
            UserDefaults.standard.set(
                siliconFlowModel,
                forKey: DefaultsKey.siliconFlowModel
            )
        }
    }

    var siliconFlowBaseURLString: String {
        didSet {
            UserDefaults.standard.set(
                siliconFlowBaseURLString,
                forKey: DefaultsKey.siliconFlowBaseURL
            )
        }
    }

    var thinkingEnabled: Bool {
        didSet { UserDefaults.standard.set(thinkingEnabled, forKey: DefaultsKey.thinking) }
    }

    var useApplePreprocessing: Bool {
        didSet { UserDefaults.standard.set(useApplePreprocessing, forKey: DefaultsKey.applePreprocessing) }
    }

    var useKnowledgeBase: Bool {
        didSet { UserDefaults.standard.set(useKnowledgeBase, forKey: DefaultsKey.knowledgeBase) }
    }

    /// Off by default to prevent typing pauses from silently consuming cloud
    /// tokens. The semantic layer still invalidates immediately and remains
    /// available through the screenplay's 情境透镜.
    var automaticallyAnalyzeDramaticUpdates: Bool {
        didSet {
            UserDefaults.standard.set(
                automaticallyAnalyzeDramaticUpdates,
                forKey: DefaultsKey.automaticDramaticAnalysis
            )
        }
    }

    var hasAPIKey: Bool {
        let activeKey = provider == .deepSeek ? apiKey : siliconFlowAPIKey
        return !activeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasSiliconFlowAPIKey: Bool {
        !siliconFlowAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasSelectedModel: Bool {
        let activeModel = provider == .deepSeek ? model : siliconFlowModel
        return !activeModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {
        let defaults = UserDefaults.standard
        let legacyBaseURL = defaults.string(
            forKey: DefaultsKey.legacyOpenAICompatibleBaseURL
        )
        let legacyWasSiliconFlow = Self.isSiliconFlowURL(legacyBaseURL)
        let storedProvider = defaults.string(forKey: DefaultsKey.provider)
        let resolvedProvider: AIProvider
        if let provider = storedProvider.flatMap(AIProvider.init(rawValue:)) {
            resolvedProvider = provider
        } else if storedProvider == "openAICompatible", legacyWasSiliconFlow {
            resolvedProvider = .siliconFlow
        } else {
            resolvedProvider = .deepSeek
        }

        // Accessing an encrypted keychain item can wait on the security daemon.
        // Never put that round-trip on SwiftUI's launch path: the workbench can
        // render immediately, then DeepSeek becomes available as soon as the
        // existing credential is read.
        apiKey = ""
        siliconFlowAPIKey = ""
        provider = resolvedProvider
        model = defaults.string(forKey: DefaultsKey.model) ?? "deepseek-v4-pro"
        baseURLString = defaults.string(forKey: DefaultsKey.baseURL) ?? "https://api.deepseek.com"

        let canMigrateLegacySiliconFlow = defaults.string(
            forKey: DefaultsKey.siliconFlowBaseURL
        ) == nil && legacyWasSiliconFlow
        siliconFlowBaseURLString = defaults.string(forKey: DefaultsKey.siliconFlowBaseURL)
            ?? (canMigrateLegacySiliconFlow ? legacyBaseURL : nil)
            ?? "https://api.siliconflow.cn/v1"
        siliconFlowModel = defaults.string(forKey: DefaultsKey.siliconFlowModel)
            ?? (canMigrateLegacySiliconFlow
                ? defaults.string(forKey: DefaultsKey.legacyOpenAICompatibleModel)
                : nil)
            ?? ""
        thinkingEnabled = defaults.object(forKey: DefaultsKey.thinking) as? Bool ?? true
        useApplePreprocessing = defaults.object(forKey: DefaultsKey.applePreprocessing) as? Bool ?? false
        useKnowledgeBase = defaults.object(forKey: DefaultsKey.knowledgeBase) as? Bool ?? true
        automaticallyAnalyzeDramaticUpdates = defaults.object(
            forKey: DefaultsKey.automaticDramaticAnalysis
        ) as? Bool ?? false

        // Persist the new namespace immediately so removing a migrated key does
        // not cause the legacy generic credential to reappear next launch.
        defaults.set(siliconFlowBaseURLString, forKey: DefaultsKey.siliconFlowBaseURL)
        defaults.set(siliconFlowModel, forKey: DefaultsKey.siliconFlowModel)
        defaults.set(provider.rawValue, forKey: DefaultsKey.provider)

        Task { [weak self] in
            let shouldMigrateLegacyCredential = legacyWasSiliconFlow
                && !defaults.bool(forKey: DefaultsKey.siliconFlowLegacyCredentialMigrated)
            let storedKeys = await Task.detached(priority: .userInitiated) {
                let deepSeekKey = try? KeychainService.readAPIKey()
                var siliconFlowKey = try? KeychainService.readSiliconFlowAPIKey()
                var didMigrateLegacyCredential = shouldMigrateLegacyCredential
                    && siliconFlowKey != nil
                if siliconFlowKey == nil, shouldMigrateLegacyCredential,
                   let legacyKey = try? KeychainService.readLegacyOpenAICompatibleAPIKey() {
                    do {
                        try KeychainService.saveSiliconFlowAPIKey(legacyKey)
                        siliconFlowKey = legacyKey
                        didMigrateLegacyCredential = true
                    } catch {
                        // Leave the marker unset so a temporary Keychain error
                        // can be retried on the next launch.
                    }
                }
                return (deepSeekKey, siliconFlowKey, didMigrateLegacyCredential)
            }.value
            if storedKeys.2 {
                defaults.set(
                    true,
                    forKey: DefaultsKey.siliconFlowLegacyCredentialMigrated
                )
            }
            self?.apiKey = storedKeys.0 ?? ""
            self?.siliconFlowAPIKey = storedKeys.1 ?? ""
        }
    }

    func saveAPIKey(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIConfigurationError.missingAPIKey(.deepSeek)
        }
        try KeychainService.saveAPIKey(trimmed)
        apiKey = trimmed
    }

    func saveSiliconFlowAPIKey(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIConfigurationError.missingAPIKey(.siliconFlow)
        }
        try KeychainService.saveSiliconFlowAPIKey(trimmed)
        UserDefaults.standard.set(
            true,
            forKey: DefaultsKey.siliconFlowLegacyCredentialMigrated
        )
        siliconFlowAPIKey = trimmed
    }

    func removeAPIKey() throws {
        try KeychainService.deleteAPIKey()
        apiKey = ""
    }

    func removeSiliconFlowAPIKey() throws {
        try KeychainService.deleteSiliconFlowAPIKey()
        UserDefaults.standard.set(
            true,
            forKey: DefaultsKey.siliconFlowLegacyCredentialMigrated
        )
        siliconFlowAPIKey = ""
    }

    func configuration() throws -> AIConfiguration {
        let activeAPIKey = provider == .deepSeek ? apiKey : siliconFlowAPIKey
        let activeBaseURLString = provider == .deepSeek
            ? baseURLString
            : siliconFlowBaseURLString
        let activeModel = provider == .deepSeek ? model : siliconFlowModel

        guard !activeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIConfigurationError.missingAPIKey(provider)
        }
        let trimmedBaseURL = activeBaseURLString.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard let baseURL = URL(string: trimmedBaseURL),
              let scheme = baseURL.scheme,
              ["https", "http"].contains(scheme.lowercased()),
              baseURL.host != nil else {
            throw AIConfigurationError.invalidBaseURL(provider)
        }
        let trimmedModel = activeModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            throw AIConfigurationError.missingModelID(provider)
        }
        return AIConfiguration(
            apiKey: activeAPIKey,
            baseURL: baseURL,
            model: trimmedModel,
            thinkingEnabled: provider == .deepSeek && thinkingEnabled,
            provider: provider
        )
    }

    func siliconFlowCatalogConfiguration() throws -> AIConfiguration {
        let key = siliconFlowAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw AIConfigurationError.missingAPIKey(.siliconFlow)
        }
        let rawURL = siliconFlowBaseURLString.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard let baseURL = URL(string: rawURL),
              let scheme = baseURL.scheme,
              ["https", "http"].contains(scheme.lowercased()),
              baseURL.host != nil else {
            throw AIConfigurationError.invalidBaseURL(.siliconFlow)
        }
        return AIConfiguration(
            apiKey: key,
            baseURL: baseURL,
            model: siliconFlowModel,
            thinkingEnabled: false,
            provider: .siliconFlow
        )
    }

    private static func isSiliconFlowURL(_ rawValue: String?) -> Bool {
        guard let rawValue,
              let host = URL(string: rawValue)?.host?.lowercased() else {
            return false
        }
        return host == "api.siliconflow.cn" || host.hasSuffix(".siliconflow.cn")
    }
}

nonisolated struct AIConfiguration: Hashable, Sendable {
    let apiKey: String
    let baseURL: URL
    let model: String
    let thinkingEnabled: Bool
    let provider: AIProvider

    init(
        apiKey: String,
        baseURL: URL,
        model: String,
        thinkingEnabled: Bool,
        provider: AIProvider = .deepSeek
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.thinkingEnabled = thinkingEnabled
        self.provider = provider
    }

    var chatCompletionsEndpoint: URL {
        endpoint(appending: ["chat", "completions"])
    }

    var modelsEndpoint: URL {
        endpoint(
            appending: ["models"],
            queryItems: [URLQueryItem(name: "sub_type", value: "chat")]
        )
    }

    func withThinkingEnabled(_ enabled: Bool) -> AIConfiguration {
        AIConfiguration(
            apiKey: apiKey,
            baseURL: baseURL,
            model: model,
            thinkingEnabled: enabled,
            provider: provider
        )
    }

    private func endpoint(
        appending endpointPath: [String],
        queryItems: [URLQueryItem] = []
    ) -> URL {
        guard var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        ) else {
            return endpointPath.reduce(baseURL) { url, component in
                url.appending(path: component)
            }
        }

        var pathComponents = components.path
            .split(separator: "/")
            .map(String.init)
        if pathComponents.count >= 2,
           pathComponents.suffix(2).map({ $0.lowercased() }) == ["chat", "completions"] {
            pathComponents.removeLast(2)
        }
        pathComponents.append(contentsOf: endpointPath)
        components.path = "/" + pathComponents.joined(separator: "/")
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        components.fragment = nil
        return components.url ?? baseURL
    }
}

enum AIConfigurationError: LocalizedError {
    case missingAPIKey(AIProvider)
    case invalidBaseURL(AIProvider)
    case missingModelID(AIProvider)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            "请先在设置中保存\(provider.displayName) API Key。"
        case .invalidBaseURL(let provider):
            "\(provider.displayName) API 地址无效。"
        case .missingModelID(let provider):
            "请先选择或填写\(provider.displayName)模型 ID。"
        }
    }
}
