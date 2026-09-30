import AppKit
import PUSHCore
import SwiftUI

struct ComparisonView: View {
    @State private var model = ComparisonModel()
    /// The tool's own preference, not PUSH's: this app has its own defaults domain.
    @AppStorage("resolveSelfCorrections") private var resolveSelfCorrections = true
    /// On by default here although it is off in PUSH: the passage says "like" on
    /// purpose, and a benchmark should show everything the cleanup can do.
    @AppStorage("californiaMode") private var californiaMode = true

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
                                           resolveSelfCorrections: resolveSelfCorrections,
                                           californiaMode: californiaMode,
                                           onDelete: { model.delete(comparison) })
                        }
                    }
                    .padding(18)
                }
            }
        }
    }

    /// The fixed passage, on screen while recording so every run says the same words.
    ///
    /// It sits in the header rather than behind a disclosure: a script you have to go
    /// looking for is a script that gets paraphrased, and a paraphrased run is not
    /// comparable to the one before it. Emphasised while recording so it stays
    /// readable at arm's length from the microphone.
    private var benchmarkScript: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "text.quote")
                    .font(.caption2)
                Text("Read this — the same words every run")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(BenchmarkScript.text, forType: .string)
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            .foregroundStyle(.secondary)

            Text(BenchmarkScript.text)
                .font(.system(size: 15, design: .serif))
                .fontWeight(model.isRecording ? .semibold : .regular)
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text(BenchmarkScript.exercises.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(model.isRecording ? 0.16 : 0.07))
        )
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

            benchmarkScript

            // On by default, as in PUSH since 8.1.3; off shows what the setting buys.
            // Applied to every row, past ones included,
            // because it is recomputed from the stored raw text rather than re-transcribed.
            Toggle("Resolve spoken self-corrections (\"15.2, I mean 1.52\" → \"1.52\")",
                   isOn: $resolveSelfCorrections)
                .font(.caption)
            Toggle("California mode (\"that's like the only slot\" → \"that's the only slot\")",
                   isOn: $californiaMode)
                .font(.caption)

            SeriesSummary(comparisons: model.comparisons)

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
    let resolveSelfCorrections: Bool
    let californiaMode: Bool
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
                if let version = comparison.scriptVersion {
                    Text("· script v\(version)")
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
                          resolveSelfCorrections: resolveSelfCorrections,
                          californiaMode: californiaMode,
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
    let resolveSelfCorrections: Bool
    let californiaMode: Bool
    let isFastest: Bool

    /// What PUSH would paste with the settings as toggled here. Same order as the
    /// app: resolve first, while the "I mean" commas are intact, then California
    /// mode, then format. Rows whose engine is no longer known keep the text they
    /// were saved with.
    private var final: String {
        guard !run.failed,
              let model = WhisperModel.allCases.first(where: { $0.displayName == run.engine })
        else { return run.final }
        var text = run.raw
        if resolveSelfCorrections { text = TranscriptionPipeline.resolveSelfCorrections(text) }
        if californiaMode { text = TranscriptionPipeline.removeCasualLike(text) }
        return TranscriptionPipeline.postProcess(text, hasNativePunctuation: model.hasNativePunctuation)
    }

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
            if final != run.raw {
                LabeledText(label: "final", text: final, emphasised: true)
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

/// Medians over every live reading of the current script — the figure that gets
/// published, and how far the series is from `BenchmarkScript.targetRuns`.
private struct SeriesSummary: View {
    let comparisons: [Comparison]

    private var series: [Comparison] {
        comparisons.filter { $0.sourceFile == nil && $0.scriptVersion == BenchmarkScript.version }
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    private static func seconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2))) + "s"
    }

    /// One line per engine, in the order engines first appear; failed runs don't count.
    private var lines: [String] {
        var names: [String] = []
        var runs: [String: [(seconds: Double, rate: Double)]] = [:]
        for comparison in series {
            for run in comparison.runs where !run.failed {
                if runs[run.engine] == nil { names.append(run.engine) }
                runs[run.engine, default: []].append(
                    (run.seconds, comparison.audioSeconds / max(run.seconds, 0.0001)))
            }
        }
        var lines = names.compactMap { name -> String? in
            let values = runs[name] ?? []
            guard let secs = Self.median(values.map(\.seconds)),
                  let rate = Self.median(values.map(\.rate)) else { return nil }
            return "\(name): \(Self.seconds(secs)) · \(Int(rate))× (\(values.count))"
        }
        let wispr = series.compactMap(\.wispr)
        if let processing = Self.median(wispr.map(\.processingSeconds)),
           let network = Self.median(wispr.map(\.networkSeconds)) {
            lines.append("Wispr Flow: \(Self.seconds(processing)) + \(Self.seconds(network)) network (\(wispr.count))")
        }
        return lines
    }

    var body: some View {
        if !series.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("Script v\(BenchmarkScript.version) · \(series.count) of \(BenchmarkScript.targetRuns) readings · medians")
                    .font(.caption.weight(.semibold))
                ForEach(lines, id: \.self) { Text($0) }
                    .font(.caption).monospacedDigit()
            }
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
    }
}
