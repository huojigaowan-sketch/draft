import SwiftUI

struct ClassicsLibraryView: View {
    let onStartExperiment: (StoryCase) -> Void

    @State private var searchText = ""
    @State private var selectedCulture = "全部"
    @State private var selectedTitle: String?

    private var cases: [StoryCase] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return StoryDNAService.shared.cases.filter { item in
            let cultureMatches = selectedCulture == "全部"
                || item.cultureLabel.contains(selectedCulture)
                || (selectedCulture == "全球" && !item.cultureLabel.contains("中国"))
            guard cultureMatches else { return false }
            guard !query.isEmpty else { return true }
            let haystack = [
                item.title,
                item.genres.joined(separator: " "),
                item.archetype,
                item.protagonist,
                item.themeConflict,
                item.patternTags.joined(separator: " "),
                item.cultureLabel,
                item.formLabel
            ].joined(separator: " ").lowercased()
            return haystack.contains(query)
        }
    }

    private var selectedCase: StoryCase? {
        if let selectedTitle,
           let match = StoryDNAService.shared.cases.first(where: { $0.title == selectedTitle }) {
            return match
        }
        return cases.first
    }

    var body: some View {
        ZStack {
            StudioCanvas()

            VStack(spacing: 0) {
                header
                Divider()

                HSplitView {
                    libraryList
                        .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
                    detail
                        .frame(minWidth: 480)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 650, ideal: 900)
        .task {
            if selectedTitle == nil {
                selectedTitle = cases.first?.title
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                EyebrowLabel(text: "Classic Story Observatory", color: StudioTheme.sky)
                Text("经典戏剧研究室")
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                Text("研究叙事功能，而不是背诵情节；研究完成后，马上把规律变成原创命题。")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("范围", selection: $selectedCulture) {
                Text("全部").tag("全部")
                Text("中国").tag("中国")
                Text("全球").tag("全球")
            }
            .pickerStyle(.segmented)
            .frame(width: 210)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .background(.ultraThinMaterial)
    }

    private var libraryList: some View {
        VStack(spacing: 10) {
            TextField("搜索人物、冲突、主题或类型", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 14)
                .padding(.top, 14)

            List(cases, selection: $selectedTitle) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.title)
                            .font(.callout.weight(.semibold))
                        Spacer()
                        Text(item.year.formatted(.number.grouping(.never)))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    Text("\(item.cultureLabel) · \(item.formLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.archetype)
                        .font(.caption2)
                        .foregroundStyle(StudioTheme.accent)
                }
                .padding(.vertical, 4)
                .tag(item.title)
            }
            .listStyle(.sidebar)
        }
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var detail: some View {
        if let item = selectedCase {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    StudioCard(padding: 24) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                PhaseBadge(text: item.cultureLabel)
                                PhaseBadge(text: item.formLabel)
                                Spacer()
                                Text(item.genres.joined(separator: " / "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(item.title)
                                .font(.system(size: 34, weight: .semibold, design: .serif))
                            Text(item.archetype)
                                .font(.title3)
                                .foregroundStyle(StudioTheme.accent)
                        }
                    }

                    researchCard(
                        title: "谁承担故事",
                        icon: "person.crop.circle",
                        tint: StudioTheme.sky,
                        body: item.protagonist
                    )
                    researchCard(
                        title: "目标与真正需要",
                        icon: "scope",
                        tint: StudioTheme.mint,
                        body: "\(item.externalGoal)\n\n\(item.internalNeed)"
                    )
                    researchCard(
                        title: "对抗如何施压",
                        icon: "bolt.horizontal.circle",
                        tint: StudioTheme.warm,
                        body: item.antagonistFunction
                    )
                    researchCard(
                        title: "主题冲突与人物弧",
                        icon: "arrow.triangle.branch",
                        tint: StudioTheme.accent,
                        body: "\(item.themeConflict)\n\n\(item.arc)"
                    )

                    StudioCard {
                        HStack(alignment: .center, spacing: 18) {
                            VStack(alignment: .leading, spacing: 6) {
                                EyebrowLabel(text: "原创实验", color: StudioTheme.mint)
                                Text("只借用功能，改变时代、人物关系和全部情节")
                                    .font(.headline)
                                Text("系统会把这份DNA带到“现实变故事”，与你的知识库一起生成新的写作方向。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("开始同构实验", systemImage: "leaf.fill") {
                                onStartExperiment(item)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        } else {
            ContentUnavailableView(
                "没有匹配的经典",
                systemImage: "theatermasks",
                description: Text("尝试更换搜索词或研究范围。")
            )
        }
    }

    private func researchCard(
        title: String,
        icon: String,
        tint: Color,
        body: String
    ) -> some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(tint)
                Text(body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
