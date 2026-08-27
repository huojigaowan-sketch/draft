import SwiftUI

struct GuidedStructureSelectionView: View {
  let project: StoryProject
  let onConfirm: (StoryStructureTemplate, GuidedScriptScale) -> Void

  @State private var selectedTemplateID = "three-act"
  @State private var selectedScale: GuidedScriptScale = .shortFilm
  @State private var query = ""

  private var templates: [StoryStructureTemplate] {
    let commonIDs = [
      "three-act",
      "hero-journey",
      "save-the-cat",
      "snowflake",
      "guided-core",
      "sequence-approach",
      "story-circle",
    ]
    let all = StoryStructureCatalog.templates
    let common = commonIDs.compactMap { id in
      all.first { $0.id == id }
    }
    let remainder = all.filter { template in
      !commonIDs.contains(template.id)
    }
    let ordered = common + remainder
    let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return ordered }
    return ordered.filter {
      [$0.name, $0.subtitle, $0.experience, $0.bestFor]
        .joined(separator: " ")
        .localizedCaseInsensitiveContains(clean)
    }
  }

  private var selectedTemplate: StoryStructureTemplate? {
    StoryStructureCatalog.templates.first { $0.id == selectedTemplateID }
  }

  var body: some View {
    ZStack {
      StudioCanvas()

      VStack(spacing: 0) {
        header
        Divider().opacity(0.4)

        ScrollView {
          VStack(alignment: .leading, spacing: 22) {
            scalePicker
            templateGrid
          }
          .padding(.horizontal, 30)
          .padding(.vertical, 24)
          .frame(maxWidth: 1_100)
          .frame(maxWidth: .infinity)
        }

        footer
      }
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 18) {
      VStack(alignment: .leading, spacing: 5) {
        EyebrowLabel(text: "先确定全本完成地图", color: StudioTheme.mint)
        Text("你想用哪种方式讲这个故事？")
          .font(.system(size: 31, weight: .semibold, design: .serif))
        Text("结构只在后台约束剧本。进入写作后，你只会看到当前场景和一个必要命题。")
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      Spacer()

      TextField("搜索结构", text: $query)
        .textFieldStyle(.roundedBorder)
        .frame(width: 230)
    }
    .padding(.horizontal, 28)
    .padding(.vertical, 18)
    .background(.ultraThinMaterial)
  }

  private var scalePicker: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("目标篇幅")
        .font(.headline)

      HStack(spacing: 10) {
        ForEach(GuidedScriptScale.allCases) { scale in
          Button {
            selectedScale = scale
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text(scale.rawValue)
                  .font(.callout.weight(.semibold))
                Spacer()
                Image(
                  systemName: selectedScale == scale
                    ? "checkmark.circle.fill"
                    : "circle"
                )
                .foregroundStyle(
                  selectedScale == scale ? StudioTheme.mint : .secondary
                )
              }
              Text(scale.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(
              selectedScale == scale
                ? StudioTheme.mint.opacity(0.09)
                : Color.primary.opacity(0.03),
              in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay {
              RoundedRectangle(cornerRadius: 14)
                .stroke(
                  selectedScale == scale
                    ? StudioTheme.mint.opacity(0.55)
                    : Color.primary.opacity(0.05)
                )
            }
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private var templateGrid: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("常见剧本结构")
          .font(.headline)
        Spacer()
        Text("可在高级工具中查看完整理论来源")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 285, maximum: 360), spacing: 12)],
        spacing: 12
      ) {
        ForEach(templates) { template in
          templateCard(template)
        }
      }
    }
  }

  private func templateCard(
    _ template: StoryStructureTemplate
  ) -> some View {
    let selected = template.id == selectedTemplateID
    return Button {
      selectedTemplateID = template.id
    } label: {
      VStack(alignment: .leading, spacing: 11) {
        HStack(alignment: .top, spacing: 11) {
          Image(systemName: template.icon)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(selected ? StudioTheme.mint : StudioTheme.accent)
            .frame(width: 38, height: 38)
            .background(
              (selected ? StudioTheme.mint : StudioTheme.accent).opacity(0.10),
              in: RoundedRectangle(cornerRadius: 11)
            )

          VStack(alignment: .leading, spacing: 3) {
            Text(template.name)
              .font(.system(size: 18, weight: .semibold, design: .serif))
            Text(template.subtitle)
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer(minLength: 5)
          Image(systemName: selected ? "checkmark.seal.fill" : "circle")
            .foregroundStyle(selected ? StudioTheme.mint : .secondary)
        }

        Text(template.experience)
          .font(.callout)
          .foregroundStyle(.primary)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)

        Text("适合：\(template.bestFor)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)

        HStack {
          Label("\(template.stages.count) 个结构义务", systemImage: "checklist")
          Spacer()
          Text(template.family)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(selected ? StudioTheme.mint : .secondary)
      }
      .padding(16)
      .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
      .background(
        selected
          ? StudioTheme.mint.opacity(0.075)
          : Color.primary.opacity(0.025),
        in: RoundedRectangle(cornerRadius: 18)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 18)
          .stroke(
            selected
              ? StudioTheme.mint.opacity(0.55)
              : Color.primary.opacity(0.05),
            lineWidth: selected ? 1.5 : 1
          )
      }
    }
    .buttonStyle(.plain)
  }

  private var footer: some View {
    HStack(spacing: 14) {
      if let selectedTemplate {
        VStack(alignment: .leading, spacing: 2) {
          Text("\(selectedTemplate.name) · \(selectedScale.rawValue)")
            .font(.callout.weight(.semibold))
          Text("系统将建立约 \(max(selectedTemplate.stages.count, selectedScale.targetSceneCount)) 个正式场景槽位，并随着写作逐一完成。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Spacer()

      Button("确认结构并进入剧本", systemImage: "text.book.closed.fill") {
        guard let selectedTemplate else { return }
        onConfirm(selectedTemplate, selectedScale)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .tint(StudioTheme.mint)
      .disabled(selectedTemplate == nil)
    }
    .padding(.horizontal, 28)
    .padding(.vertical, 14)
    .background(.ultraThinMaterial)
  }
}
