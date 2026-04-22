import Foundation

actor LibraryUseCase {
    private let repository: LibraryRepository
    private let variantExporter: VideoVariantExporter
    private let photoLibrarySaver: PhotoLibraryVideoSaver

    init(
        repository: LibraryRepository,
        variantExporter: VideoVariantExporter,
        photoLibrarySaver: PhotoLibraryVideoSaver
    ) {
        self.repository = repository
        self.variantExporter = variantExporter
        self.photoLibrarySaver = photoLibrarySaver
    }

    func loadHistory() async throws -> [GenerationRecord] {
        try await repository.loadHistory()
    }

    func delete(records: [GenerationRecord]) async throws {
        try await repository.delete(records: records)
    }

    func preparedVideoURL(for record: GenerationRecord, profile: VideoQualityProfile) async throws -> URL {
        let existingURL = repository.videoURL(for: record, profile: profile)
        if FileManager.default.fileExists(atPath: existingURL.path) {
            return existingURL
        }

        let masterURL = repository.videoURL(for: record, profile: .hq)
        guard FileManager.default.fileExists(atPath: masterURL.path) else {
            throw BalabolkaError.fileMissing
        }

        guard profile != .hq else {
            return masterURL
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: "\(record.id.uuidString)-\(profile.fileNameSuffix).mp4")

        try await variantExporter.exportVariant(from: masterURL, to: tempURL, profile: profile)
        return try await repository.storeVideoVariant(at: tempURL, for: record, profile: profile)
    }

    func saveVideoToPhotos(for record: GenerationRecord, profile: VideoQualityProfile) async throws {
        let url = try await preparedVideoURL(for: record, profile: profile)
        try await photoLibrarySaver.saveVideo(at: url)
    }
}
