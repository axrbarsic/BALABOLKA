import Foundation

enum LongFormAudioStitcherError: LocalizedError {
    case noSegments
    case sampleRateMismatch(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .noSegments:
            return "Нет аудио-сегментов для склейки."
        case let .sampleRateMismatch(expected, actual):
            return "Частота дискретизации сегмента не совпадает: ожидалось \(expected), получено \(actual)."
        }
    }
}

struct LongFormAudioStitchResult: Sendable {
    let wavData: Data
    let sampleRate: Int
    let duration: TimeInterval
}

enum LongFormAudioStitcher {
    private static let reader = BALAudioPCMReader()

    static func stitchWAVFiles(
        at urls: [URL],
        insertedGapMilliseconds: Int = 80
    ) throws -> LongFormAudioStitchResult {
        guard !urls.isEmpty else { throw LongFormAudioStitcherError.noSegments }

        var stitchedSamples: [Float] = []
        var expectedSampleRate: Int?
        var totalDuration: TimeInterval = 0

        for (index, url) in urls.enumerated() {
            let decoded = try reader.readMonoPCM(from: url)
            let roundedSampleRate = Int(decoded.sampleRate.rounded())

            if let expectedSampleRate, expectedSampleRate != roundedSampleRate {
                throw LongFormAudioStitcherError.sampleRateMismatch(
                    expected: expectedSampleRate,
                    actual: roundedSampleRate
                )
            }

            expectedSampleRate = expectedSampleRate ?? roundedSampleRate
            stitchedSamples.append(contentsOf: decoded.samples)
            totalDuration += decoded.duration

            if index < urls.count - 1, let sampleRate = expectedSampleRate {
                let gapSampleCount = max((sampleRate * insertedGapMilliseconds) / 1_000, 0)
                if gapSampleCount > 0 {
                    stitchedSamples.append(contentsOf: Array(repeating: 0, count: gapSampleCount))
                    totalDuration += Double(gapSampleCount) / Double(sampleRate)
                }
            }
        }

        let sampleRate = expectedSampleRate ?? 24_000
        let wavData = WAVBuilder.wrapMonoFloatPCM16(stitchedSamples, sampleRate: sampleRate)
        return LongFormAudioStitchResult(
            wavData: wavData,
            sampleRate: sampleRate,
            duration: totalDuration
        )
    }
}
