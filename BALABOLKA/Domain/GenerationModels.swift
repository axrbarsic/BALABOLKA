//
//  GenerationModels.swift
//  BALABOLKA
//
//  Created by Codex on 4/20/26.
//

import CryptoKit
import Foundation

enum GenerationStatus: String, CaseIterable, Codable, Sendable {
    case draft
    case queued
    case processing
    case completed
    case failed
    case cancelled
}

enum ReactiveWaveformStyleKind: String, Codable, Sendable {
    case minimalReactive = "minimal_reactive"
}

enum VideoContainerFormat: String, Codable, Sendable {
    case mp4
    case mov
}

struct VideoRenderSpec: Codable, Hashable, Sendable {
    var width: Int
    var height: Int
    var backgroundHex: String
    var waveformStyle: ReactiveWaveformStyleKind
    var container: VideoContainerFormat

    static let balabolkaSquare = VideoRenderSpec(
        width: 720,
        height: 720,
        backgroundHex: "#FFFFFF",
        waveformStyle: .minimalReactive,
        container: .mp4
    )
}

struct SynthesisOptions: Codable, Hashable, Sendable {
    var modelName: String
    var voice: GeminiVoice
    var localeIdentifier: String
    var presetID: ExpressivePreset.ID
    var intensity: Double
    var includePromptDebug: Bool
}

struct GenerationRequestDraft: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var sourceText: String
    var options: SynthesisOptions
    var prompt: ExpressivePromptPackage
    var renderSpec: VideoRenderSpec
    var createdAt: Date
    var contentHash: String

    init(
        id: UUID = UUID(),
        sourceText: String,
        options: SynthesisOptions,
        prompt: ExpressivePromptPackage,
        renderSpec: VideoRenderSpec = .balabolkaSquare,
        createdAt: Date = .now
    ) {
        self.id = id
        self.sourceText = sourceText
        self.options = options
        self.prompt = prompt
        self.renderSpec = renderSpec
        self.createdAt = createdAt
        self.contentHash = GenerationRequestDraft.makeContentHash(
            text: sourceText,
            voice: options.voice,
            localeIdentifier: options.localeIdentifier,
            presetID: options.presetID,
            intensity: options.intensity,
            modelName: options.modelName,
            renderSpec: renderSpec
        )
    }

    static func makeContentHash(
        text: String,
        voice: GeminiVoice,
        localeIdentifier: String,
        presetID: ExpressivePreset.ID,
        intensity: Double,
        modelName: String,
        renderSpec: VideoRenderSpec
    ) -> String {
        let payload = [
            text,
            voice.rawValue,
            localeIdentifier,
            presetID.rawValue,
            String(format: "%.3f", intensity),
            modelName,
            "\(renderSpec.width)x\(renderSpec.height)",
            renderSpec.backgroundHex,
            renderSpec.waveformStyle.rawValue,
            renderSpec.container.rawValue
        ].joined(separator: "\u{1F}")

        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum RemoteAssetLocation: String, Codable, Sendable {
    case inlineBase64
    case remoteURL
    case proxyPath
}

struct RemoteAssetReference: Codable, Hashable, Sendable {
    var location: RemoteAssetLocation
    var value: String
    var mimeType: String?
    var fileExtension: String?

    func resolvedURL(relativeTo baseURL: URL?) -> URL? {
        switch location {
        case .remoteURL:
            return URL(string: value)
        case .proxyPath:
            guard let baseURL else { return nil }
            return URL(string: value, relativeTo: baseURL)?.absoluteURL
        case .inlineBase64:
            return nil
        }
    }
}

struct WaveformMetadata: Codable, Hashable, Sendable {
    var sampleCount: Int?
    var peak: Double?
    var rms: Double?
    var normalizedBuckets: [Double]?
}

struct GenerationResult: Codable, Hashable, Sendable {
    var remoteJobID: String?
    var transcript: String
    var videoAsset: RemoteAssetReference?
    var waveform: WaveformMetadata?
    var durationSeconds: Double?
    var fileSizeBytes: Int64?
    var completedAt: Date?
    var localAudioFilename: String?
    var localVideoFilename: String?
    var metadata: [String: String]

    var hasLocalVideo: Bool {
        guard let localVideoFilename else { return false }
        return !localVideoFilename.isEmpty
    }
}

struct GenerationFailure: Codable, Hashable, Sendable {
    var code: String?
    var message: String
    var retryable: Bool
}

struct GenerationJob: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var remoteID: String?
    var createdAt: Date
    var updatedAt: Date
    var status: GenerationStatus
    var request: GenerationRequestDraft
    var progress: Double?
    var attemptCount: Int
    var result: GenerationResult?
    var failure: GenerationFailure?

    init(
        id: UUID = UUID(),
        remoteID: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        status: GenerationStatus = .draft,
        request: GenerationRequestDraft,
        progress: Double? = nil,
        attemptCount: Int = 0,
        result: GenerationResult? = nil,
        failure: GenerationFailure? = nil
    ) {
        self.id = id
        self.remoteID = remoteID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.request = request
        self.progress = progress
        self.attemptCount = attemptCount
        self.result = result
        self.failure = failure
    }

    var previewText: String {
        request.sourceText.makePreview(limit: 120)
    }
}

struct GenerationHistoryItem: Codable, Hashable, Identifiable, Sendable {
    var job: GenerationJob
    var cachedAt: Date

    var id: UUID { job.id }
    var updatedAt: Date { job.updatedAt }
    var previewText: String { job.previewText }
    var sourceText: String { job.request.sourceText }
    var presetID: ExpressivePreset.ID { job.request.options.presetID }
    var voice: GeminiVoice { job.request.options.voice }
    var intensity: Double { job.request.options.intensity }
    var localAudioFilename: String? { job.result?.localAudioFilename }
    var localVideoFilename: String? { job.result?.localVideoFilename }
}

struct GenerationHistoryIndex: Codable, Hashable, Sendable {
    var version: Int
    var items: [GenerationHistoryItem]

    static let empty = GenerationHistoryIndex(version: 1, items: [])
}

private extension String {
    func makePreview(limit: Int) -> String {
        let flattened = self
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard flattened.count > limit else { return flattened }
        let cutoff = flattened.index(flattened.startIndex, offsetBy: limit)
        return "\(flattened[..<cutoff])…"
    }
}
