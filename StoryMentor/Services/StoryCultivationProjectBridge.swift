import Foundation
import SwiftData

/// 把故事实验室的确定性结果接入生产模型。
///
/// 这个桥只铺设可追溯的生产底稿：不会生成剧本文字、不会锁定结构，也不会
/// 覆盖作者已经写过的字段。再次接力同一颗种子时，会更新桥自己创建的素材并
/// 逐项补齐缺失数据，而不是创建第二个项目。
@MainActor
enum StoryCultivationProjectBridge {
    private static let sourceOrigin = "故事实验室 · 原始种子"
    private static let crystalOrigin = "故事实验室 · 结晶接力"
    private static let structureOrigin = "故事实验室 · 实验选择"
    private static let legacyCreationNote = "由 NSIR 叙事编译台创建；作者命题为不可被 AI 擅自改写的 L0 公理。"

    static func connect(
        seed: StorySeed,
        snapshot: StoryCultivationSnapshot,
        projects: [StoryProject],
        in modelContext: ModelContext
    ) -> StoryProject {
        let project: StoryProject
        let isNewProject: Bool

        if let linkedID = seed.projectID,
           let linked = resolveProject(
               id: linkedID,
               projects: projects,
               in: modelContext
           ) {
            project = linked
            isNewProject = false
        } else {
            project = StoryProject(
                title: clean(seed.title).isEmpty ? "未命名故事" : clean(seed.title),
                logline: clean(snapshot.crystal.coreIdea)
            )
            modelContext.insert(project)
            isNewProject = true
        }

        let fingerprintBefore = bridgeFingerprint(seed: seed, project: project)

        applyProjectFields(
            to: project,
            seed: seed,
            snapshot: snapshot,
            isNewProject: isNewProject
        )
        let characterIDs = synchronizeCharacters(
            in: project,
            snapshot: snapshot,
            modelContext: modelContext
        )
        synchronizeArtifacts(
            in: project,
            seed: seed,
            snapshot: snapshot,
            modelContext: modelContext
        )
        synchronizeTask(
            in: project,
            snapshot: snapshot,
            modelContext: modelContext
        )
        synchronizeNSIR(
            in: project,
            seed: seed,
            snapshot: snapshot,
            characterIDs: characterIDs
        )

        if seed.linkedProjectID != project.id {
            seed.linkedProjectID = project.id
        }
        let fingerprintAfter = bridgeFingerprint(seed: seed, project: project)
        if isNewProject || fingerprintBefore != fingerprintAfter {
            seed.updatedAt = .now
            project.touch()
        }
        return project
    }

    /// 补齐旧版本已经关联、但只收到一整段命题文本的项目。
    @discardableResult
    static func repairLinkedProjects(
        seeds: [StorySeed],
        projects: [StoryProject],
        in modelContext: ModelContext
    ) -> Bool {
        var changed = false
        for seed in seeds where seed.projectID != nil {
            let snapshot = seed.cultivationSnapshot
            guard snapshot.crystal.isReadyForProduction,
                  let linkedID = seed.projectID,
                  let linkedProject = resolveProject(
                      id: linkedID,
                      projects: projects,
                      in: modelContext
                  ) else { continue }
            let projectUpdatedAt = linkedProject.updatedAt
            let seedUpdatedAt = seed.updatedAt
            _ = connect(
                seed: seed,
                snapshot: snapshot,
                projects: projects,
                in: modelContext
            )
            if projectUpdatedAt != resolveProject(
                id: linkedID,
                projects: projects,
                in: modelContext
            )?.updatedAt
                || seedUpdatedAt != seed.updatedAt {
                changed = true
            }
        }
        return changed
    }

    private static func resolveProject(
        id: UUID,
        projects: [StoryProject],
        in modelContext: ModelContext
    ) -> StoryProject? {
        if let project = projects.first(where: { $0.id == id }) {
            return project
        }
        let descriptor = FetchDescriptor<StoryProject>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private static func applyProjectFields(
        to project: StoryProject,
        seed: StorySeed,
        snapshot: StoryCultivationSnapshot,
        isNewProject: Bool
    ) {
        let crystal = snapshot.crystal
        let sourceText = firstNonempty(snapshot.rawIdea, seed.sourceText)
        let dramaticQuestion = firstNonempty(
            snapshot.dramaticQuestions.first,
            snapshot.hiddenQuestion
        )
        let worldRules = snapshot.atoms
            .filter { $0.type == .worldRule }
            .map(\.content)
        let themeText = joinedUnique([crystal.theme] + snapshot.themes)
        let conflictText = joinedUnique(
            [crystal.conflict] + snapshot.valueConflicts + snapshot.contradictions
        )
        let characterBible = characterBibleText(snapshot)
        let decisionText = experimentDecisionText(snapshot)
        let productionBrief = productionBriefText(seed: seed, snapshot: snapshot)
        let structureStartingPoint = structureStartingPointText(snapshot)

        fill(&project.title, with: clean(seed.title))
        let nextLogline = clean(crystal.coreIdea)
        if (isNewProject
            || project.logline.storyScienceTrimmed.isEmpty
            || project.logline.storyScienceTrimmed == crystal.compilerProposition.storyScienceTrimmed)
            && project.logline != nextLogline {
            project.logline = nextLogline
        }
        fill(&project.sourceTitle, with: clean(seed.title))
        fill(&project.sourceText, with: sourceText)
        fill(&project.sourceFacts, with: clean(seed.factualSummary))
        fill(&project.dramaticPromise, with: dramaticQuestion)
        fill(&project.creativeDirectionText, with: productionBrief)
        fill(&project.storyPathText, with: decisionText)
        fill(&project.structureText, with: structureStartingPoint)
        fill(&project.worldText, with: joinedUnique(worldRules))
        fill(&project.themeText, with: themeText)
        fill(&project.characterBibleText, with: characterBible)
        fill(&project.worldBibleText, with: joinedUnique(worldRules))
        fill(&project.themeBibleText, with: themeText)
        fill(&project.coreConflictText, with: conflictText)

        let digest = """
        【实验室接力】
        第 \(max(snapshot.round, 1)) 轮 · \(snapshot.decisions.count) 次已确认实验

        【故事核心】
        \(fallback(crystal.coreIdea, "待作者确认"))

        【人物小传】
        \(fallback(characterBible, crystal.characterInsight))

        【世界压力】
        \(fallback(joinedUnique(worldRules), "本轮实验尚未决定世界规则"))

        【主题命题】
        \(fallback(themeText, "待作者确认"))

        【核心冲突】
        \(fallback(conflictText, "待作者确认"))

        【下一步】
        \(fallback(snapshot.evaluation.nextStep, "继续锁定一条可验证的创作决定"))
        """
        fill(&project.storyBibleDigest, with: digest)
        if project.storyBibleRevision == 0 {
            project.storyBibleRevision = 1
            project.storyBibleUpdatedAt = .now
            project.storyBibleSyncNote = "由故事实验室建立第一版生产底稿；未锁定结构，未改动剧本正文。"
        }

        let notes = """
        【实验发现】
        \(fallback(snapshot.discovery, "本轮尚无补充发现"))

        【隐藏问题】
        \(fallback(snapshot.hiddenQuestion, "待继续发现"))

        【为什么值得追随】
        \(fallback(crystal.whyInteresting, "待作者补充"))

        【仍待解决】
        \(fallback(snapshot.evaluation.gaps.map { "• \($0)" }.joined(separator: "\n"), "当前没有标记缺口"))

        【来源说明】
        \(fallback(snapshot.provenanceNote, "来自故事实验室的作者实验记录"))
        """
        if (project.notes.storyScienceTrimmed.isEmpty
            || project.notes.storyScienceTrimmed == legacyCreationNote.storyScienceTrimmed)
            && project.notes != notes {
            project.notes = notes
        }
    }

    private static func synchronizeCharacters(
        in project: StoryProject,
        snapshot: StoryCultivationSnapshot,
        modelContext: ModelContext
    ) -> [UUID] {
        var orderedIDs: [UUID] = []
        let existingByID = Dictionary(uniqueKeysWithValues: project.characters.map { ($0.id, $0) })
        var existingByName: [String: StoryCharacter] = [:]
        for character in project.characters {
            let key = normalizedName(character.name)
            if existingByName[key] == nil { existingByName[key] = character }
        }

        for (index, psychology) in snapshot.psychology.enumerated() {
            let name = clean(psychology.character)
            guard !name.isEmpty else { continue }
            let character: StoryCharacter
            if let existing = existingByID[psychology.id]
                ?? existingByName[normalizedName(name)] {
                character = existing
            } else {
                character = StoryCharacter(
                    id: psychology.id,
                    name: name,
                    role: index == 0 ? .protagonist : .supporting,
                    project: project
                )
                modelContext.insert(character)
                project.characters.append(character)
                existingByName[normalizedName(name)] = character
            }

            let previousCharacterState = [
                character.seedText,
                character.externalGoal,
                character.internalNeed,
                character.fear,
                character.trauma,
                character.falseBelief,
                character.flaw,
                character.arc
            ]
            fill(&character.seedText, with: joinedUnique([
                index == 0 ? snapshot.crystal.characterInsight : "",
                psychology.contradiction
            ]))
            fill(&character.externalGoal, with: clean(psychology.desire))
            fill(
                &character.internalNeed,
                with: joinedUnique([psychology.need.rawValue, psychology.desire])
            )
            fill(&character.fear, with: clean(psychology.fear))
            fill(&character.trauma, with: discovered(psychology.wound))
            fill(&character.falseBelief, with: discovered(psychology.belief))
            fill(&character.flaw, with: discovered(psychology.defense))
            fill(&character.arc, with: clean(psychology.contradiction))
            let currentCharacterState = [
                character.seedText,
                character.externalGoal,
                character.internalNeed,
                character.fear,
                character.trauma,
                character.falseBelief,
                character.flaw,
                character.arc
            ]
            if previousCharacterState != currentCharacterState {
                character.touch()
            }
            orderedIDs.append(character.id)
        }

        for (index, rawName) in snapshot.characters.enumerated() {
            let name = clean(rawName)
            guard !name.isEmpty else { continue }
            if let existing = existingByName[normalizedName(name)] {
                if !orderedIDs.contains(existing.id) { orderedIDs.append(existing.id) }
                continue
            }
            let character = StoryCharacter(
                name: name,
                role: project.characters.isEmpty && index == 0 ? .protagonist : .supporting,
                seedText: index == 0 ? clean(snapshot.crystal.characterInsight) : "",
                project: project
            )
            modelContext.insert(character)
            project.characters.append(character)
            existingByName[normalizedName(name)] = character
            orderedIDs.append(character.id)
        }
        return orderedIDs
    }

    private static func synchronizeArtifacts(
        in project: StoryProject,
        seed: StorySeed,
        snapshot: StoryCultivationSnapshot,
        modelContext: ModelContext
    ) {
        upsertArtifact(
            origin: sourceOrigin,
            title: "实验来源 · \(clean(seed.title))",
            kind: .source,
            humanInput: firstNonempty(snapshot.rawIdea, seed.sourceText),
            lockedIdeas: clean(seed.authorIntent),
            text: sourceArtifactText(seed: seed, snapshot: snapshot),
            sortIndex: 0,
            project: project,
            modelContext: modelContext
        )
        upsertArtifact(
            origin: crystalOrigin,
            title: "故事结晶 · 第 \(max(snapshot.round, 1)) 轮",
            kind: .inspiration,
            humanInput: clean(seed.authorIntent),
            lockedIdeas: snapshot.decisions.map(decisionSummary).joined(separator: "\n"),
            text: productionBriefText(seed: seed, snapshot: snapshot),
            sortIndex: 1,
            project: project,
            modelContext: modelContext
        )
        upsertArtifact(
            origin: structureOrigin,
            title: "实验选择与结构起点",
            kind: .structure,
            humanInput: snapshot.decisions.map(decisionSummary).joined(separator: "\n\n"),
            lockedIdeas: clean(snapshot.hiddenQuestion),
            text: structureStartingPointText(snapshot),
            sortIndex: 2,
            project: project,
            modelContext: modelContext
        )
    }

    private static func upsertArtifact(
        origin: String,
        title: String,
        kind: ProjectModuleKind,
        humanInput: String,
        lockedIdeas: String,
        text: String,
        sortIndex: Int,
        project: StoryProject,
        modelContext: ModelContext
    ) {
        if let artifact = project.artifacts.first(where: { $0.originLabel == origin }) {
            // integratedSnapshot 与 acceptedText 相同，说明内容仍由接力桥拥有。
            guard artifact.acceptedText.storyScienceTrimmed.isEmpty
                    || artifact.acceptedText == artifact.integratedSnapshot else { return }
            let previousArtifactState = [
                artifact.title,
                artifact.kindRawValue,
                artifact.statusRawValue,
                artifact.humanInput,
                artifact.lockedIdeas,
                artifact.workingText,
                artifact.acceptedText,
                artifact.integratedSnapshot,
                String(artifact.sortIndex)
            ]
            let nextArtifactState = [
                title,
                kind.rawValue,
                ProjectModuleStatus.integrated.rawValue,
                humanInput,
                lockedIdeas,
                text,
                text,
                text,
                String(sortIndex)
            ]
            guard previousArtifactState != nextArtifactState else { return }
            artifact.title = title
            artifact.kind = kind
            artifact.status = .integrated
            artifact.humanInput = humanInput
            artifact.lockedIdeas = lockedIdeas
            artifact.workingText = text
            artifact.acceptedText = text
            artifact.integratedSnapshot = text
            artifact.sortIndex = sortIndex
            artifact.updatedAt = .now
            return
        }
        let artifact = ProjectArtifact(
            title: title,
            kind: kind,
            status: .integrated,
            originLabel: origin,
            humanInput: humanInput,
            lockedIdeas: lockedIdeas,
            workingText: text,
            acceptedText: text,
            sortIndex: sortIndex,
            project: project
        )
        artifact.integratedSnapshot = text
        modelContext.insert(artifact)
        project.artifacts.append(artifact)
    }

    private static func synchronizeTask(
        in project: StoryProject,
        snapshot: StoryCultivationSnapshot,
        modelContext: ModelContext
    ) {
        let prompt = clean(snapshot.evaluation.nextStep)
        guard !prompt.isEmpty,
              !project.tasks.contains(where: { $0.prompt.storyScienceTrimmed == prompt }) else { return }
        let task = CreativeTask(
            title: "实验接力的下一步",
            prompt: prompt,
            constraintsText: snapshot.evaluation.gaps.joined(separator: "\n"),
            rationale: clean(snapshot.crystal.whyInteresting),
            difficulty: 1,
            status: .active,
            project: project
        )
        modelContext.insert(task)
        project.tasks.append(task)
    }

    private static func synchronizeNSIR(
        in project: StoryProject,
        seed: StorySeed,
        snapshot: StoryCultivationSnapshot,
        characterIDs: [UUID]
    ) {
        var workspace = project.nsirWorkspace
        var changed = false
        let crystalEnvelope = snapshot.crystal.compilerProposition.storyScienceTrimmed
        for index in workspace.propositions.indices
        where workspace.propositions[index].originalText.storyScienceTrimmed == crystalEnvelope
            && workspace.propositions[index].id != seed.id {
            workspace.propositions[index].status = .superseded
            changed = true
        }

        let coreText = firstNonempty(snapshot.crystal.conflict, snapshot.crystal.coreIdea)
        if !coreText.isEmpty,
           !workspace.propositions.contains(where: { $0.id == seed.id }) {
            var core = NarrativeCompilerEngine.formalize(
                kind: .choiceCost,
                text: coreText,
                characterIDs: Array(characterIDs.prefix(1)),
                revision: workspace.revision + 1
            )
            core.id = seed.id
            core.lockedFacts = [coreText]
            workspace.propositions.append(core)
            changed = true
        }

        let experimentByID = Dictionary(
            uniqueKeysWithValues: snapshot.experiments.map { ($0.id, $0) }
        )
        for decision in snapshot.decisions
        where !workspace.propositions.contains(where: { $0.id == decision.id }) {
            let text = decisionSummary(decision)
            guard !text.isEmpty else { continue }
            let kind = propositionKind(for: experimentByID[decision.experimentID]?.axis)
            var proposition = NarrativeCompilerEngine.formalize(
                kind: kind,
                text: text,
                characterIDs: kind == .foreshadowing ? Array(characterIDs.prefix(1)) : characterIDs,
                revision: workspace.revision + 1
            )
            proposition.id = decision.id
            workspace.propositions.append(proposition)
            changed = true
        }

        if !snapshot.crystal.theme.storyScienceTrimmed.isEmpty,
           !workspace.rules.contains(where: { $0.id == seed.id }) {
            workspace.rules.append(
                RuleCard(
                    id: seed.id,
                    title: "实验室主题假设",
                    ruleClass: .l5,
                    statement: clean(snapshot.crystal.theme),
                    modelScope: "全项目",
                    weight: 0.72,
                    source: "故事实验室 · 第 \(max(snapshot.round, 1)) 轮"
                )
            )
            changed = true
        }

        for psychology in snapshot.psychology {
            let characterID = characterIDs.first(where: { $0 == psychology.id })
                ?? project.characters.first(where: {
                    normalizedName($0.name) == normalizedName(psychology.character)
                })?.id
            guard let characterID else { continue }

            let desire = clean(psychology.desire)
            if !desire.isEmpty,
               !workspace.state.goals.contains(where: { $0.ownerID == characterID }) {
                workspace.state.goals.append(
                    Goal(
                        id: psychology.id,
                        ownerID: characterID,
                        desiredState: desire,
                        plan: clean(psychology.contradiction),
                        currentStrategy: discovered(psychology.defense),
                        priority: 0.76
                    )
                )
                changed = true
            }

            let belief = discovered(psychology.belief)
            if !belief.isEmpty,
               !workspace.state.beliefs.contains(where: {
                   $0.holderID == characterID && $0.subject == "人物信念"
               }) {
                workspace.state.beliefs.append(
                    Belief(
                        id: psychology.id,
                        holderID: characterID,
                        subject: "人物信念",
                        value: belief,
                        truthStatus: .belief,
                        confidence: 0.72
                    )
                )
                changed = true
            }

            if !workspace.state.identities.contains(where: { $0.characterID == characterID }) {
                workspace.state.identities.append(
                    IdentityState(
                        id: psychology.id,
                        characterID: characterID,
                        selfNarrative: belief,
                        defense: discovered(psychology.defense),
                        threatenedBy: clean(psychology.fear)
                    )
                )
                changed = true
            }

            if !workspace.state.appraisals.contains(where: { $0.characterID == characterID }) {
                workspace.state.appraisals.append(
                    AffectiveAppraisal(
                        id: psychology.id,
                        characterID: characterID,
                        label: psychology.need.rawValue,
                        valuedObject: desire,
                        threat: clean(psychology.fear),
                        entitlement: "待作者确认",
                        selfReportedMotive: desire,
                        actualMotive: clean(psychology.contradiction)
                    )
                )
                changed = true
            }
        }

        for atom in snapshot.atoms where atom.type == .worldRule {
            let key = "实验室世界规则.\(atom.id.uuidString)"
            if workspace.state.worldFacts[key] == nil {
                workspace.state.worldFacts[key] = clean(atom.content)
                changed = true
            }
        }

        if changed {
            workspace.revision = max(workspace.revision + 1, 1)
            workspace.updatedAt = .now
            project.nsirWorkspace = workspace
        }
    }

    private static func propositionKind(
        for axis: StoryExperimentAxis?
    ) -> CreativePropositionKind {
        switch axis {
        case .character: .foreshadowing
        case .conflict, .ending: .choiceCost
        case .world: .imageAction
        case .theme, .none: .emotion
        }
    }

    private static func productionBriefText(
        seed: StorySeed,
        snapshot: StoryCultivationSnapshot
    ) -> String {
        let crystal = snapshot.crystal
        return """
        【来自故事实验室】
        \(clean(seed.title)) · 第 \(max(snapshot.round, 1)) 轮 · \(snapshot.decisions.count) 次已确认实验

        【故事核心】
        \(fallback(crystal.coreIdea, "待作者确认"))

        【人物洞察】
        \(fallback(crystal.characterInsight, "待作者确认"))

        【不可两全的冲突】
        \(fallback(crystal.conflict, "待作者确认"))

        【主题假设】
        \(fallback(crystal.theme, "待作者确认"))

        【为什么值得追随】
        \(fallback(crystal.whyInteresting, "待作者补充"))

        【实验发现】
        \(fallback(snapshot.discovery, "本轮尚无补充发现"))

        【作者已经选择】
        \(fallback(experimentDecisionText(snapshot), "尚无已确认实验选择"))

        【生产下一步】
        \(fallback(snapshot.evaluation.nextStep, "继续确认一条可验证的创作决定"))
        """
    }

    private static func sourceArtifactText(
        seed: StorySeed,
        snapshot: StoryCultivationSnapshot
    ) -> String {
        let atoms = snapshot.atoms.map { "• \($0.type.rawValue)：\(clean($0.content))" }
            .joined(separator: "\n")
        return """
        【原始想法】
        \(fallback(firstNonempty(snapshot.rawIdea, seed.sourceText), "未记录"))

        【作者意图】
        \(fallback(seed.authorIntent, "未补充"))

        【故事原子】
        \(fallback(atoms, "本轮尚未拆出故事原子"))
        """
    }

    private static func structureStartingPointText(
        _ snapshot: StoryCultivationSnapshot
    ) -> String {
        let questions = snapshot.dramaticQuestions.map { "• \($0)" }.joined(separator: "\n")
        let decisions = snapshot.decisions.map(decisionSummary).joined(separator: "\n\n")
        return """
        【实验室传来的结构起点】
        隐藏问题：\(fallback(snapshot.hiddenQuestion, "待继续发现"))

        【戏剧问题】
        \(fallback(questions, "待作者确认"))

        【已确认实验】
        \(fallback(decisions, "尚无已确认实验选择"))

        【下一步】
        \(fallback(snapshot.evaluation.nextStep, "进入结构推演"))

        注：这里只保存实验依据，不代表结构已经由作者锁定。
        """
    }

    private static func experimentDecisionText(
        _ snapshot: StoryCultivationSnapshot
    ) -> String {
        snapshot.decisions.map(decisionSummary).joined(separator: "\n\n")
    }

    private static func decisionSummary(_ decision: StoryExperimentDecision) -> String {
        let selections = decision.selectedValues
            .sorted { $0.key < $1.key }
            .map { "\($0.key)：\($0.value)" }
            .joined(separator: "；")
        return joinedUnique([
            "\(clean(decision.experimentTitle))：\(selections)",
            clean(decision.authorObservation)
        ])
    }

    private static func characterBibleText(_ snapshot: StoryCultivationSnapshot) -> String {
        if !snapshot.psychology.isEmpty {
            return snapshot.psychology.map { psychology in
                """
                【\(clean(psychology.character))】
                欲望：\(fallback(psychology.desire, "待明确"))
                内在需要：\(psychology.need.rawValue)
                恐惧：\(fallback(psychology.fear, "待明确"))
                创伤：\(fallback(discovered(psychology.wound), "待发现"))
                信念：\(fallback(discovered(psychology.belief), "待发现"))
                防御：\(fallback(discovered(psychology.defense), "待发现"))
                内在矛盾：\(fallback(psychology.contradiction, "待明确"))
                """
            }.joined(separator: "\n\n")
        }
        return joinedUnique([snapshot.crystal.characterInsight] + snapshot.characters)
    }

    private static func bridgeFingerprint(
        seed: StorySeed,
        project: StoryProject
    ) -> String {
        var components = [
            seed.linkedProjectID?.uuidString ?? "",
            project.title,
            project.logline,
            project.sourceTitle,
            project.sourceText,
            project.sourceFacts,
            project.dramaticPromise,
            project.creativeDirectionText,
            project.storyPathText,
            project.structureText,
            project.worldText,
            project.themeText,
            project.characterBibleText,
            project.worldBibleText,
            project.themeBibleText,
            project.coreConflictText,
            project.storyBibleDigest,
            String(project.storyBibleRevision),
            project.storyBibleSyncNote,
            project.nsirWorkspaceData.base64EncodedString()
        ]

        for character in project.characters.sorted(by: {
            $0.id.uuidString < $1.id.uuidString
        }) {
            components.append(contentsOf: [
                character.id.uuidString,
                character.name,
                character.seedText,
                character.externalGoal,
                character.internalNeed,
                character.fear,
                character.trauma,
                character.falseBelief,
                character.flaw,
                character.arc
            ])
        }

        for artifact in project.artifacts.sorted(by: {
            $0.id.uuidString < $1.id.uuidString
        }) {
            components.append(contentsOf: [
                artifact.id.uuidString,
                artifact.originLabel,
                artifact.title,
                artifact.kindRawValue,
                artifact.statusRawValue,
                artifact.humanInput,
                artifact.lockedIdeas,
                artifact.workingText,
                artifact.acceptedText,
                artifact.integratedSnapshot,
                String(artifact.sortIndex)
            ])
        }

        for task in project.tasks.sorted(by: {
            $0.id.uuidString < $1.id.uuidString
        }) {
            components.append(contentsOf: [
                task.id.uuidString,
                task.title,
                task.prompt,
                task.constraintsText,
                task.rationale,
                task.statusRawValue
            ])
        }

        return components.joined(separator: "\u{1F}")
    }

    private static func fill(_ target: inout String, with candidate: String) {
        guard target.storyScienceTrimmed.isEmpty else { return }
        let value = clean(candidate)
        guard !value.isEmpty else { return }
        target = value
    }

    private static func joinedUnique(_ values: [String]) -> String {
        var seen = Set<String>()
        return values
            .map(clean)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: "\n")
    }

    private static func firstNonempty(_ values: String?...) -> String {
        values.compactMap { $0 }.map(clean).first { !$0.isEmpty } ?? ""
    }

    private static func fallback(_ value: String, _ fallback: String) -> String {
        let value = clean(value)
        return value.isEmpty ? fallback : value
    }

    private static func discovered(_ value: String) -> String {
        let value = clean(value)
        return value == "尚待发现" ? "" : value
    }

    private static func normalizedName(_ value: String) -> String {
        clean(value).lowercased()
    }

    private static func clean(_ value: String) -> String {
        value.simplifiedChinese.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
