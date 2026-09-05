import SwiftUI
import AppKit
import PUSHCore

// MARK: - Models

struct ModelsSettingsView: View {
    @EnvironmentObject var appState: AppState

    /// Snapshot of the filesystem check for every model — kept in @State so
    /// download/delete actually refresh the view, and so the list does not stat
    /// four directories on every render pass.
    @State private var downloaded: Set<AppState.WhisperModel> = []
    @State private var downloadingModel: AppState.WhisperModel?
    @State private var downloadProgress: Double = 0
    @State private var downloadStatus: String = ""
    @State private var downloadError: String?
    @State private var appleStatus: AppleSpeechAssetStatus = .unknown
    @State private var storageBytes: Double = 0

    /// Measured on-disk size per model, filled by `refreshStorage`. Empty until
    /// the first walk finishes, which is why `metaLine` falls back to the
    /// download estimate rather than rendering a confident "Zero KB".
    @State private var modelBytes: [AppState.WhisperModel: Double] = [:]

    /// Measured size of each Nemotron vocab build, keyed by variant.
    @State private var buildBytes: [String: Double] = [:]

    var body: some View {
        Form {
            Section("Speech model") {
                ForEach(AppState.WhisperModel.selectable) { model in
                    modelRow(model)
                }

                Text("Every model runs on this Mac. Nothing you say is sent anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Storage") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Downloaded models")
                        Text(storageBytes > 0
                             ? "\(Self.format(bytes: storageBytes)) in Application Support"
                             : "Nothing downloaded yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Show in Finder") {
                        NSWorkspace.shared.selectFile(
                            nil,
                            inFileViewerRootedAtPath: ParakeetUnifiedEngine.modelDirectory
                                .deletingLastPathComponent().path
                        )
                    }
                    .disabled(storageBytes == 0)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshDownloaded()
            refreshAppleStatus()
            refreshStorage()
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func modelRow(_ model: AppState.WhisperModel) -> some View {
        let isSelected = appState.selectedWhisperModel == model

        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(model.shortName)
                        .fontWeight(.medium)
                    if let badge = model.badge {
                        Text(badge)
                            .font(.caption2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(model.modelDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(metaLine(for: model))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(buildBreakdown(for: model), id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 10)
                }

                if Self.showsLanguagePicker(for: model, selectedModel: appState.selectedWhisperModel) {
                    DictationLanguagePicker(
                        model: model,
                        onModelsChanged: {
                            refreshDownloaded()
                            refreshStorage()
                            // Apple installs its assets per locale, so the
                            // answer to "is this installed" changes with the
                            // language. Without this the row keeps showing the
                            // status of whichever locale was current on appear.
                            refreshAppleStatus()
                        },
                        reload: { willDownload in
                            await reloadForLanguage(model, willDownload: willDownload)
                        })
                    .padding(.top, 2)
                }

                if downloadingModel == model {
                    if downloadProgress > 0 {
                        ProgressView(value: downloadProgress, total: 1.0)
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                    Text(downloadStatus.isEmpty ? "Downloading…" : downloadStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isSelected, let downloadError {
                    Text(downloadError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer(minLength: 8)

            trailing(for: model)
                .padding(.top, 2)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { select(model) }
    }

    @ViewBuilder
    private func trailing(for model: AppState.WhisperModel) -> some View {
        if downloadingModel == model {
            EmptyView()
        } else if showsActiveBadge(for: model) {
            // The engine that is loaded says so, whichever engine it is. Apple
            // Speech used to be answered by a short-circuit above this check, so
            // the one engine needing no download was also the only one that
            // never said "Active": it sat reading "Installs on first use" while
            // it was loaded and transcribing, which reads as "not working yet".
            statusBadge(icon: "checkmark.circle.fill", color: .green, text: "Active")
        } else if model == .appleSpeech {
            // No download button: these assets belong to the OS. A progress bar
            // we neither drive nor can cancel would be a fiction, so this
            // reports the system's own state instead.
            statusBadge(icon: appleStatusIcon, color: appleStatusColor, text: appleStatusLabel)
        } else if downloaded.contains(model) {
            Button("Delete") { deleteModel(model) }
                .foregroundStyle(.red)
        } else {
            Button("Download") { downloadModel(model) }
                .disabled(downloadingModel != nil)
        }
    }

    /// Whether `model` is the engine currently serving dictation.
    ///
    /// Apple Speech has no files of ours, so `downloaded` is the wrong question
    /// for it — but "still installing" is worth saying in preference to
    /// "Active", since that install is the one thing that would stop it working.
    private func showsActiveBadge(for model: AppState.WhisperModel) -> Bool {
        guard model == appState.activeModel else { return false }
        if model == .appleSpeech { return appleStatus != .installing }
        return downloaded.contains(model)
    }

    private func statusBadge(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    /// One line per Nemotron build actually on disk, shown only when there are
    /// two of them.
    ///
    /// Nemotron ships one ~600 MB build per language group, so picking Arabic
    /// while holding the Latin build silently doubles what the engine occupies.
    /// A lone "1.28 GB" hides that a second download ever happened — and hides
    /// that Delete reclaims both. With one build the total already says it, and
    /// a sub-line repeating itself is noise.
    private func buildBreakdown(for model: AppState.WhisperModel) -> [String] {
        guard model == .nemotronMultilingual else { return [] }
        let present = NemotronMultilingualEngine.buildVariants.compactMap { variant in
            (buildBytes[variant] ?? 0) > 0 ? (variant, buildBytes[variant]!) : nil
        }
        guard present.count > 1 else { return [] }
        return present.map { "\(Self.buildName($0.0)) · \(Self.format(bytes: $0.1))" }
    }

    /// Named by what the build can transcribe, not by the language that
    /// happened to pull it: the second build serves Arabic, Chinese, Japanese,
    /// Russian and every other non-Latin script, so calling it "Arabic" would
    /// suggest deleting it costs only Arabic.
    private static func buildName(_ variant: String) -> String {
        variant == "latin" ? "Latin-script languages" : "All other languages"
    }

    private func metaLine(for model: AppState.WhisperModel) -> String {
        if model == .appleSpeech {
            return "No download · managed by macOS"
        }
        let isDownloaded = downloaded.contains(model)
        let state = isDownloaded ? "on this Mac" : "not downloaded"

        // Once it is on disk, say what is actually there. `downloadSizeLabel` is
        // one build's download, and Nemotron ships one per language group: a
        // user who has picked Arabic as well as Spanish has two, so the constant
        // described a 1.2 GB row as 600 MB. Before the download that constant is
        // still the right number — it is what the user is about to fetch — and
        // it also stands in until the first size walk finishes.
        let measured = isDownloaded
            ? modelBytes[model].flatMap { $0 > 0 ? Self.format(bytes: $0) : nil }
            : nil
        let size = measured ?? model.downloadSizeLabel
        // Trimming the size out of `modelDescription` also removed the only
        // place that said Streaming and Unified are one download. Deleting
        // either removes both, so the row has to admit it.
        if model == .parakeetStreaming || model == .parakeetUnified {
            let other: AppState.WhisperModel = model == .parakeetStreaming ? .parakeetUnified : .parakeetStreaming
            if AppState.WhisperModel.selectable.contains(other) {
                return "\(size) · shared with \(other.shortName) · \(state)"
            }
        }
        return "\(size) · \(state)"
    }

    // MARK: Language

    /// Whether `model`'s row should carry a dictation-language picker.
    ///
    /// Two conditions, and both earn their place. A picker under an engine that
    /// cannot take a language is a lie — the Parakeet exports are English-only
    /// by construction, and offering a choice there would be a control that
    /// silently does nothing. A picker under *every* row, meanwhile, is noise:
    /// the list is five rows of model comparison, and four popup buttons the
    /// user is not currently using bury the comparison they came to read.
    ///
    /// Keyed on `selectedWhisperModel` (the preference the row's radio button
    /// draws) rather than `activeModel` (what is loaded right now), so the
    /// picker appears under the row that looks chosen. They differ while a newly
    /// picked model is still downloading — precisely when the user is most
    /// likely to want to set its language.
    ///
    /// Internal rather than private so the tests can pin this decision; it is
    /// not part of any view's `body`, which is why it can be pinned at all.
    static func showsLanguagePicker(
        for model: AppState.WhisperModel,
        selectedModel: AppState.WhisperModel
    ) -> Bool {
        model == selectedModel && model.supportsLanguageSelection
    }

    // MARK: Apple asset status

    private var appleStatusLabel: String {
        switch appleStatus {
        case .unknown: return "Checking…"
        case .installed: return "Ready"
        case .willInstall: return "Installs on first use"
        case .installing: return "Installing…"
        case .unsupported: return "Not available"
        }
    }

    private var appleStatusIcon: String {
        switch appleStatus {
        case .installed: return "checkmark.circle.fill"
        case .installing: return "arrow.down.circle"
        case .willInstall: return "icloud.and.arrow.down"
        case .unknown: return "ellipsis.circle"
        case .unsupported: return "exclamationmark.triangle"
        }
    }

    private var appleStatusColor: Color {
        switch appleStatus {
        case .installed: return .green
        case .unsupported: return .orange
        case .unknown, .willInstall, .installing: return .secondary
        }
    }

    /// Ask the system what state its speech assets are in. Only meaningful for
    /// `.appleSpeech`, which `selectable` already filters out below macOS 26.
    private func refreshAppleStatus() {
        guard AppState.WhisperModel.selectable.contains(.appleSpeech) else { return }
        guard #available(macOS 26, *) else {
            appleStatus = .unsupported
            return
        }
        appleStatus = .unknown
        Task {
            let status = await AppleSpeechEngine.installStatus()
            await MainActor.run {
                switch status {
                case .installed: appleStatus = .installed
                case .downloading: appleStatus = .installing
                case .supported: appleStatus = .willInstall
                case .unsupported: appleStatus = .unsupported
                @unknown default: appleStatus = .unknown
                }
            }
        }
    }

    // MARK: Selection

    /// Picking a row records the preference; the swap only happens once the
    /// model is actually on disk, so dictation keeps working meanwhile.
    private func select(_ model: AppState.WhisperModel) {
        guard appState.selectedWhisperModel != model else { return }
        downloadError = nil
        appState.selectedWhisperModel = model
        if downloaded.contains(model) || model == .appleSpeech {
            activate(model)
        }
    }

    private func activate(_ model: AppState.WhisperModel) {
        Task {
            do {
                try await ModelLoader.activate(model)
                // Cleared on success, not merely when the next attempt starts.
                // A failed load followed by a successful retry otherwise leaves
                // the red text sitting under a row that is simultaneously
                // showing the green "Active" badge — the state the first
                // multilingual download actually reached, where a transient
                // mid-download failure was still on screen minutes after the
                // model had loaded and was transcribing fine.
                downloadError = nil
            } catch {
                downloadError = error.localizedDescription
            }
        }
    }

    /// Runs a language change with the row's own progress bar and error line.
    ///
    /// Choosing a language can fetch a second ~600 MB build with nobody having
    /// pressed Download — picking Arabic while the latin build is resident does
    /// exactly that — and until this existed the app just went quiet for the
    /// length of the transfer. No bar, no percentage, and on failure nothing at
    /// all, because the reload swallowed its own error. Measured at 43 seconds
    /// of silence on a fast connection; minutes on a slow one, which reads as a
    /// hung app rather than a download.
    ///
    /// Progress is measured against a baseline taken before the transfer starts,
    /// not against the folder's absolute size: the folder already holds the
    /// build being switched away from, so an absolute measure would sit at 100%
    /// from the first sample and never move.
    private func reloadForLanguage(_ model: AppState.WhisperModel, willDownload: Bool) async {
        downloadError = nil

        // A same-build switch is a prompt swap. Nothing to show, but a failure
        // still has to surface rather than disappear.
        guard willDownload, let folder = Self.folder(for: model) else {
            do {
                try await ModelLoader.reloadForLanguageChange(model)
            } catch {
                downloadError = error.localizedDescription
            }
            return
        }

        let language = appState.language(for: model).displayName
        downloadingModel = model
        downloadProgress = 0
        downloadStatus = "Downloading \(language)…"

        let expected = Self.expectedSize(of: model)
        let baseline = await Task.detached(priority: .utility) {
            Self.directorySize(at: folder)
        }.value

        let pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let onDisk = await Task.detached(priority: .utility) {
                    Self.directorySize(at: folder)
                }.value
                let progress = min(max(0, onDisk - baseline) / expected, 0.95)
                await MainActor.run {
                    downloadProgress = progress
                    if progress > 0.01 {
                        downloadStatus = "Downloading \(language)… \(Int(progress * 100))%"
                    }
                }
            }
        }

        do {
            try await ModelLoader.reloadForLanguageChange(model)
            pollTask.cancel()
            downloadProgress = 1.0
            downloadStatus = "Complete!"
        } catch {
            pollTask.cancel()
            downloadError = error.localizedDescription
        }
        downloadingModel = nil
    }

    // MARK: Filesystem

    private nonisolated static func folder(for model: AppState.WhisperModel) -> URL? {
        switch model.engineType {
        case .parakeet: return ParakeetEngine.modelDirectory
        case .parakeetUnified: return ParakeetUnifiedEngine.modelDirectory
        case .parakeetStreaming: return ParakeetStreamingEngine.modelDirectory
        // The repo root, covering both vocab builds — a user who has dictated in
        // two language groups has two of them down.
        case .nemotronMultilingual: return NemotronMultilingualEngine.modelDirectory
        case .appleSpeech: return nil  // the OS owns these; nothing of ours to show
        }
    }

    private static func checkDownloaded(_ model: AppState.WhisperModel) -> Bool {
        switch model.engineType {
        case .parakeet: return ParakeetEngine.isModelDownloaded()
        case .parakeetUnified: return ParakeetUnifiedEngine.isModelDownloaded()
        case .parakeetStreaming: return ParakeetStreamingEngine.isModelDownloaded()
        case .nemotronMultilingual: return NemotronMultilingualEngine.isModelDownloaded()
        case .appleSpeech:
            // Nothing for us to download — the system installs on demand.
            return true
        }
    }

    private func refreshDownloaded() {
        downloaded = Set(
            AppState.WhisperModel.selectable.filter { $0 != .appleSpeech && Self.checkDownloaded($0) }
        )
    }

    /// Walks the model directories, so it runs off the main thread — blocking it
    /// is how this app loses its event tap.
    private func refreshStorage() {
        // Deduplicated: Parakeet Streaming and Parakeet Unified are the same
        // weights in the same directory, so summing per-model counted 1.21 GB
        // twice and reported 2.41.
        let foldersByModel: [AppState.WhisperModel: URL] = Dictionary(
            uniqueKeysWithValues: AppState.WhisperModel.selectable.compactMap { model in
                Self.folder(for: model).map { (model, $0.standardizedFileURL) }
            })
        let builds = NemotronMultilingualEngine.buildVariants.map {
            ($0, NemotronMultilingualEngine.buildDirectory($0).standardizedFileURL)
        }
        let folders = Set(foldersByModel.values).union(builds.map(\.1))
        Task {
            // One walk per distinct folder, reused for both the total and the
            // per-row figure — the rows and the Storage line must not be able
            // to disagree about the same bytes.
            let sizes = await Task.detached(priority: .utility) {
                Dictionary(uniqueKeysWithValues: folders.map { ($0, Self.directorySize(at: $0)) })
            }.value
            await MainActor.run {
                // Summed over the model folders only: the build directories
                // live inside the Nemotron folder, so counting both would
                // report its bytes twice.
                storageBytes = Set(foldersByModel.values).compactMap { sizes[$0] }.reduce(0, +)
                modelBytes = foldersByModel.compactMapValues { sizes[$0] }
                buildBytes = Dictionary(uniqueKeysWithValues:
                    builds.compactMap { variant, url in sizes[url].map { (variant, $0) } })
            }
        }
    }

    private static func format(bytes: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// Rough on-disk sizes used to derive download progress (engines don't report it).
    private static func expectedSize(of model: AppState.WhisperModel) -> Double {
        switch model {
        case .parakeetV2: return 400_000_000
        case .parakeetUnified, .parakeetStreaming, .nemotronMultilingual: return 600_000_000
        case .appleSpeech: return 0  // never downloaded through us
        }
    }

    private nonisolated static func directorySize(at url: URL) -> Double {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Double = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Double(size)
            }
        }
        return total
    }

    // MARK: Download / delete

    private func downloadModel(_ model: AppState.WhisperModel) {
        guard let folder = Self.folder(for: model) else { return }
        // Downloading is also choosing: nobody fetches 600 MB they don't intend
        // to use.
        appState.selectedWhisperModel = model
        downloadingModel = model
        downloadProgress = 0
        downloadStatus = "Downloading…"
        downloadError = nil

        Task {
            // Poll the download directory for coarse progress.
            let expected = Self.expectedSize(of: model)
            let pollTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    let onDisk = await Task.detached(priority: .utility) {
                        Self.directorySize(at: folder)
                    }.value
                    let progress = min(onDisk / expected, 0.95)
                    await MainActor.run {
                        downloadProgress = progress
                        if progress > 0.01 {
                            downloadStatus = "Downloading… \(Int(progress * 100))%"
                        }
                    }
                }
            }
            do {
                // Engines download on load; activate also swaps it in and warms up.
                try await ModelLoader.activate(model)
                pollTask.cancel()
                downloadProgress = 1.0
                downloadStatus = "Complete!"
            } catch {
                pollTask.cancel()
                downloadError = error.localizedDescription
            }
            downloadingModel = nil
            refreshDownloaded()
            refreshStorage()
        }
    }

    private func deleteModel(_ model: AppState.WhisperModel) {
        guard let folder = Self.folder(for: model) else { return }
        downloadError = nil

        do {
            if FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.removeItem(at: folder)
            }
            // Compare FOLDERS, not models. Streaming and Unified share one
            // directory, so deleting Streaming while Unified is serving pulls
            // the active model's files out from under it — and `model ==
            // activeModel` is false in exactly that case.
            if let activeFolder = Self.folder(for: appState.activeModel),
               activeFolder.standardizedFileURL == folder.standardizedFileURL {
                Task { await ModelLoader.deactivate() }
            }
        } catch {
            downloadError = "Failed to delete: \(error.localizedDescription)"
        }
        refreshDownloaded()
        refreshStorage()
    }
}

enum AppleSpeechAssetStatus {
    case unknown
    case installed
    case willInstall
    case installing
    case unsupported
}
