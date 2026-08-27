import SwiftUI

struct ScreenplayElementSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var styles: [ScreenplayElementStyleDefinition]

    @State private var selectedStyleID: String?
    @State private var showingDeleteConfirmation = false

    init(styles: Binding<[ScreenplayElementStyleDefinition]>) {
        self._styles = styles
        self._selectedStyleID = State(
            initialValue: styles.wrappedValue.first?.id
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                styleList
                    .frame(minWidth: 220, idealWidth: 240, maxWidth: 290)

                detailPane
                    .frame(minWidth: 560)
            }

            Divider()

            HStack {
                Text("修改会立即应用到当前项目。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
        }
        .frame(minWidth: 820, minHeight: 600)
        .onAppear {
            repairSelection()
        }
        .onChange(of: styles.map(\.id)) {
            repairSelection()
        }
        .confirmationDialog(
            "删除这个自定义元素？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                deleteSelectedStyle()
            }
            .keyboardShortcut(.defaultAction)
            Button("取消", role: .cancel) {}
                .keyboardShortcut(.cancelAction)
        } message: {
            Text("已有正文不会被删除；引用这个元素的 Return 流转会安全退回“动作”。")
        }
    }

    private var styleList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("元素")
                    .font(.headline)
                Spacer()
                Text("\(styles.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)

            Divider()

            if styles.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "textformat")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("还没有元素")
                        .font(.headline)
                    Button("载入中文默认元素") {
                        styles = ScreenplayElementStyleDefinition.defaultStyles
                        selectedStyleID = styles.first?.id
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedStyleID) {
                    ForEach(styles) { style in
                        HStack(spacing: 9) {
                            Image(systemName: icon(for: style.baseType))
                                .frame(width: 18)
                                .foregroundStyle(
                                    style.isBuiltIn ? Color.accentColor : Color.orange
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.name)
                                    .lineLimit(1)
                                Text(
                                    style.isBuiltIn
                                        ? style.shortcutHint
                                        : "自定义 · \(style.shortcutHint)"
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .tag(style.id)
                    }
                }
                .listStyle(.sidebar)
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    addStyle()
                } label: {
                    Image(systemName: "plus")
                }
                .help("新增自定义元素")

                Button {
                    duplicateSelectedStyle()
                } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .disabled(selectedStyle == nil)
                .help("复制所选元素")

                Button {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selectedStyle?.isBuiltIn != false)
                .help(
                    selectedStyle?.isBuiltIn == true
                        ? "内置元素不能删除"
                        : "删除所选自定义元素"
                )

                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .frame(height: 42)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let style = selectedStyleBinding {
            VStack(spacing: 0) {
                detailHeader(style)
                Divider()

                TabView {
                    basicSettings(style)
                        .tabItem {
                            Label("基础", systemImage: "switch.2")
                        }

                    fontSettings(style)
                        .tabItem {
                            Label("字体", systemImage: "textformat.size")
                        }

                    paragraphSettings(style)
                        .tabItem {
                            Label("段落", systemImage: "paragraphsign")
                        }
                }
                .padding(16)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "textformat")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("选择一个元素进行设置")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func detailHeader(
        _ style: Binding<ScreenplayElementStyleDefinition>
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: style.wrappedValue.baseType))
                .font(.system(size: 20))
                .foregroundStyle(
                    style.wrappedValue.isBuiltIn ? Color.accentColor : Color.orange
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(style.wrappedValue.name)
                    .font(.title3.weight(.semibold))
                Text(style.wrappedValue.isBuiltIn ? "内置元素" : "项目自定义元素")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if style.wrappedValue.isBuiltIn {
                Button("恢复默认") {
                    restoreSelectedBuiltInStyle()
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
    }

    private func basicSettings(
        _ style: Binding<ScreenplayElementStyleDefinition>
    ) -> some View {
        Form {
            Section("身份") {
                TextField("名称", text: style.name)

                Picker("基础元素", selection: style.baseTypeRawValue) {
                    ForEach(FountainElementType.allCases) { type in
                        Text(type.rawValue)
                            .tag(type.rawValue)
                    }
                }

                LabeledContent("稳定标识") {
                    Text(style.wrappedValue.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("写作流转") {
                Picker("按下 Return 后", selection: style.nextStyleID) {
                    ForEach(styles) { candidate in
                        Text(candidate.name)
                            .tag(candidate.id)
                    }
                }

                HStack {
                    Text("快捷键")
                    Spacer()

                    Toggle("⌃", isOn: style.shortcutUsesControl)
                    Toggle("⌥", isOn: style.shortcutUsesOption)
                    Toggle("⇧", isOn: style.shortcutUsesShift)
                    Toggle("⌘", isOn: style.shortcutUsesCommand)

                    TextField("按键", text: style.shortcutKey)
                        .multilineTextAlignment(.center)
                        .frame(width: 54)

                    Text(style.wrappedValue.shortcutHint)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .trailing)
                }
                .toggleStyle(.checkbox)
            }
        }
        .formStyle(.grouped)
    }

    private func fontSettings(
        _ style: Binding<ScreenplayElementStyleDefinition>
    ) -> some View {
        Form {
            Section("字体") {
                TextField("字体名称", text: style.fontName)

                HStack {
                    Text("字号")
                    Spacer()
                    TextField(
                        "字号",
                        value: style.fontSize,
                        format: .number.precision(.fractionLength(0...1))
                    )
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    Stepper(
                        "",
                        value: style.fontSize,
                        in: 6...72,
                        step: 0.5
                    )
                    .labelsHidden()
                }
            }

            Section("字形") {
                Toggle("粗体", isOn: style.isBold)
                Toggle("斜体", isOn: style.isItalic)
                Toggle("拉丁字母自动大写", isOn: style.isUppercase)
            }

            Section("预览") {
                Text("场景中的人物做出一个可见的选择。")
                    .font(
                        previewFont(for: style.wrappedValue)
                    )
                    .italic(style.wrappedValue.isItalic)
                    .frame(maxWidth: .infinity, minHeight: 70)
            }
        }
        .formStyle(.grouped)
    }

    private func paragraphSettings(
        _ style: Binding<ScreenplayElementStyleDefinition>
    ) -> some View {
        Form {
            Section("对齐与边界") {
                Picker("对齐", selection: style.alignment) {
                    ForEach(ScreenplayElementTextAlignment.allCases) { alignment in
                        Text(alignment.displayName)
                            .tag(alignment)
                    }
                }

                measurementField(
                    "左侧缩进",
                    value: style.leftIndentInches,
                    suffix: "英寸"
                )
                measurementField(
                    "右侧边界",
                    value: style.rightBoundaryInches,
                    suffix: "英寸"
                )
            }

            Section("间距") {
                measurementField(
                    "段前",
                    value: style.spacingBefore,
                    suffix: "点"
                )
                measurementField(
                    "段后",
                    value: style.spacingAfter,
                    suffix: "点"
                )
                measurementField(
                    "行距",
                    value: style.lineSpacing,
                    suffix: "倍"
                )
            }

            Section("分页") {
                Toggle("从新页开始", isOn: style.startsNewPage)
                Text("场景标题默认开启此项，以保证下一场从新页开始。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func measurementField(
        _ label: String,
        value: Binding<Double>,
        suffix: String
    ) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(
                label,
                value: value,
                format: .number.precision(.fractionLength(0...2))
            )
            .multilineTextAlignment(.trailing)
            .frame(width: 82)
            Text(suffix)
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)
        }
    }

    private var selectedStyle: ScreenplayElementStyleDefinition? {
        guard let selectedStyleID else { return nil }
        return styles.first { $0.id == selectedStyleID }
    }

    private var selectedStyleBinding: Binding<ScreenplayElementStyleDefinition>? {
        guard let selectedStyleID,
              let index = styles.firstIndex(where: { $0.id == selectedStyleID }) else {
            return nil
        }
        return $styles[index]
    }

    private func addStyle() {
        let source = selectedStyle
            ?? ScreenplayElementStyleDefinition.defaultStyle(
                id: ScreenplayElementStyleID.action
            )
            ?? ScreenplayElementStyleDefinition.defaultStyles[0]
        var newStyle = source.customCopy(named: uniqueName("自定义元素"))
        newStyle.nextStyleID = newStyle.id
        styles.append(newStyle)
        selectedStyleID = newStyle.id
    }

    private func duplicateSelectedStyle() {
        guard let selectedStyle else { return }
        let copy = selectedStyle.customCopy(
            named: uniqueName("\(selectedStyle.name) 副本")
        )
        styles.append(copy)
        selectedStyleID = copy.id
    }

    private func deleteSelectedStyle() {
        guard let deletedStyleID = selectedStyleID,
              let index = styles.firstIndex(where: {
                  $0.id == deletedStyleID && !$0.isBuiltIn
              }) else {
            return
        }

        let fallbackID = styles.contains {
            $0.id == ScreenplayElementStyleID.action
        } ? ScreenplayElementStyleID.action : (styles.first?.id ?? "")

        styles.remove(at: index)
        for styleIndex in styles.indices
        where styles[styleIndex].nextStyleID == deletedStyleID {
            styles[styleIndex].nextStyleID = fallbackID.isEmpty
                ? styles[styleIndex].id
                : fallbackID
        }

        selectedStyleID = styles.indices.contains(index)
            ? styles[index].id
            : styles.last?.id
    }

    private func restoreSelectedBuiltInStyle() {
        guard let selectedStyleID,
              let index = styles.firstIndex(where: { $0.id == selectedStyleID }),
              styles[index].isBuiltIn,
              let original = ScreenplayElementStyleDefinition.defaultStyle(
                  id: selectedStyleID
              ) else {
            return
        }
        styles[index] = original
    }

    private func repairSelection() {
        if let selectedStyleID,
           styles.contains(where: { $0.id == selectedStyleID }) {
            return
        }
        selectedStyleID = styles.first?.id
    }

    private func uniqueName(_ proposed: String) -> String {
        let names = Set(styles.map(\.name))
        guard names.contains(proposed) else { return proposed }

        var suffix = 2
        while names.contains("\(proposed) \(suffix)") {
            suffix += 1
        }
        return "\(proposed) \(suffix)"
    }

    private func icon(for type: FountainElementType) -> String {
        switch type {
        case .sceneHeading: "film"
        case .action: "text.alignleft"
        case .character: "person.fill"
        case .parenthetical: "parentheses"
        case .dialogue: "text.bubble.fill"
        case .transition: "arrow.right.to.line"
        case .note: "note.text"
        }
    }

    private func previewFont(
        for style: ScreenplayElementStyleDefinition
    ) -> Font {
        let weight: Font.Weight = style.isBold ? .bold : .regular
        return .custom(
            style.fontName.isEmpty ? "Courier" : style.fontName,
            size: max(style.fontSize, 6)
        )
        .weight(weight)
    }
}
