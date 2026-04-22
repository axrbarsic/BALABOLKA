import Foundation
import Photos

enum PhotoLibrarySaveError: LocalizedError {
    case accessDenied
    case unknown

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Приложению нужен доступ на добавление видео в Фото."
        case .unknown:
            "Не удалось сохранить видео в Фото."
        }
    }
}

actor PhotoLibraryVideoSaver {
    func saveVideo(at url: URL) async throws {
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else {
            throw PhotoLibrarySaveError.accessDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false

            PHPhotoLibrary.shared().performChanges({
                let creation = PHAssetCreationRequest.forAsset()
                creation.addResource(with: .video, fileURL: url, options: nil)
            }, completionHandler: { success, error in
                guard !resumed else { return }
                resumed = true

                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PhotoLibrarySaveError.unknown)
                }
            })
        }
    }
}
