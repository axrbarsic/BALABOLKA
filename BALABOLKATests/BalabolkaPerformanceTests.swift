import XCTest
@testable import BALABOLKA

final class BalabolkaPerformanceTests: XCTestCase {
    func testSquareVideoExportPerformance() throws {
        let wavURL = try BalabolkaTestSupport.makeToneWAVFile(duration: 2.2)
        let envelope = try WaveformAnalyzer.analyze(audioURL: wavURL, frameRate: 30)
        let exporter = SquareVideoExporter()

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            let semaphore = DispatchSemaphore(value: 0)
            var exportedURL: URL?

            Task.detached {
                exportedURL = try? await exporter.export(audioURL: wavURL, envelope: envelope)
                semaphore.signal()
            }

            XCTAssertEqual(semaphore.wait(timeout: .now() + 20), .success)
            if let exportedURL {
                try? FileManager.default.removeItem(at: exportedURL)
            }
        }
    }
}
