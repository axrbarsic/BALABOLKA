import Foundation

actor ProxyClient {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 1_200
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    private let dataLoader: DataLoader

    init(dataLoader: @escaping DataLoader = { request in
        try await ProxyClient.defaultSession.data(for: request)
    }) {
        self.dataLoader = dataLoader
    }

    func synthesize(
        title: String,
        text: String,
        presets: [ExpressivePreset],
        combineMode: ExpressiveCombineMode?,
        voiceName: GeminiVoice,
        settings: BalabolkaSettings
    ) async throws -> SynthesisResponse {
        #if DEBUG
        if BalabolkaRuntime.stubSynthesisMode {
            let duration = min(max(Double(text.count) / 18, 1.2), 6.5)
            let wavData = WAVBuilder.makeMonoSineWave(duration: duration)
            return SynthesisResponse(
                audioBase64: wavData.base64EncodedString(),
                preparedTranscript: text,
                voiceName: voiceName.rawValue,
                mimeType: "audio/wav",
                sampleRate: 24_000,
                modelName: "stub.gemini.local"
            )
        }
        #endif

        let trimmedURL = settings.proxyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { throw BalabolkaError.missingProxyURL }

        guard let baseURL = URL(string: trimmedURL) else {
            throw BalabolkaError.missingProxyURL
        }

        let resolvedPresets = presets.isEmpty ? [ExpressivePreset.ID.quiet.preset] : presets
        let requestBody = SynthesisRequest(
            id: nil,
            title: title,
            text: text,
            preset: resolvedPresets[0].id.proxyPresetID,
            presetIds: resolvedPresets.count > 1 ? resolvedPresets.map { $0.id.proxyPresetID } : nil,
            combineMode: resolvedPresets.count > 1 ? (combineMode ?? .auto).rawValue : nil,
            voice: voiceName.rawValue,
            usePromptPreprocessor: true
        )

        var request = URLRequest(url: baseURL.appending(path: "/v1/tts/synthesize"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !settings.bearerToken.isEmpty {
            request.setValue("Bearer \(settings.bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await dataLoader(request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw BalabolkaError.requestTimedOut
        }
        guard let http = response as? HTTPURLResponse else {
            throw BalabolkaError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(decoding: data, as: UTF8.self)
            throw BalabolkaError.badStatus(http.statusCode, body)
        }

        let envelope = try JSONDecoder().decode(ProxySynthesisEnvelope.self, from: data)
        return SynthesisResponse(
            audioBase64: envelope.audio.base64,
            preparedTranscript: envelope.prompt.preparedTranscript,
            voiceName: envelope.voice.name,
            mimeType: envelope.audio.mimeType,
            sampleRate: envelope.audio.sampleRateHz,
            modelName: envelope.provider.ttsModel
        )
    }
}
