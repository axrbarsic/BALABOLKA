import Foundation

struct GenerateSpeechVideoRequest: Sendable {
    let title: String
    let text: String
    let presetIDs: [ExpressivePreset.ID]
    let combineMode: ExpressiveCombineMode?
    let voiceName: GeminiVoice
}

private struct PreparedSynthesisChunk: Sendable {
    let index: Int
    let audioURL: URL
    let preparedTranscript: String
    let voiceName: String
    let sampleRate: Int
    let modelName: String
}

private struct PreparedLongFormAudio: Sendable {
    let audioData: Data
    let audioURL: URL
    let preparedTranscript: String
    let voiceName: String
    let sampleRate: Int
    let modelName: String
}

private struct ChunkSynthesisDirective: Sendable {
    let presets: [ExpressivePreset]
    let combineMode: ExpressiveCombineMode?
}

actor GenerateSpeechVideoUseCase {
    private let proxyClient: ProxyClient
    private let exporter: SquareVideoExporter
    private let repository: LibraryRepository

    init(
        proxyClient: ProxyClient,
        exporter: SquareVideoExporter,
        repository: LibraryRepository
    ) {
        self.proxyClient = proxyClient
        self.exporter = exporter
        self.repository = repository
    }

    func execute(
        request: GenerateSpeechVideoRequest,
        settings: BalabolkaSettings,
        progress: (@Sendable (GenerationProgressState) async -> Void)? = nil
    ) async throws -> GenerationRecord {
        let resolvedPresetIDs = request.presetIDs.isEmpty ? [ExpressivePreset.ID.quiet] : request.presetIDs
        let resolvedPresets = resolvedPresetIDs.map(\.preset)
        let textChunks = LongFormTextChunker.makeChunks(from: request.text)

        await progress?(GenerationProgressState(
            stage: .preparingRequest,
            stageFraction: 0.45,
            statusMessage: preparingStatus(presetCount: resolvedPresets.count, chunkCount: textChunks.count)
        ))
        await progress?(GenerationProgressState(
            stage: .synthesizingSpeech,
            stageFraction: 0.02,
            statusMessage: synthesisStatus(currentChunk: 0, totalChunks: textChunks.count)
        ))

        let preparedAudio = try await synthesizeLongFormAudio(
            title: request.title,
            textChunks: textChunks,
            presets: resolvedPresets,
            combineMode: request.combineMode,
            voiceName: request.voiceName,
            settings: settings,
            progress: progress
        )
        defer {
            try? FileManager.default.removeItem(at: preparedAudio.audioURL)
        }
        await progress?(GenerationProgressState(
            stage: .processingAudio,
            stageFraction: 0.12,
            statusMessage: "Проверяю WAV-контейнер и готовлю анализ амплитуды."
        ))
        let envelope = try WaveformAnalyzer.analyze(audioURL: preparedAudio.audioURL)
        await progress?(GenerationProgressState(
            stage: .processingAudio,
            stageFraction: 1,
            statusMessage: "Амплитуда готова. Запускаю рендер квадратного видео."
        ))
        await progress?(GenerationProgressState(
            stage: .renderingVideo,
            stageFraction: 0.02,
            statusMessage: "Собираю холст 720×720 и подготавливаю анимацию."
        ))
        let videoURL = try await exporter.export(audioURL: preparedAudio.audioURL, envelope: envelope, profile: .hq) { renderFraction in
            await progress?(
                GenerationProgressState(
                    stage: .renderingVideo,
                    stageFraction: renderFraction,
                    statusMessage: self.renderingStatus(renderFraction: renderFraction)
                )
            )
        }
        defer {
            try? FileManager.default.removeItem(at: videoURL)
        }
        await progress?(GenerationProgressState(
            stage: .savingResult,
            stageFraction: 0.2,
            statusMessage: "Переношу видео и аудио в историю генераций."
        ))

        let record = try await repository.persistGeneration(
            title: request.title,
            sourceText: request.text,
            preparedTranscript: preparedAudio.preparedTranscript,
            presetIDs: resolvedPresetIDs,
            combineMode: request.combineMode,
            voiceName: GeminiVoice(rawValue: preparedAudio.voiceName) ?? request.voiceName,
            sampleRate: preparedAudio.sampleRate,
            modelName: preparedAudio.modelName,
            waveformEnvelope: envelope.samples,
            audioData: preparedAudio.audioData,
            renderedVideoURL: videoURL,
            duration: envelope.duration
        )
        await progress?(GenerationProgressState(
            stage: .savingResult,
            stageFraction: 1,
            statusMessage: "Готово. Видео сохранено локально."
        ))
        return record
    }

    private func synthesizeLongFormAudio(
        title: String,
        textChunks: [LongFormTextChunk],
        presets: [ExpressivePreset],
        combineMode: ExpressiveCombineMode?,
        voiceName: GeminiVoice,
        settings: BalabolkaSettings,
        progress: (@Sendable (GenerationProgressState) async -> Void)?
    ) async throws -> PreparedLongFormAudio {
        let chunks = textChunks.isEmpty ? [LongFormTextChunk(index: 0, text: "")] : textChunks
        var preparedChunks: [PreparedSynthesisChunk] = []
        preparedChunks.reserveCapacity(chunks.count)
        var transientAudioURLs: [URL] = []
        var retainedAudioURL: URL?

        defer {
            for audioURL in transientAudioURLs where audioURL != retainedAudioURL {
                try? FileManager.default.removeItem(at: audioURL)
            }
        }

        for (position, chunk) in chunks.enumerated() {
            let directive = synthesisDirective(
                forChunkAt: position,
                totalChunks: chunks.count,
                presets: presets,
                combineMode: combineMode
            )
            let response = try await proxyClient.synthesize(
                title: chunkTitle(baseTitle: title, position: position, total: chunks.count),
                text: chunk.text,
                presets: directive.presets,
                combineMode: directive.combineMode,
                voiceName: voiceName,
                settings: settings
            )

            guard let audioData = Data(base64Encoded: response.audioBase64) else {
                throw BalabolkaError.invalidResponse
            }

            let audioURL = FileManager.default.temporaryDirectory
                .appending(path: "\(UUID().uuidString)-chunk-\(chunk.index).wav")
            try audioData.write(to: audioURL, options: [.atomic])
            transientAudioURLs.append(audioURL)

            preparedChunks.append(
                PreparedSynthesisChunk(
                    index: chunk.index,
                    audioURL: audioURL,
                    preparedTranscript: response.preparedTranscript,
                    voiceName: response.voiceName,
                    sampleRate: response.sampleRate,
                    modelName: response.modelName
                )
            )

            let chunkFraction = Double(position + 1) / Double(max(chunks.count, 1))
            await progress?(
                GenerationProgressState(
                    stage: .synthesizingSpeech,
                    stageFraction: chunkFraction,
                    statusMessage: synthesisStatus(currentChunk: position + 1, totalChunks: chunks.count)
                )
            )
        }

        let orderedChunks = preparedChunks.sorted { $0.index < $1.index }
        guard let firstChunk = orderedChunks.first else {
            throw BalabolkaError.invalidResponse
        }

        let preparedTranscript = orderedChunks
            .map(\.preparedTranscript)
            .joined(separator: "\n\n")
        let uniqueModels = Array(NSOrderedSet(array: orderedChunks.map(\.modelName))) as? [String] ?? [firstChunk.modelName]
        let resolvedModelName = uniqueModels.joined(separator: " + ")

        if orderedChunks.count == 1 {
            retainedAudioURL = firstChunk.audioURL
            return PreparedLongFormAudio(
                audioData: try Data(contentsOf: firstChunk.audioURL),
                audioURL: firstChunk.audioURL,
                preparedTranscript: preparedTranscript,
                voiceName: firstChunk.voiceName,
                sampleRate: firstChunk.sampleRate,
                modelName: resolvedModelName
            )
        }

        await progress?(GenerationProgressState(
            stage: .processingAudio,
            stageFraction: 0.05,
            statusMessage: "Склеиваю \(orderedChunks.count) аудиофрагментов в один WAV."
        ))
        let stitched = try LongFormAudioStitcher.stitchWAVFiles(at: orderedChunks.map(\.audioURL))
        let stitchedAudioURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)-assembled.wav")
        try stitched.wavData.write(to: stitchedAudioURL, options: [.atomic])
        transientAudioURLs.append(stitchedAudioURL)
        retainedAudioURL = stitchedAudioURL

        return PreparedLongFormAudio(
            audioData: stitched.wavData,
            audioURL: stitchedAudioURL,
            preparedTranscript: preparedTranscript,
            voiceName: firstChunk.voiceName,
            sampleRate: stitched.sampleRate,
            modelName: resolvedModelName
        )
    }

    private func chunkTitle(baseTitle: String, position: Int, total: Int) -> String {
        guard total > 1 else { return baseTitle }
        return "\(baseTitle) · \(position + 1)/\(total)"
    }

    private func preparingStatus(presetCount: Int, chunkCount: Int) -> String {
        if presetCount > 1 {
            return "Готовлю expressive-план для \(presetCount) режимов и \(chunkCount) фрагм."
        }

        return chunkCount > 1
            ? "Готовлю запрос и режу длинный текст на \(chunkCount) фрагм."
            : "Готовлю запрос и expressive-настройку голоса."
    }

    private func synthesisStatus(currentChunk: Int, totalChunks: Int) -> String {
        guard totalChunks > 1 else {
            return "Gemini генерирует речь. Внутри запроса могут быть дополнительные TTS-подчанки."
        }

        if currentChunk <= 0 {
            return "Запускаю long-form озвучку: будет \(totalChunks) фрагм."
        }

        return "Gemini озвучил \(currentChunk) из \(totalChunks) фрагм."
    }

    private func renderingStatus(renderFraction: Double) -> String {
        let percent = Int((min(max(renderFraction, 0), 1) * 100).rounded())
        return "Рендер видео и синхронизация волны: \(percent)% этапа."
    }

    private func synthesisDirective(
        forChunkAt position: Int,
        totalChunks: Int,
        presets: [ExpressivePreset],
        combineMode: ExpressiveCombineMode?
    ) -> ChunkSynthesisDirective {
        guard
            totalChunks > 1,
            presets.count > 1,
            combineMode == .sequence
        else {
            return ChunkSynthesisDirective(
                presets: presets,
                combineMode: presets.count > 1 ? combineMode : nil
            )
        }

        let chunkStart = Double(position) / Double(totalChunks)
        let chunkEnd = Double(position + 1) / Double(totalChunks)
        let maxPresetIndex = presets.count - 1
        let startIndex = min(maxPresetIndex, Int(floor(chunkStart * Double(presets.count))))
        let safeUpperProgress = max(chunkStart, min(chunkEnd - 0.000_001, 0.999_999))
        let endIndex = min(maxPresetIndex, Int(floor(safeUpperProgress * Double(presets.count))))
        let selectedPresets = Array(presets[startIndex...max(startIndex, endIndex)])

        return ChunkSynthesisDirective(
            presets: selectedPresets,
            combineMode: selectedPresets.count > 1 ? .sequence : nil
        )
    }
}
