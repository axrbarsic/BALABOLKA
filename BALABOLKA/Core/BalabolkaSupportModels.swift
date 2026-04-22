import Foundation

enum BalabolkaRuntime {
    static var resetStateOnLaunch: Bool {
        ProcessInfo.processInfo.environment["BALABOLKA_RESET_STATE"] == "1"
    }

    static var stubSynthesisMode: Bool {
        ProcessInfo.processInfo.environment["BALABOLKA_UI_TEST_MODE"] == "1"
    }

    static var disableInlineAutoplay: Bool {
        ProcessInfo.processInfo.environment["BALABOLKA_DISABLE_INLINE_AUTOPLAY"] == "1"
    }
}

extension ExpressivePreset {
    nonisolated var cardIcon: String {
        switch id {
        case .quiet: "speaker.wave.1.fill"
        case .whisper: "moon.stars.fill"
        case .laugh: "face.smiling.fill"
        case .cry: "cloud.rain.fill"
        case .cough: "waveform.path.ecg"
        case .hoarse: "flame.fill"
        case .sarcasm: "theatermasks.fill"
        case .anger: "bolt.fill"
        case .tired: "bed.double.fill"
        case .heavyBreathing: "wind"
        }
    }

    nonisolated var cardChip: String {
        switch id {
        case .quiet: "low gain"
        case .whisper: "[whisper]"
        case .laugh: "[laughs]"
        case .cry: "[crying]"
        case .cough: "[cough]"
        case .hoarse: "gravelly"
        case .sarcasm: "[sarcastic]"
        case .anger: "clipped"
        case .tired: "[tired]"
        case .heavyBreathing: "[gasp]"
        }
    }

    nonisolated var recommendedVoice: GeminiVoice {
        recommendedVoices.first ?? .sulafat
    }

    nonisolated var payload: [String: String] {
        [
            "title": title,
            "summary": shortDescription,
            "audioProfileTemplate": audioProfileTemplate,
            "sceneTemplate": sceneTemplate,
            "recommendedVoices": recommendedVoices.map(\.rawValue).joined(separator: ", "),
            "directorNotes": baselineDirectorNotes.joined(separator: " | "),
            "avoidNotes": avoidNotes.joined(separator: " | "),
            "stageDirections": stageDirections.map(\.instruction).joined(separator: " | ")
        ]
    }
}

extension ExpressivePreset.ID {
    nonisolated var proxyPresetID: String {
        switch self {
        case .quiet: "quiet"
        case .whisper: "whisper"
        case .laugh: "laugh"
        case .cry: "cry"
        case .cough: "cough"
        case .hoarse: "hoarse"
        case .sarcasm: "sarcasm"
        case .anger: "anger"
        case .tired: "tired"
        case .heavyBreathing: "heavy_breathing"
        }
    }
}

struct BalabolkaSettings: Codable, Equatable, Sendable {
    static let productionProxyBaseURL = "https://balabolka-proxy.axrbarsic.workers.dev"

    var proxyBaseURL: String = Self.productionProxyBaseURL
    var bearerToken: String = ""
    var defaultVoice: GeminiVoice = .sulafat
}

enum BalabolkaLimits {
    static let proxyRequestMaxCharacters = 12_000
    static let longFormSourceTextMaxCharacters = 128_000
    static let longFormChunkTargetCharacters = 4_200
    static let officialTTSInputTokenLimit = 8_192
    static let officialTTSOutputTokenLimit = 16_384

    static let proxyRequestMaxDescription =
        "\(proxyRequestMaxCharacters.formatted(.number.grouping(.automatic))) символов"
    static let longFormSourceTextMaxDescription =
        "\(longFormSourceTextMaxCharacters.formatted(.number.grouping(.automatic))) символов"
    static let officialTokenDescription =
        "\(officialTTSInputTokenLimit.formatted(.number.grouping(.automatic))) входных токенов"
}

enum GenerationProgressStage: Int, CaseIterable, Codable, Sendable {
    case preparingRequest
    case synthesizingSpeech
    case processingAudio
    case renderingVideo
    case savingResult

    var title: String {
        switch self {
        case .preparingRequest:
            "Подготовка"
        case .synthesizingSpeech:
            "Озвучка"
        case .processingAudio:
            "Аудио"
        case .renderingVideo:
            "Видео"
        case .savingResult:
            "Сохранение"
        }
    }

    var detail: String {
        switch self {
        case .preparingRequest:
            "Собираю expressive-план и готовлю запрос."
        case .synthesizingSpeech:
            "Gemini генерирует речь. Для длинного текста это может занять пару минут."
        case .processingAudio:
            "Проверяю WAV и считаю живую амплитуду."
        case .renderingVideo:
            "Собираю квадратное видео 720×720 и синхронизирую волну."
        case .savingResult:
            "Пишу итоговый файл в историю и локальный кэш."
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .preparingRequest:
            0.0...0.12
        case .synthesizingSpeech:
            0.12...0.74
        case .processingAudio:
            0.74...0.86
        case .renderingVideo:
            0.86...0.97
        case .savingResult:
            0.97...1.0
        }
    }

    var syntheticCeiling: Double {
        switch self {
        case .preparingRequest:
            0.9
        case .synthesizingSpeech:
            0.93
        case .processingAudio:
            0.9
        case .renderingVideo:
            0.94
        case .savingResult:
            0.9
        }
    }

    func fraction(for stageFraction: Double) -> Double {
        let safeStageFraction = min(max(stageFraction, 0), 1)
        let span = range.upperBound - range.lowerBound
        return min(max(range.lowerBound + (span * safeStageFraction), 0), 1)
    }
}

struct GenerationProgressState: Equatable, Sendable {
    var stage: GenerationProgressStage
    var fractionCompleted: Double
    var stageFraction: Double
    var statusMessage: String?

    init(
        stage: GenerationProgressStage,
        fractionCompleted: Double? = nil,
        stageFraction: Double = 0,
        statusMessage: String? = nil
    ) {
        self.stage = stage
        self.stageFraction = min(max(stageFraction, 0), 1)
        self.fractionCompleted = min(max(fractionCompleted ?? stage.fraction(for: self.stageFraction), 0), 1)
        self.statusMessage = statusMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var percentText: String {
        "\(Int((fractionCompleted * 100).rounded()))%"
    }

    var detailText: String {
        if let statusMessage, !statusMessage.isEmpty {
            return statusMessage
        }

        return stage.detail
    }
}

enum ExpressiveCombineMode: String, CaseIterable, Codable, Sendable {
    case auto
    case blend
    case sequence

    var title: String {
        switch self {
        case .auto:
            "Умно"
        case .blend:
            "Смешать"
        case .sequence:
            "По ходу текста"
        }
    }
}

struct GenerationRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    var title: String
    var sourceText: String
    var preparedTranscript: String
    var presetIDs: [ExpressivePreset.ID]
    var combineMode: ExpressiveCombineMode?
    var voiceName: GeminiVoice
    var sampleRate: Int
    var modelName: String
    var audioRelativePath: String
    var videoRelativePath: String
    var duration: TimeInterval
    var waveformEnvelope: [Float]

    init(
        id: UUID,
        createdAt: Date,
        title: String,
        sourceText: String,
        preparedTranscript: String,
        presetIDs: [ExpressivePreset.ID],
        combineMode: ExpressiveCombineMode?,
        voiceName: GeminiVoice,
        sampleRate: Int,
        modelName: String,
        audioRelativePath: String,
        videoRelativePath: String,
        duration: TimeInterval,
        waveformEnvelope: [Float]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.sourceText = sourceText
        self.preparedTranscript = preparedTranscript
        self.presetIDs = presetIDs.isEmpty ? [.quiet] : presetIDs
        self.combineMode = combineMode
        self.voiceName = voiceName
        self.sampleRate = sampleRate
        self.modelName = modelName
        self.audioRelativePath = audioRelativePath
        self.videoRelativePath = videoRelativePath
        self.duration = duration
        self.waveformEnvelope = waveformEnvelope
    }

    init(from decoder: Decoder) throws {
        enum CodingKeys: String, CodingKey {
            case id
            case createdAt
            case title
            case sourceText
            case preparedTranscript
            case presetID
            case presetIDs
            case combineMode
            case voiceName
            case sampleRate
            case modelName
            case audioRelativePath
            case videoRelativePath
            case duration
            case waveformEnvelope
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        title = try container.decode(String.self, forKey: .title)
        sourceText = try container.decode(String.self, forKey: .sourceText)
        preparedTranscript = try container.decode(String.self, forKey: .preparedTranscript)
        if let decodedPresetIDs = try container.decodeIfPresent([ExpressivePreset.ID].self, forKey: .presetIDs),
           !decodedPresetIDs.isEmpty {
            presetIDs = decodedPresetIDs
        } else if let legacyPresetID = try container.decodeIfPresent(ExpressivePreset.ID.self, forKey: .presetID) {
            presetIDs = [legacyPresetID]
        } else {
            presetIDs = [.quiet]
        }
        combineMode = try container.decodeIfPresent(ExpressiveCombineMode.self, forKey: .combineMode)
        voiceName = try container.decode(GeminiVoice.self, forKey: .voiceName)
        sampleRate = try container.decode(Int.self, forKey: .sampleRate)
        modelName = try container.decode(String.self, forKey: .modelName)
        audioRelativePath = try container.decode(String.self, forKey: .audioRelativePath)
        videoRelativePath = try container.decode(String.self, forKey: .videoRelativePath)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        waveformEnvelope = try container.decode([Float].self, forKey: .waveformEnvelope)
    }

    func encode(to encoder: Encoder) throws {
        enum CodingKeys: String, CodingKey {
            case id
            case createdAt
            case title
            case sourceText
            case preparedTranscript
            case presetIDs
            case combineMode
            case voiceName
            case sampleRate
            case modelName
            case audioRelativePath
            case videoRelativePath
            case duration
            case waveformEnvelope
        }

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(title, forKey: .title)
        try container.encode(sourceText, forKey: .sourceText)
        try container.encode(preparedTranscript, forKey: .preparedTranscript)
        try container.encode(presetIDs, forKey: .presetIDs)
        try container.encodeIfPresent(combineMode, forKey: .combineMode)
        try container.encode(voiceName, forKey: .voiceName)
        try container.encode(sampleRate, forKey: .sampleRate)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(audioRelativePath, forKey: .audioRelativePath)
        try container.encode(videoRelativePath, forKey: .videoRelativePath)
        try container.encode(duration, forKey: .duration)
        try container.encode(waveformEnvelope, forKey: .waveformEnvelope)
    }
}

extension GenerationRecord {
    var presetID: ExpressivePreset.ID { presetIDs.first ?? .quiet }
    var preset: ExpressivePreset { presetID.preset }
    var presets: [ExpressivePreset] { presetIDs.map(\.preset) }
    var presetSummary: String {
        let labels = presets.map(\.title)
        return labels.isEmpty ? ExpressivePreset.ID.quiet.preset.title : labels.joined(separator: " + ")
    }
}

struct SynthesisRequest: Codable, Sendable {
    let id: String?
    let title: String?
    let text: String
    let preset: String
    let presetIds: [String]?
    let combineMode: String?
    let voice: String
    let usePromptPreprocessor: Bool
}

struct SynthesisResponse: Codable, Sendable {
    let audioBase64: String
    let preparedTranscript: String
    let voiceName: String
    let mimeType: String
    let sampleRate: Int
    let modelName: String
}

struct ProxySynthesisEnvelope: Codable, Sendable {
    struct PromptPayload: Codable, Sendable {
        let preparedPrompt: String
        let preparedTranscript: String
    }

    struct VoicePayload: Codable, Sendable {
        let name: String
        let descriptor: String
    }

    struct AudioPayload: Codable, Sendable {
        let mimeType: String
        let base64: String
        let sampleRateHz: Int
    }

    struct ProviderPayload: Codable, Sendable {
        let ttsModel: String
    }

    let requestId: String
    let prompt: PromptPayload
    let voice: VoicePayload
    let audio: AudioPayload
    let provider: ProviderPayload
}

enum BalabolkaError: LocalizedError {
    case missingProxyURL
    case emptyText
    case sourceTextTooLong(current: Int, max: Int)
    case invalidResponse
    case badStatus(Int, String)
    case fileMissing
    case requestTimedOut

    var errorDescription: String? {
        switch self {
        case .missingProxyURL:
            return "Укажи URL proxy в настройках."
        case .emptyText:
            return "Нужен текст для озвучки."
        case let .sourceTextTooLong(current, max):
            return "Текст слишком длинный даже для текущего long-form mobile-режима: \(current.formatted(.number.grouping(.automatic))) символов при лимите \(max.formatted(.number.grouping(.automatic))). Для ещё больших стенограмм нужен отдельный batch/job режим."
        case .invalidResponse:
            return "Proxy вернул неожиданный ответ."
        case let .badStatus(code, body):
            if body.localizedCaseInsensitiveContains("quota") {
                if body.localizedCaseInsensitiveContains("daily") ||
                    body.localizedCaseInsensitiveContains("per_model_per_day") ||
                    body.localizedCaseInsensitiveContains("requests per day")
                {
                    return "Квота Gemini TTS на сегодня исчерпана для этого проекта. Это ограничение модели, а не зависание приложения. Подожди суточного сброса квоты или переключи backend на другой проект/API key."
                }

                return "Gemini TTS временно упёрся в лимит запросов. Попробуй ещё раз чуть позже или сократи нагрузку."
            }

            return "Proxy ответил ошибкой \(code): \(body)"
        case .fileMissing:
            return "Локальный файл результата не найден."
        case .requestTimedOut:
            return "Сервер озвучки не успел ответить вовремя. Для длинного текста генерация может занимать заметно дольше минуты."
        }
    }
}
