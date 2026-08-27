import SwiftUI

struct ScreenplaySceneHeadingEditorView: View {
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var heading: String
    @FocusState private var headingFocused: Bool

    init(
        initialHeading: String,
        onSave: @escaping (String) -> Void
    ) {
        self.onSave = onSave
        _heading = State(initialValue: initialHeading)
    }

    private var localizedHeading: String? {
        FountainParser.localizedSceneHeading(heading)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑场景标题")
                .font(.title2.weight(.semibold))
            TextField("例如：内. 客厅 - 日", text: $heading)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .focused($headingFocused)
            Text("使用“内.”、“外.”或“内/外.”开头。标题只负责显示，场景身份由稳定 ID 保存。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !heading.isEmpty, localizedHeading == nil {
                Label(
                    "无法识别场景类型，请补充“内.”、“外.”或“内/外.”。",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    guard let localizedHeading else { return }
                    onSave(localizedHeading)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(localizedHeading == nil)
            }
        }
        .padding(22)
        .frame(width: 520)
        .task {
            headingFocused = true
        }
    }
}

private enum ScreenplayReportSection: String, CaseIterable, Identifiable {
    case summary = "总览"
    case scenes = "场景"
    case characters = "人物"
    case locations = "地点"

    var id: String { rawValue }
}

struct ScreenplayReportView: View {
    let report: ScreenplayReport
    let onSelectScene: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var section: ScreenplayReportSection = .summary

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("编剧报告")
                        .font(.title2.weight(.semibold))
                    Text("场景、人物、地点与时长均从当前剧本实时生成")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Picker("报告", selection: $section) {
                ForEach(ScreenplayReportSection.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            Divider()

            Group {
                switch section {
                case .summary:
                    summary
                case .scenes:
                    sceneReport
                case .characters:
                    characterReport
                case .locations:
                    locationReport
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 560, idealHeight: 660)
    }

    private var summary: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 150), spacing: 12)
                ],
                spacing: 12
            ) {
                reportMetric("场景", "\(report.scenes.count) 场", "square.stack.3d.up")
                reportMetric("标准页数", "约 \(report.totalPages) 页", "doc.text")
                reportMetric(
                    "预计时长",
                    ChineseScreenplayTiming.formattedDuration(
                        report.totalDurationSeconds
                    ),
                    "clock"
                )
                reportMetric("主要人物", "\(report.totalCharacterCount) 人", "person.2")
                reportMetric("内景", "\(report.interiorSceneCount) 场", "house")
                reportMetric("外景", "\(report.exteriorSceneCount) 场", "sun.max")
                reportMetric("内/外", "\(report.mixedSceneCount) 场", "arrow.left.arrow.right")
                reportMetric(
                    "日/夜",
                    "\(report.daySceneCount) / \(report.nightSceneCount)",
                    "circle.lefthalf.filled"
                )
            }
            .padding(20)
        }
    }

    private func reportMetric(
        _ title: String,
        _ value: String,
        _ icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(StudioTheme.mint)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .padding(15)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }

    private var sceneReport: some View {
        List(report.scenes) { scene in
            Button {
                onSelectScene(scene.sceneIndex)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text("\(scene.sceneIndex + 1)")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .frame(width: 30, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scene.heading)
                            .font(.callout.weight(.semibold))
                        Text(scene.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Text(scene.characters.joined(separator: "、"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(scene.estimatedPages) 页")
                        Text(
                            ChineseScreenplayTiming.formattedDuration(
                                scene.estimatedDurationSeconds
                            )
                        )
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var characterReport: some View {
        List(report.characters) { character in
            HStack {
                Label(character.name, systemImage: "person.crop.circle")
                Spacer()
                Text("\(character.sceneCount) 场")
                    .foregroundStyle(.secondary)
                Text("\(character.dialogueCueCount) 次对白")
                    .frame(width: 90, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
        .overlay {
            if report.characters.isEmpty {
                ContentUnavailableView(
                    "尚未识别到人物",
                    systemImage: "person.slash",
                    description: Text("使用人物元素或 @人物名 写入对白后会自动统计。")
                )
            }
        }
    }

    private var locationReport: some View {
        List(report.locations) { location in
            HStack {
                Text(location.kind.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(StudioTheme.mint)
                    .frame(width: 44, alignment: .leading)
                Text(location.name)
                Spacer()
                Text("\(location.sceneCount) 场")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.callout)
        }
    }
}

struct ScreenplayFindReplaceView: View {
    let scriptText: String
    let onSelectScene: (Int) -> Void
    let onApply: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var replacement = ""
    @State private var scope: ScreenplayBulkEditScope = .fullScript
    @State private var caseSensitive = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case query
        case replacement
    }

    private var results: [ScreenplaySearchResult] {
        ScreenplayBulkEditor.search(
            query,
            scope: scope,
            caseSensitive: caseSensitive,
            in: scriptText
        )
    }

    private var occurrenceCount: Int {
        results.reduce(0) { $0 + $1.occurrenceCount }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("查找与批量修改")
                        .font(.title2.weight(.semibold))
                    Text("执行替换前会自动保存一个可恢复版本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Form {
                TextField("查找", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .query)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField = .replacement
                    }
                TextField("替换为", text: $replacement)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .replacement)
                    .submitLabel(.done)
                    .onSubmit {
                        applyReplacement()
                    }
                Picker("范围", selection: $scope) {
                    ForEach(ScreenplayBulkEditScope.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("区分大小写", isOn: $caseSensitive)
            }
            .formStyle(.grouped)
            .frame(height: 190)

            Divider()

            List(results) { result in
                Button {
                    onSelectScene(result.sceneIndex)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(result.sceneIndex + 1)")
                            .font(.caption.monospacedDigit().weight(.bold))
                            .frame(width: 28, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.heading)
                                .font(.callout.weight(.semibold))
                            Text(result.excerpt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Text("\(result.occurrenceCount) 处")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if query.isEmpty {
                    ContentUnavailableView(
                        "输入要查找的内容",
                        systemImage: "magnifyingglass"
                    )
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }

            Divider()

            HStack {
                Text("共 \(results.count) 个场景、\(occurrenceCount) 处匹配")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("全部替换 \(occurrenceCount) 处") {
                    applyReplacement()
                }
                .buttonStyle(.borderedProminent)
                .disabled(query.isEmpty || occurrenceCount == 0)
            }
            .padding(16)
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 600)
        .task {
            focusedField = .query
        }
    }

    private func applyReplacement() {
        guard !query.isEmpty, occurrenceCount > 0 else { return }
        let updated = ScreenplayBulkEditor.replacing(
            query,
            with: replacement,
            scope: scope,
            caseSensitive: caseSensitive,
            in: scriptText
        )
        onApply(updated, "批量修改前：\(query)")
        dismiss()
    }
}
