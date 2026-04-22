import Observation

@MainActor
@Observable
final class AppContainer {
    let settingsStore: SettingsStore
    let model: BalabolkaAppModel

    init(
        settingsStore: SettingsStore,
        repository: LibraryRepository,
        proxyClient: ProxyClient,
        exporter: SquareVideoExporter,
        variantExporter: VideoVariantExporter,
        photoLibrarySaver: PhotoLibraryVideoSaver
    ) {
        let generateUseCase = GenerateSpeechVideoUseCase(
            proxyClient: proxyClient,
            exporter: exporter,
            repository: repository
        )
        let libraryUseCase = LibraryUseCase(
            repository: repository,
            variantExporter: variantExporter,
            photoLibrarySaver: photoLibrarySaver
        )

        self.settingsStore = settingsStore
        self.model = BalabolkaAppModel(
            settingsStore: settingsStore,
            repository: repository,
            generateUseCase: generateUseCase,
            libraryUseCase: libraryUseCase
        )
    }

    convenience init() {
        self.init(
            settingsStore: SettingsStore(),
            repository: LibraryRepository(),
            proxyClient: ProxyClient(),
            exporter: SquareVideoExporter(),
            variantExporter: VideoVariantExporter(),
            photoLibrarySaver: PhotoLibraryVideoSaver()
        )
    }
}
