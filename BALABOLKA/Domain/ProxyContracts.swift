//
//  ProxyContracts.swift
//  BALABOLKA
//
//  Created by Codex on 4/20/26.
//

import Foundation

struct ProxySynthesisRequest: Codable, Hashable, Sendable {
    var id: String
    var title: String?
    var text: String
    var preset: String
    var voice: String
    var usePromptPreprocessor: Bool

    init(
        draft: GenerationRequestDraft,
        title: String? = nil,
        usePromptPreprocessor: Bool = true
    ) {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)

        self.id = draft.id.uuidString.lowercased()
        self.title = trimmedTitle?.isEmpty == false ? trimmedTitle : nil
        self.text = draft.sourceText
        self.preset = draft.options.presetID.proxyIdentifier
        self.voice = draft.options.voice.rawValue
        self.usePromptPreprocessor = usePromptPreprocessor
    }
}

struct ProxyCatalogResponse: Codable, Hashable, Sendable {
    struct LimitsPayload: Codable, Hashable, Sendable {
        var sourceTextMaxCharacters: Int
        var ttsInputTokenLimit: Int
        var ttsOutputTokenLimit: Int
        var chunkingEnabled: Bool
    }

    struct PresetDescriptor: Codable, Hashable, Sendable {
        var id: String
        var label: String
        var description: String
        var defaultVoice: String
    }

    struct VoiceDescriptor: Codable, Hashable, Sendable {
        var name: String
        var descriptor: String
    }

    var presets: [PresetDescriptor]
    var voices: [VoiceDescriptor]
    var limits: LimitsPayload?
}

struct ProxySynthesisResponse: Codable, Hashable, Sendable {
    struct MetadataPayload: Codable, Hashable, Sendable {
        var id: String?
        var title: String?
    }

    struct PresetPayload: Codable, Hashable, Sendable {
        var id: String
        var label: String
        var description: String
    }

    struct VoicePayload: Codable, Hashable, Sendable {
        var name: String
        var descriptor: String
    }

    struct PromptPayload: Codable, Hashable, Sendable {
        struct DirectorNotesPayload: Codable, Hashable, Sendable {
            var style: String
            var pacing: String
            var breathing: String
            var articulation: String
            var sampleContext: String
        }

        var preparedPrompt: String
        var preparedTranscript: String
        var mode: String
        var preprocessorModel: String?
        var audioProfile: String
        var scene: String
        var directorNotes: DirectorNotesPayload
        var audioTags: [String]
        var notes: [String]
        var warnings: [String]
    }

    struct AudioPayload: Codable, Hashable, Sendable {
        var mimeType: String
        var base64: String
        var bytes: Int
        var durationMs: Double?
        var sampleRateHz: Int
        var channels: Int
        var bitDepth: Int
        var convertedFromPcm: Bool
        var rawMimeType: String?
        var sha256: String

        var durationSeconds: Double? {
            durationMs.map { $0 / 1_000 }
        }
    }

    struct ProviderPayload: Codable, Hashable, Sendable {
        var ttsModel: String
        var preprocessorModel: String?
        var ttsAttempts: Int
        var promptPreprocessorUsed: Bool
        var timestamp: Date?
    }

    var requestID: String
    var sourceText: String
    var metadata: MetadataPayload
    var preset: PresetPayload
    var voice: VoicePayload
    var prompt: PromptPayload
    var audio: AudioPayload
    var provider: ProviderPayload

    enum CodingKeys: String, CodingKey {
        case requestID = "requestId"
        case sourceText
        case metadata
        case preset
        case voice
        case prompt
        case audio
        case provider
    }
}
