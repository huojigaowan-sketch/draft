#if DEBUG
import Foundation

/// Fast executable invariants for the semantic foundation. They run only in
/// Debug builds and intentionally avoid network/model calls.
@MainActor
enum DramaticSemanticInvariantChecks {
    static func run() {
        let ineffective = DramaticStateMutation(
            dimension: .world,
            subject: "门",
            beforeValue: "锁着",
            afterValue: "锁着"
        )
        precondition(!ineffective.isEffective, "Unchanged state must not count as drama.")

        let first = DramaticUpdateRecord(
            sceneIndex: 1,
            ordinal: 0,
            carrier: .action,
            actionVerb: "打开",
            summary: "她打开保险柜",
            mutations: [
                DramaticStateMutation(
                    dimension: .world,
                    subject: "保险柜",
                    beforeValue: "锁着",
                    afterValue: "打开"
                )
            ],
            sourceRevision: "debug-1",
            analysisModel: "invariant"
        )
        let second = DramaticUpdateRecord(
            sceneIndex: 1,
            ordinal: 1,
            carrier: .perception,
            actionVerb: "发现",
            summary: "她发现保险柜是空的",
            mutations: [
                DramaticStateMutation(
                    dimension: .knowledge,
                    subject: "保险柜内容",
                    holder: "她",
                    beforeValue: "相信证据在里面",
                    afterValue: "知道保险柜是空的",
                    truthStatus: .fact,
                    observerNames: ["她", "观众"]
                )
            ],
            sourceRevision: "debug-1",
            analysisModel: "invariant"
        )
        let reduction = DramaticStateReducer.reduce([second, first])
        precondition(reduction.exitState.count == 2, "Reducer must preserve both state dimensions.")
        precondition(reduction.conflicts.isEmpty, "A coherent update chain must not conflict.")

        let metrics = DramaticStateReducer.metrics(
            for: [first, second],
            durationSeconds: 60
        )
        precondition(metrics.effectiveUpdateCount == 2, "Pacing must count effective updates only.")
        precondition(metrics.updateDensity > 0, "Effective changes must produce non-zero density.")

        let source = "内. 档案室 - 夜\n\n她打开保险柜。\n\n里面是空的。"
        let anchor = DramaticAnchorResolver.anchor(
            quotedText: "她打开保险柜。",
            sceneText: source,
            sceneRecordID: nil,
            sceneContractID: nil
        )
        precondition(anchor.localUTF16Length > 1, "Exact source evidence must remain externally anchored.")
    }
}
#endif
