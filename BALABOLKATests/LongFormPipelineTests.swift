import XCTest
@testable import BALABOLKA

final class LongFormPipelineTests: XCTestCase {
    func testChunkerSplits128kRussianTextWithinProxyBudget() {
        let text = Self.makeExpressiveRussianText(targetCharacters: 128_000)

        let chunks = LongFormTextChunker.makeChunks(from: text)

        XCTAssertGreaterThan(text.count, 120_000)
        XCTAssertGreaterThan(chunks.count, 10)
        XCTAssertTrue(chunks.allSatisfy { !$0.text.isEmpty })
        XCTAssertTrue(chunks.allSatisfy { $0.text.count <= BalabolkaLimits.proxyRequestMaxCharacters })
        XCTAssertTrue(chunks.contains { $0.text.contains("шёпотом") || $0.text.contains("кашляет") || $0.text.contains("смеётся") })
    }

    func testAudioStitcherCombinesWAVSegmentsIntoSingleFile() throws {
        let firstURL = try BalabolkaTestSupport.makeToneWAVFile(duration: 0.8, frequency: 330)
        let secondURL = try BalabolkaTestSupport.makeToneWAVFile(duration: 0.9, frequency: 550)

        let stitched = try LongFormAudioStitcher.stitchWAVFiles(at: [firstURL, secondURL], insertedGapMilliseconds: 90)
        let directory = try BalabolkaTestSupport.makeTemporaryDirectory()
        let outputURL = directory.appending(path: "stitched.wav")
        try stitched.wavData.write(to: outputURL)

        let envelope = try WaveformAnalyzer.analyze(audioURL: outputURL, frameRate: 30)
        XCTAssertEqual(stitched.sampleRate, 24_000)
        XCTAssertGreaterThan(stitched.duration, 1.7)
        XCTAssertGreaterThan(envelope.duration, 1.7)
        XCTAssertFalse(envelope.samples.isEmpty)
    }

    func testLongFormUseCaseProcesses128kStressPayloadInSimulator() async throws {
        guard ProcessInfo.processInfo.environment["BALABOLKA_ENABLE_LONGFORM_STRESS"] == "1" else {
            throw XCTSkip("Long-form simulator stress test is opt-in.")
        }

        let sourceText = Self.makeExpressiveRussianText(targetCharacters: 128_000)
        let baseDirectory = try BalabolkaTestSupport.makeTemporaryDirectory()
        let repository = LibraryRepository(baseDirectory: baseDirectory, resetOnInit: false)
        let exporter = SquareVideoExporter()
        let capture = SynthesisRequestCapture()
        let proxyClient = ProxyClient { request in
            let requestBody = try XCTUnwrap(request.httpBody)
            let decoded = try JSONDecoder().decode(SynthesisRequest.self, from: requestBody)
            await capture.record(decoded)
            XCTAssertFalse(decoded.text.isEmpty)
            XCTAssertLessThanOrEqual(decoded.text.count, BalabolkaLimits.proxyRequestMaxCharacters)

            let activePresetIDs = decoded.presetIds ?? [decoded.preset]
            XCTAssertFalse(activePresetIDs.isEmpty)
            XCTAssertLessThanOrEqual(activePresetIDs.count, 2)

            if activePresetIDs.count > 1 {
                XCTAssertEqual(decoded.combineMode, ExpressiveCombineMode.sequence.rawValue)
            } else {
                XCTAssertNil(decoded.combineMode)
            }

            let chunkDuration = min(max(Double(decoded.text.count) / 5_000, 0.45), 1.1)
            let audioData = WAVBuilder.makeMonoSineWave(
                duration: chunkDuration,
                sampleRate: 24_000,
                frequency: 220 + Double(decoded.text.count % 200)
            )
            let envelope = ProxySynthesisEnvelope(
                requestId: UUID().uuidString,
                prompt: .init(
                    preparedPrompt: "long-form-stub",
                    preparedTranscript: decoded.text
                ),
                voice: .init(name: GeminiVoice.algenib.rawValue, descriptor: GeminiVoice.algenib.descriptor),
                audio: .init(
                    mimeType: "audio/wav",
                    base64: audioData.base64EncodedString(),
                    sampleRateHz: 24_000
                ),
                provider: .init(ttsModel: "gemini-longform-stub")
            )

            return (
                try JSONEncoder().encode(envelope),
                BalabolkaTestSupport.makeHTTPResponse(statusCode: 200, url: request.url ?? URL(string: "http://localhost")!)
            )
        }

        let useCase = GenerateSpeechVideoUseCase(
            proxyClient: proxyClient,
            exporter: exporter,
            repository: repository
        )
        let request = GenerateSpeechVideoRequest(
            title: "Long-form stress",
            text: sourceText,
            presetIDs: [.quiet, .whisper, .laugh],
            combineMode: .sequence,
            voiceName: .algenib
        )

        let record = try await useCase.execute(
            request: request,
            settings: BalabolkaSettings(
                proxyBaseURL: "http://localhost:8787",
                bearerToken: "",
                defaultVoice: .algenib
            )
        )
        let capturedRequests = await capture.requests()
        let observedPresetGroups = capturedRequests.map { $0.presetIds ?? [$0.preset] }

        XCTAssertGreaterThan(record.sourceText.count, 120_000)
        XCTAssertEqual(record.presetIDs, [.quiet, .whisper, .laugh])
        XCTAssertEqual(record.combineMode, .sequence)
        XCTAssertEqual(record.voiceName, .algenib)
        XCTAssertEqual(record.modelName, "gemini-longform-stub")
        XCTAssertGreaterThan(observedPresetGroups.count, 10)
        XCTAssertTrue(observedPresetGroups.first?.contains("quiet") == true)
        XCTAssertTrue(observedPresetGroups.contains(where: { $0.contains("whisper") }))
        XCTAssertTrue(observedPresetGroups.last?.contains("laugh") == true)
        XCTAssertFalse(observedPresetGroups.allSatisfy { $0 == ["quiet", "whisper", "laugh"] })
        XCTAssertTrue(observedPresetGroups.allSatisfy { $0.count <= 2 })
        XCTAssertTrue(record.duration > 10)
        XCTAssertFalse(record.waveformEnvelope.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repository.audioURL(for: record).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: repository.videoURL(for: record).path))
    }

    func testUserMixedModeTextKeepsProgressMonotonic() async throws {
        let sourceText = Self.makeUserSuppliedRussianText()
        let baseDirectory = try BalabolkaTestSupport.makeTemporaryDirectory()
        let repository = LibraryRepository(baseDirectory: baseDirectory, resetOnInit: false)
        let exporter = SquareVideoExporter()
        let capture = SynthesisRequestCapture()
        let progressCapture = ProgressStateCapture()
        let proxyClient = ProxyClient { request in
            let requestBody = try XCTUnwrap(request.httpBody)
            let decoded = try JSONDecoder().decode(SynthesisRequest.self, from: requestBody)
            await capture.record(decoded)

            let chunkDuration = min(max(Double(decoded.text.count) / 4_800, 0.5), 1.3)
            let audioData = WAVBuilder.makeMonoSineWave(
                duration: chunkDuration,
                sampleRate: 24_000,
                frequency: 260 + Double(decoded.text.count % 160)
            )
            let envelope = ProxySynthesisEnvelope(
                requestId: UUID().uuidString,
                prompt: .init(
                    preparedPrompt: "mixed-mode-user-text",
                    preparedTranscript: decoded.text
                ),
                voice: .init(name: GeminiVoice.charon.rawValue, descriptor: GeminiVoice.charon.descriptor),
                audio: .init(
                    mimeType: "audio/wav",
                    base64: audioData.base64EncodedString(),
                    sampleRateHz: 24_000
                ),
                provider: .init(ttsModel: "gemini-progress-stub")
            )

            return (
                try JSONEncoder().encode(envelope),
                BalabolkaTestSupport.makeHTTPResponse(statusCode: 200, url: request.url ?? URL(string: "http://localhost")!)
            )
        }

        let useCase = GenerateSpeechVideoUseCase(
            proxyClient: proxyClient,
            exporter: exporter,
            repository: repository
        )
        let request = GenerateSpeechVideoRequest(
            title: "User mixed mode",
            text: sourceText,
            presetIDs: [.sarcasm, .laugh, .cough],
            combineMode: .auto,
            voiceName: .charon
        )

        _ = try await useCase.execute(
            request: request,
            settings: BalabolkaSettings(
                proxyBaseURL: "http://localhost:8787",
                bearerToken: "",
                defaultVoice: .charon
            ),
            progress: { state in
                await progressCapture.record(state)
            }
        )

        let capturedRequests = await capture.requests()
        let progressStates = await progressCapture.states()

        XCTAssertGreaterThan(sourceText.count, 3_000)
        XCTAssertFalse(capturedRequests.isEmpty)
        XCTAssertEqual(capturedRequests.first?.presetIds ?? [], ["sarcasm", "laugh", "cough"])
        XCTAssertEqual(capturedRequests.first?.combineMode, ExpressiveCombineMode.auto.rawValue)
        XCTAssertTrue(progressStates.count >= 7)
        XCTAssertEqual(progressStates.first?.stage, .preparingRequest)
        XCTAssertEqual(progressStates.last?.stage, .savingResult)
        XCTAssertEqual(try XCTUnwrap(progressStates.last).fractionCompleted, 1, accuracy: 0.0001)
        XCTAssertTrue(progressStates.allSatisfy { !$0.detailText.isEmpty })

        for pair in zip(progressStates, progressStates.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0.fractionCompleted, pair.1.fractionCompleted + 0.0001)
        }
    }
}

private actor SynthesisRequestCapture {
    private var storedRequests: [SynthesisRequest] = []

    func record(_ request: SynthesisRequest) {
        storedRequests.append(request)
    }

    func requests() -> [SynthesisRequest] {
        storedRequests
    }
}

private actor ProgressStateCapture {
    private var storedStates: [GenerationProgressState] = []

    func record(_ state: GenerationProgressState) {
        storedStates.append(state)
    }

    func states() -> [GenerationProgressState] {
        storedStates
    }
}

private extension LongFormPipelineTests {
    static func makeExpressiveRussianText(targetCharacters: Int) -> String {
        let paragraphs = [
            "Он говорит тихо, почти шёпотом, затем коротко кашляет и продолжает без паники, будто держит ритм рассказа под полным контролем.",
            "Иногда он смеётся уголком голоса, а потом снова собирается и возвращается к ровной, ясной дикции, как хороший рассказчик длинной истории.",
            "В одном месте он устало выдыхает, в другом сбрасывает напряжение и шепчет признание так, словно рядом спят люди и нельзя шуметь.",
            "В середине повествования слышна лёгкая хрипота, затем снова чистая речь, и это делает озвучку живой, но не клоунской.",
            "Иногда пауза короткая, затем снова фраза, потом смешок, потом спокойный тон, потом сухой кашель, и вся сцена остаётся естественной."
        ]

        var result: [String] = []
        var index = 0

        while result.joined(separator: "\n\n").count < targetCharacters {
            let paragraph = paragraphs[index % paragraphs.count]
            result.append("Абзац \(index + 1). \(paragraph)")
            index += 1
        }

        return result.joined(separator: "\n\n")
    }

    static func makeUserSuppliedRussianText() -> String {
        """
        @TeaTramRussia, давай разберем эту трогательную иллюзию глобального фан-клуба, который якобы прорывается сквозь мифическую «западную пропаганду», на примере твоего наивного комментатора @lyle_ott. Ты жалуешься на «русофобию» и «антироссийскую пропаганду», пытаясь выставить международную изоляцию РФ как какую-то иррациональную, ничем не обоснованную ненависть Запада. Давай посмотрим на сухие факты, цифры и международное право, свободные от эхо-камер соцсетей и удобных алгоритмических переводов.

        Во-первых, термин «русофобия» - это искусственный политический конструкт, удобный щит, выкованный Кремлем для защиты от любой критики своих внешнеполитических и внутренних преступлений. У Запада нет иррационального страха перед русскими как нацией. Реакция международного сообщества - это прямой и закономерный ответ на задокументированные, объективные нарушения Устава ООН. Когда 141 страна на Генеральной Ассамблее ООН голосует за резолюцию, осуждающую вторжение в Украину, это не «пропаганда». Это глобальный консенсус в области международного права. Когда Международный уголовный суд выдает ордер на арест за незаконную депортацию детей, это юридический процесс, основанный на доказательствах, а не пережиток холодной войны. Называть требование ответственности «русофобией» - это классическая манипуляция и перекладывание вины с агрессора на наблюдателей.

        Во-вторых, давай обсудим эту вымышленную волну иностранцев, жаждущих переехать в Россию, чтобы спастись от «западной пропаганды», таких как твой друг Lyle. Статистика миграции вдребезги разбивает твой нарратив. По оценкам независимых демографов и международных институтов, с февраля 2022 года Россию покинули от 500 000 до 1 000 000 граждан. Это IT-специалисты, ученые, врачи и предприниматели. Они голосуют ногами против режима, который ты так усердно защищаешь. На этом фоне сколько американцев реально переезжает в РФ? Несмотря на отчаянные PR-акции, такие как указы об упрощенном ВНЖ для иностранцев, бегущих от «деструктивных неолиберальных установок», приток западных экспатов остается на уровне статистической погрешности. Ты гордишься лайками в комментариях, но в реальности Россия страдает от катастрофической утечки мозгов и острейшего демографического кризиса.

        Твой комментатор @lyle_ott утверждает, что его не обманет пропаганда, хотя он буквально глотает государственные нарративы, созданные для оправдания агрессивной войны, репрессий и экономической стагнации. Если он действительно хочет жить и работать в России, ему стоит подготовиться к суровой реальности: инфляция бьет рекорды, ключевая ставка Центробанка находится на заградительном кризисном уровне, а за неправильное мнение в интернете, отклоняющееся от официальной линии партии, можно легко отправиться в колонию за «дискредитацию армии».

        Твой пост - это хрестоматийный пример ошибки выжившего и предвзятости подтверждения. Ты находишь одного доверчивого иностранца и экстраполируешь это на весь мир, чтобы успокоить когнитивный диссонанс от жизни в изолированном, находящемся под беспрецедентными санкциями государстве. То, что ты называешь «антироссийской пропагандой», на деле является лишь зеркалом глобальной реальности, объективно отражающим последствия действий самой Москвы. Хватит путать геополитическую изоляцию за собственные преступления с позицией невинной жертвы.
        """
    }
}
