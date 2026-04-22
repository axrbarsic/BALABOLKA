import Foundation
import XCTest
@testable import BALABOLKA

final class ProxyClientTests: XCTestCase {
    func testSynthesizeBuildsExpectedRequestAndDecodesResponse() async throws {
        let capture = RequestCapture()
        let responseData = try BalabolkaTestSupport.makeProxyEnvelopeJSON()
        let client = ProxyClient { request in
            await capture.store(request)
            return (responseData, BalabolkaTestSupport.makeHTTPResponse())
        }

        let result = try await client.synthesize(
            title: "Новая озвучка",
            text: "Проверка запроса",
            presets: [.preset(for: .anger)],
            combineMode: nil,
            voiceName: .fenrir,
            settings: BalabolkaSettings(
                proxyBaseURL: "http://localhost:8787",
                bearerToken: "secret-token",
                defaultVoice: .sulafat
            )
        )

        let capturedRequest = await capture.load()
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
        XCTAssertEqual(request.url?.path, "/v1/tts/synthesize")

        let body = try XCTUnwrap(request.httpBody)
        let payload = try JSONDecoder().decode(SynthesisRequest.self, from: body)
        XCTAssertEqual(payload.preset, "anger")
        XCTAssertNil(payload.presetIds)
        XCTAssertNil(payload.combineMode)
        XCTAssertEqual(payload.voice, GeminiVoice.fenrir.rawValue)
        XCTAssertTrue(payload.usePromptPreprocessor)

        XCTAssertEqual(result.voiceName, GeminiVoice.sulafat.rawValue)
        XCTAssertEqual(result.mimeType, "audio/wav")
        XCTAssertEqual(result.sampleRate, 24_000)
    }

    func testStubModeBypassesNetworkAndReturnsFixtureAudio() async throws {
        setenv("BALABOLKA_UI_TEST_MODE", "1", 1)
        defer { unsetenv("BALABOLKA_UI_TEST_MODE") }

        let client = ProxyClient { _ in
            XCTFail("Network must not be hit in stub mode")
            return (Data(), BalabolkaTestSupport.makeHTTPResponse(statusCode: 500))
        }

        let result = try await client.synthesize(
            title: "Stub",
            text: "Stub path",
            presets: [.preset(for: .quiet)],
            combineMode: nil,
            voiceName: .sulafat,
            settings: BalabolkaSettings()
        )

        XCTAssertEqual(result.modelName, "stub.gemini.local")
        XCTAssertEqual(result.mimeType, "audio/wav")
        XCTAssertFalse(result.audioBase64.isEmpty)
    }
}

private actor RequestCapture {
    private var request: URLRequest?

    func store(_ request: URLRequest) {
        self.request = request
    }

    func load() -> URLRequest? {
        request
    }
}

private extension ExpressivePreset {
    static func preset(for id: ExpressivePreset.ID) -> ExpressivePreset {
        id.preset
    }
}
