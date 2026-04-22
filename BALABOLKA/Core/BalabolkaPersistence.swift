import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    private enum Keys {
        static let settings = "balabolka.settings"
    }

    var current: BalabolkaSettings {
        didSet { persist() }
    }

    init(
        defaults: UserDefaults = .standard,
        resetOnInit: Bool = BalabolkaRuntime.resetStateOnLaunch
    ) {
        if resetOnInit {
            defaults.removeObject(forKey: Keys.settings)
        }

        if
            let data = defaults.data(forKey: Keys.settings),
            let decoded = try? JSONDecoder().decode(BalabolkaSettings.self, from: data)
        {
            current = Self.migratedSettings(from: decoded)
        } else {
            current = BalabolkaSettings()
        }
        self.defaults = defaults
    }

    private let defaults: UserDefaults

    private func persist() {
        guard let data = try? JSONEncoder().encode(current) else { return }
        defaults.set(data, forKey: Keys.settings)
    }

    private static func migratedSettings(from settings: BalabolkaSettings) -> BalabolkaSettings {
        guard shouldPromoteToProductionProxy(settings.proxyBaseURL) else {
            return settings
        }

        var migrated = settings
        migrated.proxyBaseURL = BalabolkaSettings.productionProxyBaseURL
        migrated.bearerToken = ""
        return migrated
    }

    private static func shouldPromoteToProductionProxy(_ rawValue: String) -> Bool {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return true }
        guard let components = URLComponents(string: trimmedValue) else { return false }
        guard let host = components.host?.lowercased() else { return false }

        if host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local") {
            return true
        }

        if components.port == 8787, isPrivateIPv4Host(host) {
            return true
        }

        return false
    }

    private static func isPrivateIPv4Host(_ host: String) -> Bool {
        let octets = host.split(separator: ".")
        guard octets.count == 4 else { return false }
        let numbers = octets.compactMap { Int($0) }
        guard numbers.count == 4 else { return false }

        switch (numbers[0], numbers[1]) {
        case (10, _):
            return true
        case (172, 16...31):
            return true
        case (192, 168):
            return true
        default:
            return false
        }
    }
}

actor LibraryRepository {
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    nonisolated let baseDirectory: URL
    nonisolated let recordsDirectory: URL

    init(
        baseDirectory: URL? = nil,
        resetOnInit: Bool = BalabolkaRuntime.resetStateOnLaunch
    ) {
        let resolvedBaseDirectory = baseDirectory ?? Self.defaultBaseDirectory
        self.baseDirectory = resolvedBaseDirectory
        self.recordsDirectory = resolvedBaseDirectory.appending(path: "Records", directoryHint: .isDirectory)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        if resetOnInit, fileManager.fileExists(atPath: resolvedBaseDirectory.path) {
            try? fileManager.removeItem(at: resolvedBaseDirectory)
        }
    }

    func loadHistory() async throws -> [GenerationRecord] {
        try ensureDirectories()
        guard fileManager.fileExists(atPath: indexURL.path) else { return [] }
        let data = try Data(contentsOf: indexURL)
        return try decoder.decode([GenerationRecord].self, from: data)
            .sorted(by: { $0.createdAt > $1.createdAt })
    }

    nonisolated func audioURL(for record: GenerationRecord) -> URL {
        recordsDirectory.appending(path: record.id.uuidString).appending(path: record.audioRelativePath)
    }

    nonisolated func videoURL(for record: GenerationRecord) -> URL {
        recordsDirectory.appending(path: record.id.uuidString).appending(path: record.videoRelativePath)
    }

    nonisolated func videoURL(for record: GenerationRecord, profile: VideoQualityProfile) -> URL {
        switch profile {
        case .hq:
            videoURL(for: record)
        case .xSmall:
            recordsDirectory
                .appending(path: record.id.uuidString)
                .appending(path: "balabolka-\(profile.fileNameSuffix).mp4")
        }
    }

    func storeVideoVariant(at sourceURL: URL, for record: GenerationRecord, profile: VideoQualityProfile) throws -> URL {
        let destinationURL = videoURL(for: record, profile: profile)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    func persistGeneration(
        title: String,
        sourceText: String,
        preparedTranscript: String,
        presetIDs: [ExpressivePreset.ID],
        combineMode: ExpressiveCombineMode?,
        voiceName: GeminiVoice,
        sampleRate: Int,
        modelName: String,
        waveformEnvelope: [Float],
        audioData: Data,
        renderedVideoURL: URL,
        duration: TimeInterval
    ) async throws -> GenerationRecord {
        try ensureDirectories()

        let recordID = UUID()
        let recordDirectory = recordsDirectory.appending(path: recordID.uuidString)
        try fileManager.createDirectory(at: recordDirectory, withIntermediateDirectories: true)

        let audioName = "speech.wav"
        let videoName = "balabolka.mp4"
        let audioURL = recordDirectory.appending(path: audioName)
        let videoURL = recordDirectory.appending(path: videoName)

        try audioData.write(to: audioURL, options: [.atomic])
        if fileManager.fileExists(atPath: videoURL.path) {
            try fileManager.removeItem(at: videoURL)
        }
        try fileManager.copyItem(at: renderedVideoURL, to: videoURL)

        let record = GenerationRecord(
            id: recordID,
            createdAt: Date(),
            title: title,
            sourceText: sourceText,
            preparedTranscript: preparedTranscript,
            presetIDs: presetIDs,
            combineMode: combineMode,
            voiceName: voiceName,
            sampleRate: sampleRate,
            modelName: modelName,
            audioRelativePath: audioName,
            videoRelativePath: videoName,
            duration: duration,
            waveformEnvelope: waveformEnvelope
        )

        var allRecords = try await loadHistory()
        allRecords.insert(record, at: 0)
        try writeIndex(allRecords)
        return record
    }

    func delete(records deletedRecords: [GenerationRecord]) async throws {
        guard !deletedRecords.isEmpty else { return }

        try ensureDirectories()
        let deletedIDs = Set(deletedRecords.map(\.id))
        var remainingRecords = try await loadHistory()
        remainingRecords.removeAll { deletedIDs.contains($0.id) }

        for record in deletedRecords {
            let recordDirectory = recordsDirectory.appending(path: record.id.uuidString)
            if fileManager.fileExists(atPath: recordDirectory.path) {
                try fileManager.removeItem(at: recordDirectory)
            }
        }

        try writeIndex(remainingRecords)
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: recordsDirectory, withIntermediateDirectories: true)
    }

    private func writeIndex(_ records: [GenerationRecord]) throws {
        let data = try encoder.encode(records)
        try data.write(to: indexURL, options: [.atomic])
    }

    nonisolated private static var defaultBaseDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "BALABOLKA", directoryHint: .isDirectory)
    }

    private var indexURL: URL {
        baseDirectory.appending(path: "history.json")
    }
}
