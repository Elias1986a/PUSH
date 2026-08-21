import PUSHCore
import SwiftUI

struct ComparisonView: View {
    @State private var model = ComparisonModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if model.comparisons.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(model.comparisons) { comparison in
                            ComparisonCard(comparison: comparison,
                                           pending: comparison.id == model.comparisons.first?.id ? model.pending : 0,
                                           onDelete: { model.delete(comparison) })
                        }
                    }
                    .padding(18)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Engine comparison")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Spacer()
                if !model.comparisons.isEmpty {
                    Button("Clear") { model.clear() }
                }
            }

            HStack(spacing: 12) {
                Button {
                    model.toggleRecording()
                } label: {
                    Label(model.isRecording ? "Stop" : "Record",
                          systemImage: model.isRecording ? "stop.circle.fill" : "record.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isRecording ? .red : .accentColor)
                .controlSize(.large)
            }

            Text(model.status.isEmpty ? engineSummary : model.status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
    }

    /// Names the engines rather than counting them — "4 engines" hides which ones were
    /// skipped for want of a download.
    private var engineSummary: String {
        model.models.isEmpty
            ? "No engines available — download a model in PUSH first."
            : "Click Record, talk, click Stop. " + model.models.map(\.displayName).joined(separator: " · ")
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Say a sentence. Every engine transcribes that same recording.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ComparisonCard: View {
    let comparison: Comparison
    let pending: Int
    let onDelete: () -> Void

    /// Fastest first. Engines are measured in sequence, so arrival order says which ran
    /// first, not which is quicker — sorting is what makes the winner readable.
    private var ranked: [EngineRun] {
        comparison.runs.sorted { lhs, rhs in
            if lhs.failed != rhs.failed { return !lhs.failed }
            return lhs.seconds < rhs.seconds
        }
    }

    /// Whether the engines actually disagreed, ignoring formatting. Apple punctuates and
    /// Whisper doesn't; that's a formatting difference, not a recognition error.
    private var verdict: (String, Color)? {
        let texts = comparison.runs.filter { !$0.failed }.map(\.raw)
        guard texts.count > 1 else { return nil }
        if Set(texts).count == 1 { return ("identical", .green) }
        let normalized = Set(texts.map {
            $0.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
        })
        return normalized.count == 1 ? ("same words", .green) : ("words differ", .purple)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(comparison.date.formatted(date: .omitted, time: .standard))
                Text("· held \(comparison.audioSeconds, format: .number.precision(.fractionLength(1)))s")
                Spacer()
                if let verdict {
                    Text(verdict.0)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(verdict.1.opacity(0.16), in: Capsule())
                        .foregroundStyle(verdict.1)
                }
                Button(action: onDelete) {
                    Image(systemName: "trash").font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if pending > 0 {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("\(pending) engine\(pending == 1 ? "" : "s") still running…")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ForEach(Array(ranked.enumerated()), id: \.element.id) { index, run in
                EngineRow(run: run,
                          audioSeconds: comparison.audioSeconds,
                          isFastest: index == 0 && !run.failed && comparison.runs.count > 1)
            }

            if let cleanup = comparison.cleanup {
                Divider()
                CleanupRow(cleanup: cleanup)
            }
        }
        .padding(15)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct EngineRow: View {
    let run: EngineRun
    let audioSeconds: Double
    let isFastest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(run.engine + (isFastest ? " · fastest" : ""))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background((isFastest ? Color.green : Color.accentColor).opacity(0.16), in: Capsule())
                    .foregroundStyle(isFastest ? .green : Color.accentColor)
                Spacer()
                if !run.failed {
                    Text("\(run.seconds, format: .number.precision(.fractionLength(2)))s · \(Int(audioSeconds / max(run.seconds, 0.0001)))× realtime")
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(isFastest ? .green : .secondary)
                }
            }

            // Both stages, because the two failure modes look identical in the final text
            // alone: a word the model misheard, and a word the pipeline mangled.
            LabeledText(label: "raw", text: run.raw)
            if run.final != run.raw {
                LabeledText(label: "final", text: run.final, emphasised: true)
            } else if !run.failed {
                Text("final — unchanged by post-processing")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct CleanupRow: View {
    let cleanup: CleanupRun

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("Apple Intelligence cleanup")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.orange.opacity(0.16), in: Capsule())
                    .foregroundStyle(.orange)
                Spacer()
                Text("+\(cleanup.seconds, format: .number.precision(.fractionLength(2)))s")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.orange)
            }
            Text(cleanup.text)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            // The reason this isn't in PUSH: it is added to every utterance, on top of
            // whichever engine already ran.
            Text("on \(cleanup.basedOn)'s raw text — this cost is why it isn't an option in PUSH")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct LabeledText: View {
    let label: String
    let text: String
    var emphasised = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .frame(width: 32, alignment: .leading)
            Text(text.isEmpty ? "(nothing recognised)" : text)
                .font(.callout)
                .foregroundStyle(text.isEmpty ? .secondary : (emphasised ? .primary : .secondary))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
