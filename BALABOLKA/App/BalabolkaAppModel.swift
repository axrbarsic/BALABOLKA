import Foundation
import Observation

@MainActor
@Observable
final class BalabolkaAppModel {
    var composerText: String = """
    Балаболка, сделай голос живым, но не превращай текст в клоунаду.
    """
    var generationTitle: String = "Новая озвучка"
    var selectedPresetIDs: [ExpressivePreset.ID] = [.quiet]
    var isCombineModeEnabled = false
    var selectedCombineMode: ExpressiveCombineMode = .auto
    var selectedVoiceName: GeminiVoice = .sulafat
    var history: [GenerationRecord] = []
    var activeRecord: GenerationRecord?
    var errorMessage: String?
    var isGenerating = false
    var generationProgress: GenerationProgressState?

    @ObservationIgnored
    let settingsStore: SettingsStore

    @ObservationIgnored
    private let repository: LibraryRepository
    @ObservationIgnored
    private let generateUseCase: GenerateSpeechVideoUseCase
    @ObservationIgnored
    private let libraryUseCase: LibraryUseCase
    @ObservationIgnored
    private var historyTask: Task<Void, Never>?
    @ObservationIgnored
    private var generationTask: Task<Void, Never>?
    @ObservationIgnored
    private var syntheticProgressTask: Task<Void, Never>?

    init(
        settingsStore: SettingsStore,
        repository: LibraryRepository,
        generateUseCase: GenerateSpeechVideoUseCase,
        libraryUseCase: LibraryUseCase
    ) {
        self.settingsStore = settingsStore
        self.repository = repository
        self.generateUseCase = generateUseCase
        self.libraryUseCase = libraryUseCase
        selectedVoiceName = settingsStore.current.defaultVoice

        historyTask = Task {
            await loadHistory()
        }
    }

    convenience init() {
        let settingsStore = SettingsStore()
        let repository = LibraryRepository()
        let generateUseCase = GenerateSpeechVideoUseCase(
            proxyClient: ProxyClient(),
            exporter: SquareVideoExporter(),
            repository: repository
        )
        let libraryUseCase = LibraryUseCase(
            repository: repository,
            variantExporter: VideoVariantExporter(),
            photoLibrarySaver: PhotoLibraryVideoSaver()
        )
        self.init(
            settingsStore: settingsStore,
            repository: repository,
            generateUseCase: generateUseCase,
            libraryUseCase: libraryUseCase
        )
    }

    var selectedPresetID: ExpressivePreset.ID {
        get { selectedPresetIDs.first ?? .quiet }
        set { selectedPresetIDs = [newValue] }
    }

    var selectedPresets: [ExpressivePreset] {
        let resolvedIDs = selectedPresetIDs.isEmpty ? [ExpressivePreset.ID.quiet] : selectedPresetIDs
        return resolvedIDs.map(\.preset)
    }

    var selectedPreset: ExpressivePreset {
        selectedPresetID.preset
    }

    var selectedPresetSummary: String {
        selectedPresets.map(\.title).joined(separator: " + ")
    }

    var sourceTextCharacterCount: Int {
        composerText.count
    }

    var remainingSourceTextCharacters: Int {
        BalabolkaLimits.longFormSourceTextMaxCharacters - sourceTextCharacterCount
    }

    var isOverSourceTextLimit: Bool {
        remainingSourceTextCharacters < 0
    }

    var requiresLongFormMode: Bool {
        sourceTextCharacterCount > BalabolkaLimits.proxyRequestMaxCharacters
    }

    var estimatedChunkCount: Int {
        let normalizedText = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return 0 }
        return LongFormTextChunker.makeChunks(from: normalizedText).count
    }

    var canGenerate: Bool {
        !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isGenerating &&
        !isOverSourceTextLimit
    }

    func loadHistory() async {
        do {
            history = try await libraryUseCase.loadHistory()
            if activeRecord == nil {
                activeRecord = history.first
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(record: GenerationRecord) {
        activeRecord = record
        composerText = record.sourceText
        generationTitle = record.title
        selectedPresetIDs = record.presetIDs
        isCombineModeEnabled = record.presetIDs.count > 1
        selectedCombineMode = record.combineMode ?? .auto
        selectedVoiceName = record.voiceName
    }

    func setCombineMode(_ isEnabled: Bool) {
        isCombineModeEnabled = isEnabled
        if !isEnabled, let firstPresetID = selectedPresetIDs.first {
            selectedPresetIDs = [firstPresetID]
        } else if isEnabled, selectedPresetIDs.isEmpty {
            selectedPresetIDs = [.quiet]
        }
    }

    func togglePreset(_ presetID: ExpressivePreset.ID) {
        if !isCombineModeEnabled {
            selectedPresetIDs = [presetID]
            return
        }

        if let existingIndex = selectedPresetIDs.firstIndex(of: presetID) {
            if selectedPresetIDs.count > 1 {
                selectedPresetIDs.remove(at: existingIndex)
            }
            return
        }

        if selectedPresetIDs.count >= 3 {
            selectedPresetIDs.removeFirst()
        }

        selectedPresetIDs.append(presetID)
    }

    func resolvedVideoURL(for record: GenerationRecord, profile: VideoQualityProfile = .hq) -> URL? {
        let url = repository.videoURL(for: record, profile: profile)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func preparedVideoURL(for record: GenerationRecord, profile: VideoQualityProfile) async throws -> URL {
        try await libraryUseCase.preparedVideoURL(for: record, profile: profile)
    }

    func saveVideoToPhotos(for record: GenerationRecord, profile: VideoQualityProfile) async throws {
        try await libraryUseCase.saveVideoToPhotos(for: record, profile: profile)
    }

    func deleteHistory(at offsets: IndexSet) {
        let recordsToDelete = offsets.compactMap { history.indices.contains($0) ? history[$0] : nil }
        guard !recordsToDelete.isEmpty else { return }

        Task {
            do {
                try await libraryUseCase.delete(records: recordsToDelete)
                for index in offsets.sorted(by: >) {
                    history.remove(at: index)
                }

                if let activeRecord, recordsToDelete.contains(activeRecord) {
                    self.activeRecord = history.first
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func generate() {
        generationTask?.cancel()
        generationTask = Task {
            await generateFlow()
        }
    }

    private func generateFlow() async {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            errorMessage = BalabolkaError.emptyText.localizedDescription
            return
        }
        guard text.count <= BalabolkaLimits.longFormSourceTextMaxCharacters else {
            errorMessage = BalabolkaError.sourceTextTooLong(
                current: text.count,
                max: BalabolkaLimits.longFormSourceTextMaxCharacters
            ).localizedDescription
            return
        }

        isGenerating = true
        errorMessage = nil
        generationProgress = GenerationProgressState(
            stage: .preparingRequest,
            stageFraction: 0.22,
            statusMessage: "Запускаю задачу и проверяю локальные ограничения."
        )
        defer {
            isGenerating = false
            syntheticProgressTask?.cancel()
            syntheticProgressTask = nil
            generationProgress = nil
        }

        do {
            let normalizedTitle = generationTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Новая озвучка"
                : generationTitle
            startSyntheticProgress()

            let record = try await generateUseCase.execute(
                request: GenerateSpeechVideoRequest(
                    title: normalizedTitle,
                    text: text,
                    presetIDs: selectedPresetIDs,
                    combineMode: isCombineModeEnabled ? selectedCombineMode : nil,
                    voiceName: selectedVoiceName
                ),
                settings: settingsStore.current,
                progress: { [weak self] progress in
                    await self?.setGenerationProgress(progress)
                }
            )

            history.insert(record, at: 0)
            activeRecord = record
            settingsStore.current.defaultVoice = selectedVoiceName
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startSyntheticProgress() {
        syntheticProgressTask?.cancel()
        syntheticProgressTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 420_000_000)

                guard let progress = self.generationProgress else { continue }
                guard progress.stageFraction < progress.stage.syntheticCeiling else { continue }

                let increment: Double
                switch progress.stage {
                case .preparingRequest:
                    increment = 0.08
                case .synthesizingSpeech:
                    increment = 0.018
                case .processingAudio:
                    increment = 0.05
                case .renderingVideo:
                    increment = 0.024
                case .savingResult:
                    increment = 0.06
                }

                self.generationProgress = GenerationProgressState(
                    stage: progress.stage,
                    stageFraction: min(progress.stageFraction + increment, progress.stage.syntheticCeiling),
                    statusMessage: progress.statusMessage
                )
            }
        }
    }

    private func setGenerationProgress(_ progress: GenerationProgressState) {
        if let current = generationProgress, current.stage == progress.stage {
            generationProgress = GenerationProgressState(
                stage: progress.stage,
                stageFraction: max(current.stageFraction, progress.stageFraction),
                statusMessage: progress.statusMessage
            )
            return
        }

        generationProgress = progress
    }
}
