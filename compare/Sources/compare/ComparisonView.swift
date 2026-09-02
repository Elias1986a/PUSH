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

                // The benchmark's way in: `say` clips and corpus audio cover the
                // languages nobody here can dictate in or judge by ear.
                Button {
                    model.openFile()
                } label: {
                    Label("Open audio file…", systemImage: "waveform.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(model.isRecording)
            }

            Text(model.status.isEmpty ? engineSummary : model.status)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let loadedFile = model.loadedFile {
                HStack(spacing: 5) {
                    Image(systemName: "doc.badge.clock").font(.caption2)
                    Text(loadedFile)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(18)
    }

    /// Names the engines rather than counting them — "4 engines" hides which ones were
    /// skipped for want of a download.
    private var engineSummary: String {
        if model.models.isEmpty { return "No engines available — download a model in PUSH first." }
        let engines = model.models.map(\.displayName).joined(separator: " · ")
        // Wispr can only be compared on an utterance it also heard, and it listens to
        // its own hotkey — there is no way to trigger it from here.
        return WisprReader.isInstalled
            ? "Record and hold Wispr's hotkey while you talk, or open an audio file. " + engines + " · Wispr Flow"
            : "Record and talk, or open an audio file. " + engines
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Say a sentence, or open an audio file. Every engine transcribes that same audio.")
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
                // Named, never implied: a row from a file and a row from live
                // dictation would otherwise be indistinguishable afterwards.
                if let source = comparison.sourceFile {
                    Label(source, systemImage: "waveform")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("· \(comparison.audioSeconds, format: .number.precision(.fractionLength(1)))s")
                } else {
                    Text("· held \(comparison.audioSeconds, format: .number.precision(.fractionLength(1)))s")
                }
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

            if let wispr = comparison.wispr {
                Divider()
                WisprRow(wispr: wispr, audioSeconds: comparison.audioSeconds)
            } else if let absence = comparison.wisprAbsence {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "cloud.slash").font(.caption2)
                    Text(absence).font(.caption2)
                }
                .foregroundStyle(.tertiary)
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

            // Shown separately from the transcription time and never mixed into it: a
            // cold Neural Engine compile is minutes for a large model and seconds for a
            // small one, which would swamp the number this tool exists to compare.
            if run.loadSeconds > 1 {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath").font(.caption2)
                    Text("\(run.loadSeconds, format: .number.precision(.fractionLength(1)))s to load and warm up — one-time, not counted above")
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
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

private struct WisprRow: View {
    let wispr: WisprRun
    let audioSeconds: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("Wispr Flow · cloud")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.blue.opacity(0.16), in: Capsule())
                    .foregroundStyle(.blue)
                Spacer()
                Text("\(wispr.processingSeconds, format: .number.precision(.fractionLength(2)))s + \(wispr.networkSeconds, format: .number.precision(.fractionLength(2)))s network")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.blue)
            }

            LabeledText(label: "raw", text: wispr.raw)
            if wispr.formatted != wispr.raw {
                LabeledText(label: "final", text: wispr.formatted, emphasised: true)
            }

            // Their number is measured differently from ours and must be labelled so —
            // reading it as comparable to local compute time flatters us.
            Text("their own measurement, server-side; the engines above are local compute")
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
