import AVFAudio
import AVFoundation
import XCTest
@testable import BALABOLKA

enum BalabolkaTestSupport {
    static func makeTemporaryDirectory(named name: String = UUID().uuidString) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "BALABOLKA-Tests-\(name)", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func makeToneWAVFile(
        duration: TimeInterval = 1.4,
        sampleRate: Int = 24_000,
        frequency: Double = 440
    ) throws -> URL {
        let directory = try makeTemporaryDirectory()
        let url = directory.appending(path: "fixture.wav")
        try WAVBuilder.makeMonoSineWave(duration: duration, sampleRate: sampleRate, frequency: frequency).write(to: url)
        return url
    }

    static func makePlaceholderVideoFile() throws -> URL {
        let directory = try makeTemporaryDirectory()
        let url = directory.appending(path: "placeholder.mp4")
        try Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70]).write(to: url)
        return url
    }

    static func makeProxyEnvelopeJSON(
        text: String = "Тестовая озвучка",
        voiceName: String = GeminiVoice.sulafat.rawValue
    ) throws -> Data {
        let envelope = ProxySynthesisEnvelope(
            requestId: UUID().uuidString,
            prompt: .init(
                preparedPrompt: "prompt",
                preparedTranscript: text
            ),
            voice: .init(name: voiceName, descriptor: "тёплый"),
            audio: .init(
                mimeType: "audio/wav",
                base64: WAVBuilder.makeMonoSineWave(duration: 1.1).base64EncodedString(),
                sampleRateHz: 24_000
            ),
            provider: .init(ttsModel: "gemini-test")
        )
        return try JSONEncoder().encode(envelope)
    }

    static func makeHTTPResponse(
        statusCode: Int = 200,
        url: URL = URL(string: "http://localhost:8787/v1/tts/synthesize")!
    ) -> HTTPURLResponse {
        guard let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil) else {
            fatalError("Failed to create HTTPURLResponse")
        }
        return response
    }
}

enum MediaAssetInspector {
    static func rootMeanSquareAmplitude(from asset: AVAsset) async throws -> Double {
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            XCTFail("Expected audio track in asset")
            return 0
        }

        let reader = try XCTUnwrap(AVAssetReader(asset: asset))
        let output = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        )
        output.alwaysCopiesSampleData = false
        XCTAssertTrue(reader.canAdd(output))
        reader.add(output)
        XCTAssertTrue(reader.startReading())

        var sumSquares = 0.0
        var sampleCount = 0

        while let sampleBuffer = output.copyNextSampleBuffer() {
            defer { CMSampleBufferInvalidate(sampleBuffer) }
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let dataLength = CMBlockBufferGetDataLength(blockBuffer)
            var data = Data(count: dataLength)

            let copyStatus = data.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(
                    blockBuffer,
                    atOffset: 0,
                    dataLength: dataLength,
                    destination: bytes.baseAddress!
                )
            }
            XCTAssertEqual(copyStatus, kCMBlockBufferNoErr)

            var offset = 0
            while offset + 1 < data.count {
                let lowByte = UInt16(data[offset])
                let highByte = UInt16(data[offset + 1])
                let rawSample = lowByte | (highByte << 8)
                let sampleValue = Int16(bitPattern: rawSample)
                let normalized: Double = Double(sampleValue) / 32767.0
                let squared: Double = normalized * normalized
                sumSquares += squared
                sampleCount += 1
                offset += MemoryLayout<Int16>.size
            }
        }

        if reader.status == .failed {
            throw try XCTUnwrap(reader.error)
        }

        guard sampleCount > 0 else { return 0 }
        return sqrt(sumSquares / Double(sampleCount))
    }
}
