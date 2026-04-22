import AVFoundation
import XCTest
@testable import BALABOLKA

final class WaveformPipelineTests: XCTestCase {
    func testAnalyzerBuildsNormalizedEnvelopeFromWAV() throws {
        let wavURL = try BalabolkaTestSupport.makeToneWAVFile(duration: 1.5)

        let envelope = try WaveformAnalyzer.analyze(audioURL: wavURL, frameRate: 30)

        XCTAssertEqual(envelope.frameRate, 30)
        XCTAssertGreaterThan(envelope.duration, 1.45)
        XCTAssertFalse(envelope.samples.isEmpty)
        XCTAssertTrue(envelope.samples.allSatisfy { $0 >= 0.02 && $0 <= 1.0 })
        XCTAssertGreaterThan(envelope.samples.max() ?? 0, 0.4)
    }

    func testExporterProduces720SquareVideoWithAudibleTrack() async throws {
        let wavURL = try BalabolkaTestSupport.makeToneWAVFile(duration: 1.8)
        let envelope = try WaveformAnalyzer.analyze(audioURL: wavURL, frameRate: 30)
        let exporter = SquareVideoExporter()

        let outputURL = try await exporter.export(audioURL: wavURL, envelope: envelope)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let asset = AVURLAsset(url: outputURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertEqual(audioTracks.count, 1)

        let naturalSize = try await videoTracks[0].load(.naturalSize)
        XCTAssertEqual(Int(naturalSize.width), 720)
        XCTAssertEqual(Int(naturalSize.height), 720)

        let audioRMS = try await MediaAssetInspector.rootMeanSquareAmplitude(from: asset)
        XCTAssertGreaterThan(audioRMS, 0.02)
    }

    func testVideoVariantExporterProducesSmallProfileWithAudio() async throws {
        let wavURL = try BalabolkaTestSupport.makeToneWAVFile(duration: 1.8)
        let envelope = try WaveformAnalyzer.analyze(audioURL: wavURL, frameRate: 30)
        let exporter = SquareVideoExporter()
        let variantExporter = VideoVariantExporter()

        let masterURL = try await exporter.export(audioURL: wavURL, envelope: envelope, profile: .hq)
        let smallURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)-x-small.mp4")
        defer {
            try? FileManager.default.removeItem(at: masterURL)
            try? FileManager.default.removeItem(at: smallURL)
        }

        try await variantExporter.exportVariant(from: masterURL, to: smallURL, profile: .xSmall)

        let asset = AVURLAsset(url: smallURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertEqual(audioTracks.count, 1)

        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(CMTimeGetSeconds(duration), 1.0)
    }
}
