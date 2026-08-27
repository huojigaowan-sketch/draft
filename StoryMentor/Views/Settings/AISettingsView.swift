import SwiftUI

struct AISettingsView: View {
    @Environment(AISettingsStore.self) private var settings
    @State private var draftAPIKey = ""
    @State private var draftSiliconFlowAPIKey = ""
    @State private var siliconFlowModelIDs: [String] = []
    @State private var isLoadingSiliconFlowModels = false
    @State private var isManualModelEntryExpanded = false
    @State private var siliconFlowModelRequestID = UUID()
    @State private var modelCatalogMessage = ""
    @State private var statusMessage = ""
    @State private var isTesting = false
    @State private var errorMessage = ""
    @State private var showingError = false
    @FocusState private var apiKeyFocused: Bool
    @FocusState private var siliconFlowAPIKeyFocused: Bool

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    EyebrowLabel(text: "AI & Privacy")
                    Text("模型与隐私")
                        .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    Text("可选择 DeepSeek 或硅基流动；Apple Foundation Models 只在本机整理长文本。")
                        .foregroundStyle(.secondary)
                }

                StudioCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("当前模型接口", systemImage: "point.3.connected.trianglepath.dotted")
                            .font(.headline)

                        Picker("接口", selection: $settings.provider) {
                            ForEach(AIProvider.allCases) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(settings.provider == .deepSeek
                            ? "继续使用原有 DeepSeek 配置。"
                            : "使用硅基流动官方接口，并通过 API Key 自动获取可用对话模型。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if settings.provider == .deepSeek {
                    StudioCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("DeepSeek API", systemImage: "key.fill")
                                .font(.headline)

                            SecureField("粘贴 API Key", text: $draftAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .focused($apiKeyFocused)
                                .onSubmit {
                                    saveDeepSeekKey()
                                }

                            HStack {
                                if settings.hasAPIKey {
                                    Label("已安全保存在钥匙串", systemImage: "checkmark.shield.fill")
                                        .font(.caption)
                                        .foregroundStyle(StudioTheme.mint)
                                } else {
                                    Text("Key 不会写入项目文件或 UserDefaults。")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if settings.hasAPIKey {
                                    Button("移除", role: .destructive) {
                                        removeDeepSeekKey()
                                    }
                                }
                                Button("保存 Key") {
                                    saveDeepSeekKey()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    StudioCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("诊断模型", systemImage: "brain.head.profile")
                                .font(.headline)

                            Picker("模型", selection: $settings.model) {
                                Text("DeepSeek V4 Pro · 深度诊断").tag("deepseek-v4-pro")
                                Text("DeepSeek V4 Flash · 快速省费").tag("deepseek-v4-flash")
                            }
                            .pickerStyle(.radioGroup)

                            Toggle("启用深度推理", isOn: $settings.thinkingEnabled)
                            Text("关闭后响应更快、输出 token 通常更少；复杂人物和结构诊断建议开启。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    StudioCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("硅基流动 API", systemImage: "key.fill")
                                .font(.headline)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("API 地址")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                HStack {
                                    TextField(
                                        "https://api.siliconflow.cn/v1",
                                        text: $settings.siliconFlowBaseURLString
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit {
                                        refreshSiliconFlowModels()
                                    }

                                    Button("恢复默认") {
                                        settings.siliconFlowBaseURLString =
                                            "https://api.siliconflow.cn/v1"
                                        refreshSiliconFlowModels()
                                    }
                                }
                                Text("官方 Base URL；聊天请求会自动使用 /chat/completions。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            SecureField(
                                settings.hasSiliconFlowAPIKey
                                    ? "输入新 API Key 以替换已保存的 Key"
                                    : "粘贴硅基流动 API Key",
                                text: $draftSiliconFlowAPIKey
                            )
                                .textFieldStyle(.roundedBorder)
                                .focused($siliconFlowAPIKeyFocused)
                                .onSubmit {
                                    saveSiliconFlowKey()
                                }

                            HStack {
                                if settings.hasSiliconFlowAPIKey {
                                    Label("已安全保存在钥匙串", systemImage: "checkmark.shield.fill")
                                        .font(.caption)
                                        .foregroundStyle(StudioTheme.mint)
                                } else {
                                    Text("API Key 只保存在本机钥匙串，不会写入项目文件。")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if settings.hasSiliconFlowAPIKey {
                                    Button("移除", role: .destructive) {
                                        removeSiliconFlowKey()
                                    }
                                }
                                Button("保存 Key") {
                                    saveSiliconFlowKey()
                                }
                                .buttonStyle(.borderedProminent)
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Label("对话模型", systemImage: "cpu")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Button {
                                        refreshSiliconFlowModels()
                                    } label: {
                                        if isLoadingSiliconFlowModels {
                                            ProgressView()
                                                .controlSize(.small)
                                        } else {
                                            Label("刷新模型", systemImage: "arrow.clockwise")
                                        }
                                    }
                                    .disabled(
                                        !settings.hasSiliconFlowAPIKey
                                            || isLoadingSiliconFlowModels
                                    )
                                }

                                if !siliconFlowModelIDs.isEmpty {
                                    Picker("模型 ID", selection: $settings.siliconFlowModel) {
                                        ForEach(modelPickerIDs, id: \.self) { modelID in
                                            Text(modelID).tag(modelID)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                } else if isLoadingSiliconFlowModels {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("正在读取可用模型 ID…")
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text(settings.hasSiliconFlowAPIKey
                                        ? "点击“刷新模型”从硅基流动读取可用模型。"
                                        : "保存 API Key 后会自动获取可用对话模型。")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Button {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        isManualModelEntryExpanded.toggle()
                                    }
                                } label: {
                                    Label(
                                        "手动填写模型 ID",
                                        systemImage: isManualModelEntryExpanded
                                            ? "chevron.down"
                                            : "chevron.right"
                                    )
                                    .font(.subheadline.weight(.semibold))
                                }
                                .buttonStyle(.plain)

                                if isManualModelEntryExpanded {
                                    TextField(
                                        "例如 deepseek-ai/DeepSeek-V3.2",
                                        text: $settings.siliconFlowModel
                                    )
                                    .textFieldStyle(.roundedBorder)
                                }

                                if !modelCatalogMessage.isEmpty {
                                    Text(modelCatalogMessage)
                                        .font(.caption)
                                        .foregroundStyle(StudioTheme.mint)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                StudioCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Apple 本地处理", systemImage: "apple.intelligence")
                                .font(.headline)
                            Spacer()
                            PhaseBadge(text: AppleTextService.availability.label)
                        }

                        Toggle("长文本先在本机压缩", isOn: $settings.useApplePreprocessing)
                        Toggle("诊断时检索私人知识库", isOn: $settings.useKnowledgeBase)
                        Toggle(
                            "正文保存后自动重算情境更新",
                            isOn: $settings.automaticallyAnalyzeDramaticUpdates
                        )

                        Text("当前选中的远程模型用于叙事编译、情境更新和复杂推理。Apple 端侧能力只可选用于长文本压缩与局部润色，不参与 NSIR 的逻辑裁决。关闭自动重算不会关闭语义底座，可在正文的“情境透镜”中手动分析。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if settings.provider == .deepSeek {
                    StudioCard {
                        DisclosureGroup("高级连接设置") {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField("Base URL", text: $settings.baseURLString)
                                    .textFieldStyle(.roundedBorder)
                                Text("默认：https://api.deepseek.com")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 12)
                        }
                    }
                }

                HStack {
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.callout)
                            .foregroundStyle(StudioTheme.mint)
                    }
                    Spacer()
                    Button {
                        testConnection()
                    } label: {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("测试连接", systemImage: "network")
                        }
                    }
                    .disabled(!settings.hasAPIKey || !settings.hasSelectedModel || isTesting)
                }
            }
            .padding(28)
        }
        .frame(width: 660, height: 720)
        .background(StudioCanvas())
        .task {
            draftAPIKey = settings.apiKey
            draftSiliconFlowAPIKey = ""
            focusAPIKey(for: settings.provider)
            if settings.provider == .siliconFlow, settings.hasSiliconFlowAPIKey {
                let requestID = UUID()
                siliconFlowModelRequestID = requestID
                await loadSiliconFlowModels(requestID: requestID)
            }
        }
        .onChange(of: settings.provider) { _, provider in
            statusMessage = ""
            focusAPIKey(for: provider)
            if provider == .siliconFlow, settings.hasSiliconFlowAPIKey {
                refreshSiliconFlowModels()
            }
        }
        .onChange(of: settings.siliconFlowAPIKey) { _, apiKey in
            guard settings.provider == .siliconFlow,
                  !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            refreshSiliconFlowModels()
        }
        .alert("设置失败", isPresented: $showingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func saveDeepSeekKey() {
        do {
            try settings.saveAPIKey(draftAPIKey)
            statusMessage = "DeepSeek API Key 已保存"
        } catch {
            present(error)
        }
    }

    private func removeDeepSeekKey() {
        do {
            try settings.removeAPIKey()
            draftAPIKey = ""
            statusMessage = "DeepSeek API Key 已移除"
        } catch {
            present(error)
        }
    }

    private func saveSiliconFlowKey() {
        do {
            try settings.saveSiliconFlowAPIKey(draftSiliconFlowAPIKey)
            draftSiliconFlowAPIKey = ""
            statusMessage = "硅基流动 API Key 已保存"
        } catch {
            present(error)
        }
    }

    private func removeSiliconFlowKey() {
        do {
            try settings.removeSiliconFlowAPIKey()
            siliconFlowModelRequestID = UUID()
            isLoadingSiliconFlowModels = false
            draftSiliconFlowAPIKey = ""
            siliconFlowModelIDs = []
            modelCatalogMessage = ""
            statusMessage = "硅基流动 API Key 已移除"
        } catch {
            present(error)
        }
    }

    private var modelPickerIDs: [String] {
        let selected = settings.siliconFlowModel.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !selected.isEmpty, !siliconFlowModelIDs.contains(selected) else {
            return siliconFlowModelIDs
        }
        return [selected] + siliconFlowModelIDs
    }

    private func refreshSiliconFlowModels() {
        let requestID = UUID()
        siliconFlowModelRequestID = requestID
        Task {
            await loadSiliconFlowModels(requestID: requestID)
        }
    }

    private func loadSiliconFlowModels(requestID: UUID) async {
        isLoadingSiliconFlowModels = true
        modelCatalogMessage = ""
        defer {
            if siliconFlowModelRequestID == requestID {
                isLoadingSiliconFlowModels = false
            }
        }

        do {
            let configuration = try settings.siliconFlowCatalogConfiguration()
            let modelIDs = try await SiliconFlowModelCatalogClient(
                configuration: configuration
            ).fetchChatModelIDs()
            guard siliconFlowModelRequestID == requestID else { return }
            siliconFlowModelIDs = modelIDs

            let selected = settings.siliconFlowModel.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if selected.isEmpty {
                let preferredIDs = [
                    "deepseek-ai/DeepSeek-V4-Flash",
                    "deepseek-ai/DeepSeek-V3.2",
                    "Pro/deepseek-ai/DeepSeek-V3.2"
                ]
                settings.siliconFlowModel = preferredIDs.first(where: modelIDs.contains)
                    ?? modelIDs[0]
            }
            modelCatalogMessage = "已获取 \(modelIDs.count) 个可用对话模型"
        } catch {
            guard siliconFlowModelRequestID == requestID else { return }
            modelCatalogMessage = ""
            present(error)
        }
    }

    private func testConnection() {
        Task {
            isTesting = true
            defer { isTesting = false }
            do {
                let model = try await DeepSeekClient(
                    configuration: settings.configuration()
                ).testConnection()
                statusMessage = "连接成功 · \(model)"
            } catch {
                present(error)
            }
        }
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
    }

    private func focusAPIKey(for provider: AIProvider) {
        apiKeyFocused = provider == .deepSeek
        siliconFlowAPIKeyFocused = provider == .siliconFlow
    }
}
