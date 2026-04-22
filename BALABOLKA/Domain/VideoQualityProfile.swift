import AVFoundation
import Foundation

enum VideoQualityProfile: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case hq
    case xSmall

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hq:
            "HQ"
        case .xSmall:
            "X / Small"
        }
    }

    var subtitle: String {
        switch self {
        case .hq:
            "Максимально чистая версия 720×720."
        case .xSmall:
            "Сильно сжатая копия для публикации."
        }
    }

    var caption: String {
        switch self {
        case .hq:
            "30 fps, приоритет качества"
        case .xSmall:
            "24 fps, network-optimized"
        }
    }

    var fileNameSuffix: String {
        switch self {
        case .hq:
            "hq"
        case .xSmall:
            "x-small"
        }
    }

    var targetFrameRate: Int {
        switch self {
        case .hq:
            30
        case .xSmall:
            24
        }
    }

    var exportPresetName: String {
        switch self {
        case .hq:
            AVAssetExportPresetHighestQuality
        case .xSmall:
            AVAssetExportPresetLowQuality
        }
    }

    var shouldOptimizeForNetworkUse: Bool {
        switch self {
        case .hq:
            false
        case .xSmall:
            true
        }
    }

    var approximateTotalBitRate: Int {
        switch self {
        case .hq:
            2_600_000
        case .xSmall:
            620_000
        }
    }
}
