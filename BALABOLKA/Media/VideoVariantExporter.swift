import AVFoundation
import Foundation

enum VideoVariantExportError: LocalizedError {
    case sourceMissing
    case videoTrackMissing
    case exporterUnavailable

    var errorDescription: String? {
        switch self {
        case .sourceMissing:
            "Исходный файл видео не найден."
        case .videoTrackMissing:
            "В исходном ролике не найден video track."
        case .exporterUnavailable:
            "Не удалось подготовить экспорт выбранного профиля."
        }
    }
}

actor VideoVariantExporter {
    private let fileManager = FileManager.default

    func exportVariant(
        from sourceURL: URL,
        to outputURL: URL,
        profile: VideoQualityProfile
    ) async throws {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw VideoVariantExportError.sourceMissing
        }

        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            throw VideoVariantExportError.videoTrackMissing
        }

        let composition = AVMutableComposition()
        let range = CMTimeRange(start: .zero, duration: duration)

        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoVariantExportError.videoTrackMissing
        }

        try compositionVideoTrack.insertTimeRange(range, of: sourceVideoTrack, at: .zero)

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let sourceAudioTrack = audioTracks.first,
           let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try compositionAudioTrack.insertTimeRange(range, of: sourceAudioTrack, at: .zero)
        }

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: profile.exportPresetName) else {
            throw VideoVariantExportError.exporterUnavailable
        }

        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let transformedSize = naturalSize.applying(preferredTransform)
        let renderSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = range

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(preferredTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(profile.targetFrameRate))
        videoComposition.instructions = [instruction]

        exportSession.videoComposition = videoComposition
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = profile.shouldOptimizeForNetworkUse

        if profile == .xSmall {
            let seconds = max(CMTimeGetSeconds(duration), 1)
            let targetBytes = Int64((Double(profile.approximateTotalBitRate) * seconds) / 8.0)
            exportSession.fileLengthLimit = targetBytes
        }

        try await exportSession.export(to: outputURL, as: .mp4)
    }
}
