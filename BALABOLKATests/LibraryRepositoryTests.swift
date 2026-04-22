import XCTest
@testable import BALABOLKA

final class LibraryRepositoryTests: XCTestCase {
    func testPersistLoadAndDeleteGeneration() async throws {
        let baseDirectory = try BalabolkaTestSupport.makeTemporaryDirectory()
        let repository = LibraryRepository(baseDirectory: baseDirectory, resetOnInit: false)
        let audioData = WAVBuilder.makeMonoSineWave(duration: 1.0)
        let videoURL = try BalabolkaTestSupport.makePlaceholderVideoFile()

        let record = try await repository.persistGeneration(
            title: "Тест",
            sourceText: "Исходный текст",
            preparedTranscript: "Подготовленный текст",
            presetIDs: [.sarcasm, .tired],
            combineMode: .blend,
            voiceName: .charon,
            sampleRate: 24_000,
            modelName: "gemini-test",
            waveformEnvelope: [0.1, 0.5, 0.2],
            audioData: audioData,
            renderedVideoURL: videoURL,
            duration: 1.0
        )

        let loaded = try await repository.loadHistory()
        XCTAssertEqual(loaded.count, 1)
        let restored = try XCTUnwrap(loaded.first)
        XCTAssertEqual(restored.id, record.id)
        XCTAssertEqual(restored.title, record.title)
        XCTAssertEqual(restored.sourceText, record.sourceText)
        XCTAssertEqual(restored.preparedTranscript, record.preparedTranscript)
        XCTAssertEqual(restored.presetIDs, record.presetIDs)
        XCTAssertEqual(restored.combineMode, record.combineMode)
        XCTAssertEqual(restored.voiceName, record.voiceName)
        XCTAssertEqual(restored.sampleRate, record.sampleRate)
        XCTAssertEqual(restored.modelName, record.modelName)
        XCTAssertEqual(restored.audioRelativePath, record.audioRelativePath)
        XCTAssertEqual(restored.videoRelativePath, record.videoRelativePath)
        XCTAssertEqual(restored.duration, record.duration, accuracy: 0.0001)
        XCTAssertEqual(restored.waveformEnvelope.count, record.waveformEnvelope.count)
        for (lhs, rhs) in zip(restored.waveformEnvelope, record.waveformEnvelope) {
            XCTAssertEqual(lhs, rhs, accuracy: 0.0001)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: repository.audioURL(for: record).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: repository.videoURL(for: record).path))

        try await repository.delete(records: [record])

        let remaining = try await repository.loadHistory()
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.videoURL(for: record).path))
    }
}
