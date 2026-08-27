import AppKit
import SwiftData
import SwiftUI

struct FragmentMemoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoryFragment.updatedAt, order: .reverse)
    private var fragments: [StoryFragment]

    let onGrow: (StoryFragment) -> Void

    @State private var searchText = ""
    @State private var selectedKindRawValue = "全部"
    @State private var selectedFragmentID: UUID?
    @State private var fragmentPendingDeletion: StoryFragment?
    @State private var persistenceError = ""
    @State private var showingPersistenceError = false

    private var filteredFragments: [StoryFragment] {
        fragments.filter { fragment in
            let matchesKind = selectedKindRawValue == "全部"
                || fragment.kindRawValue == selectedKindRawValue
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || fragment.title.localizedCaseInsensitiveContains(query)
                || fragment.content.localizedCaseInsensitiveContains(query)
                || fragment.tagsText.localizedCaseInsensitiveContains(query)
                || fragment.note.localizedCaseInsensitiveContains(query)
            return matchesKind && matchesSearch
        }
    }

    private var selectedFragment: StoryFragment? {
        guard let selectedFragmentID else {
            return filteredFragments.first
        }
        return fragments.first { $0.id == selectedFragmentID }
    }

    var body: some View {
        ZStack {
            StudioCanvas()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    controls

                    if filteredFragments.isEmpty {
                        emptyState
                    } else {
                        HStack(alignment: .top, spacing: 18) {
                            fragmentList
                                .frame(maxWidth: 390)
                            if let selectedFragment {
                                fragmentDetail(selectedFragment)
                            }
                        }
                    }
                }
                .padding(26)
                .frame(maxWidth: 1_080)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationSplitViewColumnWidth(min: 650, ideal: 920)
        .searchable(text: $searchText, prompt: "搜索标题、内容、标签或备注")
        .onAppear {
            if selectedFragmentID == nil {
                selectedFragmentID = fragments.first?.id
            }
        }
        .confirmationDialog(
            "移除这个喜爱碎片？",
            isPresented: Binding(
                get: { fragmentPendingDeletion != nil },
                set: { if !$0 { fragmentPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("移除", role: .destructive) {
                deletePendingFragment()
            }
            .keyboardShortcut(.defaultAction)
            Button("取消", role: .cancel) {
                fragmentPendingDeletion = nil
            }
            .keyboardShortcut(.cancelAction)
        } message: {
            Text("只会从灵感碎片库移除，不会影响原来的故事项目或AI结果。")
        }
        .alert("无法移除碎片", isPresented: $showingPersistenceError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(persistenceError)
        }
    }

    private var header: some View {
        StudioCard(padding: 25) {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 9) {
                    EyebrowLabel(text: "Fragment Memory", color: StudioTheme.warm)
                    Text("把喜欢的结果留下来")
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                    Text("好故事常从彼此无关的碎片重新连接。收藏不会再次调用AI；它只是把你真正有感觉的方向，变成可以积累、检索和继续生长的私人记忆。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 720, alignment: .leading)
                }
                Spacer()
                ZStack {
                    Image(systemName: "snowflake")
                        .font(.system(size: 58, weight: .ultraLight))
                        .foregroundStyle(StudioTheme.sky)
                    Image(systemName: "heart.fill")
                        .font(.title2)
                        .foregroundStyle(StudioTheme.warm)
                }
                .frame(width: 86, height: 86)
            }
        }
    }

    private var controls: some View {
        HStack {
            Label("\(fragments.count) 个喜爱碎片", systemImage: "heart.fill")
                .font(.headline)
                .foregroundStyle(StudioTheme.warm)
            Spacer()
            Picker("类型", selection: $selectedKindRawValue) {
                Text("全部").tag("全部")
                ForEach(StoryFragmentKind.allCases) { kind in
                    Label(kind.rawValue, systemImage: kind.systemImage)
                        .tag(kind.rawValue)
                }
            }
            .frame(width: 180)
        }
    }

    private var fragmentList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(filteredFragments) { fragment in
                Button {
                    selectedFragmentID = fragment.id
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(fragment.kind.rawValue, systemImage: fragment.kind.systemImage)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(color(for: fragment.kind))
                            Spacer()
                            Text(fragment.updatedAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(fragment.title)
                            .font(.system(.title3, design: .serif, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(fragment.content)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                        if !fragment.tags.isEmpty {
                            Text(fragment.tags.prefix(4).map { "#\($0)" }.joined(separator: "  "))
                                .font(.caption2)
                                .foregroundStyle(StudioTheme.accent)
                                .lineLimit(1)
                        }
                    }
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        selectedFragment?.id == fragment.id
                            ? color(for: fragment.kind).opacity(0.10)
                            : Color.primary.opacity(0.025),
                        in: RoundedRectangle(cornerRadius: 15)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(
                                selectedFragment?.id == fragment.id
                                    ? color(for: fragment.kind).opacity(0.45)
                                    : Color.primary.opacity(0.05)
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func fragmentDetail(_ fragment: StoryFragment) -> some View {
        StudioCard(padding: 22) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        EyebrowLabel(text: fragment.kind.rawValue, color: color(for: fragment.kind))
                        Text(fragment.title)
                            .font(.system(.title2, design: .serif, weight: .semibold))
                    }
                    Spacer()
                    Menu {
                        Button("复制完整内容", systemImage: "doc.on.doc") {
                            copy(fragment.content)
                        }
                        Button("移除喜爱", systemImage: "heart.slash", role: .destructive) {
                            fragmentPendingDeletion = fragment
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                    .menuStyle(.borderlessButton)
                }

                if !fragment.projectTitle.isEmpty {
                    Label("来自《\(fragment.projectTitle)》", systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ScrollView {
                    Text(fragment.content)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 220, maxHeight: 380)
                .padding(14)
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 7) {
                    EyebrowLabel(text: "标签")
                    TextField(
                        "例如：反派、母女关系、黑色喜剧",
                        text: Binding(
                            get: { fragment.tagsText },
                            set: {
                                fragment.tagsText = $0
                                fragment.updatedAt = .now
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 7) {
                    EyebrowLabel(text: "为什么喜欢它")
                    TextEditor(
                        text: Binding(
                            get: { fragment.note },
                            set: {
                                fragment.note = $0
                                fragment.updatedAt = .now
                            }
                        )
                    )
                    .font(.callout)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 72)
                    .padding(8)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
                }

                HStack {
                    if fragment.grownProjectID != nil {
                        Label("已经长成项目", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(StudioTheme.mint)
                    }
                    Spacer()
                    Button("让它长成故事", systemImage: "leaf.arrow.triangle.circlepath") {
                        onGrow(fragment)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        StudioCard {
            VStack(spacing: 14) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(StudioTheme.warm)
                Text(searchText.isEmpty ? "还没有喜爱碎片" : "没有找到匹配碎片")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                Text(searchText.isEmpty
                     ? "在改编方向、故事选项或AI诊断旁点击心形，它就会来到这里。"
                     : "换一个关键词或类型看看。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 260)
        }
    }

    private func color(for kind: StoryFragmentKind) -> Color {
        switch kind {
        case .adaptationDirection: StudioTheme.mint
        case .storyChoice: StudioTheme.accent
        case .analysis: StudioTheme.sky
        case .blueprint: StudioTheme.warm
        case .free: .secondary
        }
    }

    private func copy(_ content: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }

    private func deletePendingFragment() {
        guard let fragmentPendingDeletion else { return }
        let nextID = filteredFragments.first { $0.id != fragmentPendingDeletion.id }?.id
        modelContext.delete(fragmentPendingDeletion)
        do {
            try ProjectPersistenceStore.savePendingChanges(in: modelContext)
            selectedFragmentID = nextID
            self.fragmentPendingDeletion = nil
        } catch {
            persistenceError = error.localizedDescription
            showingPersistenceError = true
        }
    }
}
