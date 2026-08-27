import SwiftUI

struct DramaticLensView: View {
    let title: String
    let updates: [DramaticUpdateRecord]
    let projection: NarrativeProjectionRecord?
    let isAnalyzing: Bool
    let warnings: [String]
    let message: String
    let onAnalyze: () -> Void
    let onToggleLock: (DramaticUpdateRecord) -> Void

    private var current: [DramaticUpdateRecord] {
        updates.filter { $0.status != .stale }.sorted { $0.ordinal < $1.ordinal }
    }

    private var hasStaleEvidence: Bool {
        updates.contains { $0.status == .stale }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    definitionCard
                    if hasStaleEvidence && current.isEmpty && projection == nil {
                        staleCard
                    }
                    if let projection {
                        pacingCard(projection.metrics)
                        projectionCard(projection)
                    }
                    if current.isEmpty {
                        emptyCard
                    } else {
                        ForEach(current) { update in
                            updateCard(update)
                        }
                    }
                    ForEach(warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
            }
        }
        .background(ScreenplayEditorPalette.chrome.opacity(0.96))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                .foregroundStyle(StudioTheme.mint)
            VStack(alignment: .leading, spacing: 1) {
                Text("情境透镜")
                    .font(.system(size: 12.5, weight: .bold))
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onAnalyze) {
                if isAnalyzing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("分析", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isAnalyzing)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
    }

    private var definitionCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("底层判据")
                .font(.caption.weight(.bold))
                .foregroundStyle(StudioTheme.mint)
            Text("只有使 W / K / G / R / D / E 至少一项发生不可再分变化的行动、对白、沉默、感知或事件，才计为一次更新。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .semanticCard()
    }

    private var staleCard: some View {
        Label(
            "正文已经变化，旧更新不再参与节奏和向上归纳。请重新分析。",
            systemImage: "exclamationmark.arrow.trianglehead.counterclockwise"
        )
        .font(.caption)
        .foregroundStyle(.orange)
        .fixedSize(horizontal: false, vertical: true)
        .semanticCard()
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message.nonempty ?? "尚无已验证的情境更新")
                .font(.caption.weight(.semibold))
            Text("零更新也是有效诊断：它表示这段文字尚未让世界、认知、目标、关系、规范或观众理解发生变化。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .semanticCard()
    }

    private func pacingCard(_ metrics: SemanticPacingMetrics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("语义节奏")
                    .font(.caption.weight(.bold))
                Spacer()
                Text("\(metrics.effectiveUpdateCount) 次 / \(formatted(metrics.durationSeconds))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            metricRow("变化密度", metrics.updateDensity, ceiling: 3)
            metricRow("平均影响", metrics.averageImpact, ceiling: 1)
            metricRow("阻力强度", metrics.resistanceIntensity, ceiling: 1)
            metricRow("不可逆性", metrics.irreversibility, ceiling: 1)
            Text("节奏由有效变化量 ÷ 时间计算，不再按字数、句数或小节拍数量替代。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .semanticCard()
    }

    private func projectionCard(_ value: NarrativeProjectionRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("正文实现")
                .font(.caption.weight(.bold))
                .foregroundStyle(StudioTheme.mint)
            Text(value.summary)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            if !value.realizationGap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label(value.realizationGap, systemImage: "scope")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .semanticCard()
    }

    private func updateCard(_ update: DramaticUpdateRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%02d", update.ordinal + 1))
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(StudioTheme.mint)
                Text(update.actionVerb)
                    .font(.caption.weight(.bold))
                Text("· \(update.carrier.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onToggleLock(update)
                } label: {
                    Image(systemName: update.status == .locked ? "lock.fill" : "lock.open")
                }
                .buttonStyle(.plain)
                .help(update.status == .locked ? "解除作者锁定" : "锁定为作者确认的更新")
            }

            Text(update.summary)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 74), spacing: 5)],
                alignment: .leading,
                spacing: 5
            ) {
                ForEach(Array(Set(update.mutations.map(\.dimension))).sorted {
                    $0.rawValue < $1.rawValue
                }) { dimension in
                    Label(dimension.rawValue, systemImage: dimension.symbol)
                        .font(.system(size: 9.5, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(StudioTheme.mint.opacity(0.13), in: Capsule())
                }
            }

            ForEach(update.mutations) { mutation in
                VStack(alignment: .leading, spacing: 2) {
                    Text(mutation.subject)
                        .font(.caption2.weight(.semibold))
                    Text("\(mutation.beforeValue)  →  \(mutation.afterValue)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !update.sourceAnchor.quotedText.isEmpty {
                Text("“\(update.sourceAnchor.quotedText)”")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(4)
            }
        }
        .semanticCard()
    }

    private func metricRow(_ label: String, _ value: Double, ceiling: Double) -> some View {
        HStack(spacing: 7) {
            Text(label)
                .font(.caption2)
                .frame(width: 52, alignment: .leading)
            ProgressView(value: min(max(value / ceiling, 0), 1))
                .tint(StudioTheme.mint)
            Text(String(format: "%.2f", value))
                .font(.caption2.monospacedDigit())
                .frame(width: 32, alignment: .trailing)
        }
    }

    private func formatted(_ seconds: Double) -> String {
        ChineseScreenplayTiming.formattedDuration(seconds)
    }
}

private extension View {
    func semanticCard() -> some View {
        padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
    }
}

private extension String {
    nonisolated var nonempty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
