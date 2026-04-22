import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import UIKit

struct WaveformEnvelope: Sendable {
    let samples: [Float]
    let duration: TimeInterval
    let frameRate: Int

    func amplitude(at time: TimeInterval) -> CGFloat {
        guard !samples.isEmpty else { return 0.02 }
        guard duration > 0 else { return CGFloat(samples[0]) }

        let clampedTime = min(max(time, 0), duration)
        let position = (clampedTime / duration) * Double(max(samples.count - 1, 1))
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = min(lowerIndex + 1, samples.count - 1)
        let fraction = Float(position - Double(lowerIndex))
        let lower = samples[lowerIndex]
        let upper = samples[upperIndex]
        return CGFloat(lower + ((upper - lower) * fraction))
    }
}

enum WaveformAnalyzer {
    private static let pcmReader = BALAudioPCMReader()

    static func analyze(audioURL: URL, frameRate: Int = 30) throws -> WaveformEnvelope {
        let pcm = try pcmReader.readMonoPCM(from: audioURL)
        let samples = makeEnvelopeSamples(from: pcm.samples, duration: pcm.duration, frameRate: frameRate)

        return WaveformEnvelope(
            samples: samples,
            duration: max(pcm.duration, 1.0 / Double(max(frameRate, 1))),
            frameRate: max(frameRate, 1)
        )
    }

    private static func makeEnvelopeSamples(
        from pcmSamples: [Float],
        duration: TimeInterval,
        frameRate: Int
    ) -> [Float] {
        guard !pcmSamples.isEmpty else { return [0.02] }

        let detailRate = max(frameRate * 6, 180)
        let targetSampleCount = max(Int(ceil(duration * Double(detailRate))), 120)
        let windowSize = max(pcmSamples.count / targetSampleCount, 1)

        var envelope: [Float] = []
        envelope.reserveCapacity(targetSampleCount)

        var index = 0
        while index < pcmSamples.count {
            let upperBound = min(index + windowSize, pcmSamples.count)
            let window = pcmSamples[index..<upperBound]

            var peak: Float = 0
            var energy: Float = 0

            for sample in window {
                let magnitude = abs(sample)
                peak = max(peak, magnitude)
                energy += magnitude * magnitude
            }

            let count = Float(max(window.count, 1))
            let rms = sqrt(energy / count)
            let shaped = min(max((peak * 0.6) + (rms * 0.9), 0.015), 1)
            envelope.append(shaped)
            index = upperBound
        }

        let normalized = normalize(envelope)
        let smoothed = smooth(normalized)
        return smoothed.isEmpty ? [0.02] : smoothed
    }

    private static func normalize(_ values: [Float]) -> [Float] {
        guard let maximum = values.max(), maximum > 0 else {
            return Array(repeating: 0.02, count: max(values.count, 1))
        }

        let floor: Float = 0.02
        let scale = max(maximum, 0.12)
        return values.map { sample in
            min(max((sample / scale) * 0.92, floor), 1)
        }
    }

    private static func smooth(_ values: [Float]) -> [Float] {
        guard values.count > 2 else { return values }

        let kernel: [Float] = [1, 2, 3, 2, 1]
        let radius = kernel.count / 2

        return values.indices.map { index in
            var weightedSum: Float = 0
            var totalWeight: Float = 0

            for kernelOffset in kernel.indices {
                let sampleIndex = index + kernelOffset - radius
                guard values.indices.contains(sampleIndex) else { continue }
                let weight = kernel[kernelOffset]
                weightedSum += values[sampleIndex] * weight
                totalWeight += weight
            }

            return totalWeight > 0 ? (weightedSum / totalWeight) : values[index]
        }
    }
}

enum WaveformProfile {
    private static let visibleTimeSpan: TimeInterval = 3.2

    static func samples(for time: TimeInterval, envelope: WaveformEnvelope, columns: Int) -> [CGFloat] {
        guard columns > 0 else { return [] }

        var rendered: [CGFloat] = []
        rendered.reserveCapacity(columns)

        for index in 0..<columns {
            let progress: Double
            if columns == 1 {
                progress = 0.5
            } else {
                progress = Double(index) / Double(columns - 1)
            }

            let relativeOffset = (progress - 0.5) * visibleTimeSpan
            let sampleTime = time + relativeOffset
            let amplitude = envelope.amplitude(at: sampleTime)
            let centerDistance = abs((progress - 0.5) * 2)
            let focusBoost = CGFloat(0.82 + (0.22 * (1 - centerDistance)))
            rendered.append(min(max(amplitude * focusBoost, 0.02), 1))
        }

        return rendered
    }
}

enum WaveformVectorRenderer {
    static func path(in rect: CGRect, samples: [CGFloat]) -> CGPath {
        let safeSamples = samples.isEmpty ? [0.05, 0.08, 0.05] : samples
        let path = CGMutablePath()
        let centerY = rect.midY
        let maxHeight = rect.height * 0.34
        let stepX = rect.width / CGFloat(max(safeSamples.count - 1, 1))

        path.move(to: CGPoint(x: rect.minX, y: centerY))

        for (index, sample) in safeSamples.enumerated() {
            let x = rect.minX + (CGFloat(index) * stepX)
            let y = centerY - (maxHeight * sample)
            path.addLine(to: CGPoint(x: x, y: y))
        }

        for (index, sample) in safeSamples.enumerated().reversed() {
            let x = rect.minX + (CGFloat(index) * stepX)
            let y = centerY + (maxHeight * sample)
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.closeSubpath()
        return path
    }
}

enum WaveformExportError: LocalizedError {
    case writerUnavailable
    case pixelBufferPoolUnavailable
    case cannotAppendFrame
    case missingVideoTrack
    case missingAudioTrack
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .writerUnavailable:
            return "Не удалось создать video writer."
        case .pixelBufferPoolUnavailable:
            return "Не удалось подготовить pixel buffer pool."
        case .cannotAppendFrame:
            return "Не удалось добавить кадр в видео."
        case .missingVideoTrack:
            return "Не найден video track для финального mux."
        case .missingAudioTrack:
            return "Не найден audio track для финального mux."
        case .exportFailed:
            return "Не удалось экспортировать итоговый ролик."
        }
    }
}

actor SquareVideoExporter {
    private let canvasSize = CGSize(width: 720, height: 720)
    private let waveformRect = CGRect(x: 68, y: 214, width: 584, height: 292)
    private let columnCount = 88

    func export(
        audioURL: URL,
        envelope: WaveformEnvelope,
        profile: VideoQualityProfile = .hq,
        progress: (@Sendable (Double) async -> Void)? = nil
    ) async throws -> URL {
        let intermediateURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)-video.mov")
        let outputURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
        let renderEnvelope = WaveformEnvelope(
            samples: envelope.samples,
            duration: envelope.duration,
            frameRate: profile.targetFrameRate
        )
        var shouldCleanupOutput = true

        defer {
            try? FileManager.default.removeItem(at: intermediateURL)
            if shouldCleanupOutput {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        await progress?(0.02)
        try await renderVideoOnly(to: intermediateURL, envelope: renderEnvelope, profile: profile) { renderFraction in
            await progress?(0.1 + (renderFraction * 0.78))
        }
        await progress?(0.92)
        try await mux(videoURL: intermediateURL, audioURL: audioURL, outputURL: outputURL)
        await progress?(1)
        shouldCleanupOutput = false
        return outputURL
    }

    private func renderVideoOnly(
        to outputURL: URL,
        envelope: WaveformEnvelope,
        profile: VideoQualityProfile,
        progress: (@Sendable (Double) async -> Void)? = nil
    ) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mov) else {
            throw WaveformExportError.writerUnavailable
        }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(canvasSize.width),
            AVVideoHeightKey: Int(canvasSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: profile.approximateTotalBitRate,
                AVVideoExpectedSourceFrameRateKey: profile.targetFrameRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(canvasSize.width),
            kCVPixelBufferHeightKey as String: Int(canvasSize.height)
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)

        guard writer.canAdd(input) else {
            throw WaveformExportError.writerUnavailable
        }

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let totalFrames = max(Int(ceil(envelope.duration * Double(envelope.frameRate))), 1)
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(envelope.frameRate))

        for frameIndex in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }

            guard let pool = adaptor.pixelBufferPool else {
                throw WaveformExportError.pixelBufferPoolUnavailable
            }

            let currentTime = Double(frameIndex) / Double(envelope.frameRate)
            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
            let buffer = try makePixelBuffer(from: pool, time: currentTime, envelope: envelope)

            guard adaptor.append(buffer, withPresentationTime: presentationTime) else {
                throw writer.error ?? WaveformExportError.cannotAppendFrame
            }

            if frameIndex.isMultiple(of: max(totalFrames / 24, 1)) || frameIndex == totalFrames - 1 {
                let fraction = Double(frameIndex + 1) / Double(totalFrames)
                await progress?(fraction)
            }
        }

        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error {
            throw error
        }
    }

    private func makePixelBuffer(
        from pool: CVPixelBufferPool,
        time: TimeInterval,
        envelope: WaveformEnvelope
    ) throws -> CVPixelBuffer {
        var maybeBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybeBuffer)

        guard let buffer = maybeBuffer else {
            throw WaveformExportError.pixelBufferPoolUnavailable
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard
            let baseAddress = CVPixelBufferGetBaseAddress(buffer),
            let context = CGContext(
                data: baseAddress,
                width: Int(canvasSize.width),
                height: Int(canvasSize.height),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            )
        else {
            throw WaveformExportError.pixelBufferPoolUnavailable
        }

        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        context.setFillColor(UIColor.white.cgColor)
        context.fill(canvasRect)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        let baselineY = waveformRect.midY
        context.setStrokeColor(UIColor(red: 0.88, green: 0.88, blue: 0.88, alpha: 1).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: waveformRect.minX, y: baselineY))
        context.addLine(to: CGPoint(x: waveformRect.maxX, y: baselineY))
        context.strokePath()

        let samples = WaveformProfile.samples(for: time, envelope: envelope, columns: columnCount)
        let wavePath = WaveformVectorRenderer.path(in: waveformRect, samples: samples)

        context.addPath(wavePath)
        context.setFillColor(UIColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1).cgColor)
        context.fillPath()

        return buffer
    }

    private func mux(videoURL: URL, audioURL: URL, outputURL: URL) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        let composition = AVMutableComposition()
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)

        guard
            let videoTrack = videoTracks.first,
            let audioTrack = audioTracks.first
        else {
            throw videoTracks.isEmpty
                ? WaveformExportError.missingVideoTrack
                : WaveformExportError.missingAudioTrack
        }

        let videoDuration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        let duration = CMTimeMinimum(videoDuration, audioDuration)
        let range = CMTimeRange(start: .zero, duration: duration)

        guard let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw WaveformExportError.missingVideoTrack
        }
        guard let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw WaveformExportError.missingAudioTrack
        }

        try compositionVideoTrack.insertTimeRange(range, of: videoTrack, at: .zero)
        compositionVideoTrack.preferredTransform = try await videoTrack.load(.preferredTransform)
        try compositionAudioTrack.insertTimeRange(range, of: audioTrack, at: .zero)

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw WaveformExportError.exportFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = false

        try await exportSession.export(to: outputURL, as: .mp4)
    }
}
