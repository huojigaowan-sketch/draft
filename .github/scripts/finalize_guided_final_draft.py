from __future__ import annotations

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f"missing integration anchor: {label}")
    return text.replace(old, new, 1)


# 1. Guided output enum is iterated by the compiler.
path = "StoryMentor/Models/GuidedScreenplayObligations.swift"
text = read(path)
text = text.replace(
    "nonisolated enum GuidedScreenplayEchoKind: String, Codable, Hashable, Sendable {",
    "nonisolated enum GuidedScreenplayEchoKind: String, CaseIterable, Codable, Hashable, Sendable {",
)
write(path, text)


# 2. FountainParser.replacingScene returns a concrete String.
path = "StoryMentor/Services/GuidedFinalDraftProjectWriter.swift"
text = read(path)
old_writer = """    guard let updatedScreenplay = FountainParser.replacingScene(
      at: sceneIndex,
      in: project.screenplayText,
      with: result.fountainText
    ) else {
      throw GuidedFinalDraftProjectWriterError.sceneReplacementFailed
    }
"""
new_writer = """    let updatedScreenplay = FountainParser.replacingScene(
      at: sceneIndex,
      in: project.screenplayText,
      with: result.fountainText
    )
"""
text = replace_once(text, old_writer, new_writer, "concrete Fountain scene replacement")
write(path, text)


# 3. The novice default enters the real Final Draft editor wrapped by hidden obligations.
path = "StoryMentor/Views/Workspace/WorkspaceContentView.swift"
text = read(path)
text = replace_once(
    text,
    "GuidedFlowWorkspaceView(project: project, onNavigate: onNavigate)",
    "GuidedFinalDraftWorkspaceView(project: project, onNavigate: onNavigate)",
    "default guided Final Draft route",
)
write(path, text)


# 4. Add a quiet guided mode to the existing professional screenplay editor.
path = "StoryMentor/Views/Screenplay/ScreenplayStudioView.swift"
text = read(path)
text = replace_once(
    text,
    """    @Bindable var project: StoryProject
    let onNavigate: (WorkspaceSection) -> Void
    @Query private var workspaceStates: [ScreenplayWorkspaceState]
""",
    """    @Bindable var project: StoryProject
    let onNavigate: (WorkspaceSection) -> Void
    var guidedMode = false
    @Query private var workspaceStates: [ScreenplayWorkspaceState]
""",
    "ScreenplayStudioView guidedMode property",
)
text = replace_once(
    text,
    """        VStack(spacing: 10) {
            aiCreationHeader
            editorBody
            statusBar
        }
""",
    """        VStack(spacing: 10) {
            if !guidedMode {
                aiCreationHeader
            }
            editorBody
            statusBar
        }
""",
    "quiet guided editor chrome",
)
text = replace_once(
    text,
    """        .task {
            let addedNSIRMappings = SceneMappingEngine.synchronizeNSIRTransitions(
""",
    """        .task {
            if guidedMode {
                showingNavigator = false
                showingDramaticLens = false
                canvasMode = .scene
            }
            let addedNSIRMappings = SceneMappingEngine.synchronizeNSIRTransitions(
""",
    "guided editor launch state",
)
text = replace_once(
    text,
    """            lastCommittedFullText = project.screenplayText
            if let incomplete = firstIncompleteSmallBeatContract,
               let record = synchronizedSceneRecords.first(where: {
                   $0.sceneContractID == incomplete.id
               }) {
                loadScene(at: record.order)
            } else if let activeSceneID = state.activeSceneID,
""",
    """            lastCommittedFullText = project.screenplayText
            if let requestedContractID = project.requestedSceneContractID,
               let record = synchronizedSceneRecords.first(where: {
                   $0.sceneContractID == requestedContractID
               }) {
                project.requestedSceneContractID = nil
                loadScene(at: record.order)
            } else if let incomplete = firstIncompleteSmallBeatContract,
                      let record = synchronizedSceneRecords.first(where: {
                          $0.sceneContractID == incomplete.id
                      }) {
                loadScene(at: record.order)
            } else if let activeSceneID = state.activeSceneID,
""",
    "initial obligation scene focus",
)
text = replace_once(
    text,
    """        .onDisappear {
            sceneDraftSaveTask?.cancel()
            commitSceneDraft()
        }
""",
    """        .onChange(of: project.requestedSceneContractID) { _, requestedID in
            guard let requestedID else { return }
            focusRequestedSceneContract(requestedID)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .guidedFlowCommitScreenplay
            )
        ) { notification in
            guard let projectID = notification.object as? UUID,
                  projectID == project.id else { return }
            commitSceneDraft()
        }
        .onDisappear {
            sceneDraftSaveTask?.cancel()
            commitSceneDraft()
        }
""",
    "guided save and scene-focus hooks",
)
text = replace_once(
    text,
    """    private func selectSceneContract(_ contract: SceneContract) {
""",
    """    private func focusRequestedSceneContract(_ contractID: UUID) {
        guard let record = synchronizedSceneRecords.first(where: {
            $0.sceneContractID == contractID
        }) else { return }
        project.requestedSceneContractID = nil
        selectScene(record.order)
    }

    private func selectSceneContract(_ contract: SceneContract) {
""",
    "requested scene helper",
)
write(path, text)


# 5. Final architecture documentation.
doc = r'''# 引导式 Final Draft 完整剧本工作流

## 产品契约

StoryMentor 的默认创作路径不是无限问答，也不是先写素材、最后重写剧本。它遵循一条有明确终点的生产链：

```text
用户选择专业结构
        ↓
后台建立硬性剧作义务地图
        ↓
用户始终在现有 Final Draft / Fountain 编辑器中写作
        ↓
AI 只整理当前场景，并填充结构、场景、节拍与连续性义务
        ↓
创作回声引用作者原句，说明这些文字已经造成什么
        ↓
所有硬义务归零、阻断问题归零、作者确认
        ↓
完整标准剧本完成
```

## 前台与后台

```text
┌─────────────────────────────┐
│ 前台：现有专业剧本编辑器     │
│                             │
│  一个必要命题               │
│  场景标题 / 动作 / 人物 / 对白│
│  作者持续长写               │
│  一次创作回声               │
└──────────────┬──────────────┘
               │
               ▼
┌─────────────────────────────┐
│ 后台：隐藏完成地图           │
│                             │
│  结构阶段义务               │
│  场景状态契约               │
│  W/K/G/R/D/E 情境更新        │
│  理论 RAG 与 StoryDNA        │
│  连续性与交付检查            │
└─────────────────────────────┘
```

用户不需要重复抄写或将作文重新改成剧本。主文档从进入生产阶段开始就是唯一正式剧本。

## 1. 结构选择

`GuidedStructureSelectionView` 让作者确认：

- 常见结构模板：三幕剧、英雄之旅、救猫咪、八序列、故事圆环等；
- 目标规模：短剧 / 短片、中短篇、电影长片；
- 模板用途、适用范围与风险提示。

结构锁定后，`GuidedScreenplayObligationEngine` 将模板阶段转换为隐藏的完成地图。结构节点表示必须由正文兑现的戏剧功能，不要求一节点机械对应一场戏。

## 2. 硬性剧作义务

义务分为五类：

```text
structureSelection  结构与篇幅已确认
structureStage      结构阶段在正文中获得证据
sceneDraft          场景具有标准正文和有效状态变化
screenplayReview     连续性、结构、人物与格式无阻断问题
authorApproval       作者确认当前完整稿
```

只有硬义务会阻止项目宣布完成。对白润色、进一步压缩等软建议不制造无限任务。

## 3. 唯一写作表面

`.compiler` 默认打开 `GuidedFinalDraftWorkspaceView`，它在现有 `ScreenplayStudioView` 上方增加一条轻量命题栏。编辑器仍保留原项目的专业能力：

- Fountain / Final Draft 元素格式；
- 场景标题、动作、人物、括号、对白、转场；
- Return 与双 Return 的元素流转；
- 元素选择器、样式设置、场景切换、版本与导出；
- 正文与外部戏剧语义锚点分离。

`guidedMode` 只隐藏非必要面板并聚焦当前义务场景，不建立第二套编辑器。

## 4. 一轮创作

```text
当前未完成义务
      ↓
生成一个自然命题
      ↓
作者在当前正式场景中自由长写
      ↓
提交前同步保存场景草稿
      ↓
GuidedFinalDraftCompilerEngine 只编译当前场景
      ↓
GuidedFinalDraftProjectWriter 非破坏式写回
      ↓
创作回声 + 下一项义务
```

作者可以直接写标准剧本，也可以先自然展开。AI 的输出范围被限制在当前场景，禁止顺手生成整部大纲或全本。

## 5. AI 编译输入

当前场景编译同时读取：

- 作者当前场景正文；
- 已锁定结构阶段与项目命题；
- 人物、关系、世界、主题和连续性状态；
- 前后场景契约；
- 私人理论知识库检索片段；
- StoryDNA 的相近结构案例。

理论和案例只用于提高执行质量，不覆盖作者已经写下的事实和选择。

## 6. 写回规则

`GuidedFinalDraftProjectWriter` 在写回前创建可恢复版本，并同步：

- 标准 Fountain 场景正文；
- `SceneContract` 的目标、阻碍、转折、结果和下一场压力；
- `SceneMicroBeat` 与 `DramaticStateMutation`；
- 当前结构阶段的正文证据；
- 从原文中形成的人物材料；
- 作者原句、知识来源和创作回声；
- 语义投影与连续性检查状态。

作者原文和保留句进入项目材料，AI 摘要不能替代原文。

## 7. 即时创作回声

每次提交后，右侧回声只回答“这些文字已经造成了什么”，典型分类包括：

- 人物；
- 情节；
- 关系；
- 可拍画面；
- 声音与作者语气；
- 生活与世界；
- 结构推进。

每项发现必须附带作者原文证据，不使用总分，不把审美判断伪装成客观测量。

## 8. 完成条件

```text
所有结构阶段已有正文证据
+
所有必要场景已有标准剧本文字
+
所有场景至少完成一次有效状态变化
+
连续性、结构、人物与格式检查无阻断问题
+
作者确认当前全文指纹
=
剧本完成
```

任何正文修改都会使旧的最终确认失效。只有重新满足义务并由作者确认后，完成状态才恢复。

## 9. 关键源码

| 职责 | 文件 |
| --- | --- |
| 义务、完成快照与回声模型 | `StoryMentor/Models/GuidedScreenplayObligations.swift` |
| 隐藏完成地图与下一命题 | `StoryMentor/Services/GuidedScreenplayObligationEngine.swift` |
| 当前场景 AI 编译 | `StoryMentor/AI/GuidedFinalDraftCompilerEngine.swift` |
| 非破坏式正式写回 | `StoryMentor/Services/GuidedFinalDraftProjectWriter.swift` |
| 结构与篇幅选择 | `StoryMentor/Views/GuidedFlow/GuidedStructureSelectionView.swift` |
| 沉浸式工作区包装 | `StoryMentor/Views/GuidedFlow/GuidedFinalDraftWorkspaceView.swift` |
| 专业正文编辑器 | `StoryMentor/Views/Screenplay/ScreenplayStudioView.swift` |

## 10. 验证清单

合并代码执行 Swift 语法解析和关键集成断言。最终 macOS 验证应覆盖：

1. 旧项目 SwiftData 打开与迁移；
2. 新项目选择结构和篇幅；
3. 当前义务自动聚焦正确场景；
4. Return / 双 Return 的剧本元素流转不变；
5. 场景自动保存后再调用 AI 编译；
6. 编译前版本快照和撤销；
7. 理论 RAG / StoryDNA 有无数据时均可工作；
8. 结构、场景、节拍和正文义务能连续推进；
9. 全本修改后作者确认自动失效；
10. 硬义务归零后停止出题并允许导出。
'''
write("Documentation/GuidedFinalDraftWorkflow.md", doc)


architecture_path = "Documentation/GuidedFlowArchitecture.md"
architecture = read(architecture_path)
start = "<!-- guided-final-draft:start -->"
end = "<!-- guided-final-draft:end -->"
section = f'''\n{start}\n## 正式剧本终点\n\n引导式心流现在以现有 Final Draft / Fountain 编辑器作为唯一生产表面。结构模板在后台生成硬性剧作义务；每次命题只补当前真实缺口，作者文字被编译进同一份正式剧本。所有结构、场景、情境更新、连续性和格式义务完成并经作者确认后，系统停止出题。完整设计见 [`GuidedFinalDraftWorkflow.md`](GuidedFinalDraftWorkflow.md)。\n{end}\n'''
if start in architecture and end in architecture:
    architecture = re.sub(
        re.escape(start) + r".*?" + re.escape(end),
        section.strip(),
        architecture,
        flags=re.S,
    )
else:
    architecture = architecture.rstrip() + "\n" + section
write(architecture_path, architecture)


readme_path = "README.md"
readme = read(readme_path)
start = "<!-- guided-final-draft-readme:start -->"
end = "<!-- guided-final-draft-readme:end -->"
section = f'''\n{start}\n## Guided Final Draft workflow\n\nThe novice-first route now starts with an explicit professional structure and target scale, then keeps the existing Final Draft-style Fountain editor as the only writing surface. Hidden structure, scene, dramatic-state, continuity, and delivery obligations determine the next prompt and the real completion point. Each accepted scene is compiled non-destructively with theory RAG and StoryDNA context, while creative echoes cite the author's own lines. The system stops prompting only when all hard obligations are satisfied and the author approves the complete screenplay.\n\nSee [`Documentation/GuidedFinalDraftWorkflow.md`](Documentation/GuidedFinalDraftWorkflow.md).\n{end}\n'''
if start in readme and end in readme:
    readme = re.sub(
        re.escape(start) + r".*?" + re.escape(end),
        section.strip(),
        readme,
        flags=re.S,
    )
else:
    readme = readme.rstrip() + "\n" + section
write(readme_path, readme)


# 6. Remove transport/recovery automation from the final product tree.
for relative in (
    ".github/workflows/apply-final-draft-obligation.yml",
    ".github/workflows/finalize-final-draft-obligation.yml",
    ".github/workflows/recover-final-draft-flow.yml",
    ".github/workflows/finalize-guided-final-draft-v4.yml",
    ".github/scripts/finalize_guided_final_draft.py",
):
    target = ROOT / relative
    if target.exists():
        target.unlink()
