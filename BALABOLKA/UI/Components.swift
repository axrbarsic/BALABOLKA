import AVKit
import SwiftUI
import UIKit

enum AppTheme {
    static let background = Color(red: 0.97, green: 0.96, blue: 0.93)
    static let panel = Color.white
    static let ink = Color(red: 0.11, green: 0.12, blue: 0.14)
    static let secondaryInk = Color(red: 0.28, green: 0.29, blue: 0.32)
    static let accent = Color(red: 0.93, green: 0.43, blue: 0.28)
    static let accentSoft = Color(red: 0.98, green: 0.91, blue: 0.86)
}

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .background(AppTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 18, x: 0, y: 10)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.ink.opacity(configuration.isPressed ? 0.9 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(AppTheme.ink)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.88 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

struct ExpressiveCardView: View {
    let preset: ExpressivePreset
    let isSelected: Bool

    var body: some View {
        let supportingColor = isSelected ? Color.white : AppTheme.secondaryInk

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: preset.cardIcon)
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(preset.cardChip)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isSelected ? AppTheme.accent : AppTheme.ink)
                    .clipShape(Capsule())
            }

            Text(preset.title)
                .font(.title3.weight(.bold))
                .fontDesign(.rounded)

            Text(preset.shortDescription)
                .font(.subheadline)
                .foregroundStyle(supportingColor)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Label(preset.recommendedVoice.rawValue, systemImage: "waveform")
                .font(.caption)
                .foregroundStyle(supportingColor)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isSelected ? AppTheme.ink : Color.white.opacity(0.88))
        )
        .foregroundStyle(isSelected ? Color.white : AppTheme.ink)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isSelected ? AppTheme.accent : Color.black.opacity(0.05), lineWidth: isSelected ? 2 : 1)
        )
    }
}

struct WaveformThumbnailView: View {
    let samples: [Float]

    var body: some View {
        GeometryReader { geometry in
            let cgSamples = samples.isEmpty
                ? Array(repeating: CGFloat(0.05), count: 48)
                : stride(from: 0, to: samples.count, by: max(samples.count / 48, 1)).map { CGFloat(samples[$0]) }

            Canvas { context, size in
                let path = Path(WaveformVectorRenderer.path(in: CGRect(origin: .zero, size: size), samples: cgSamples))
                context.fill(path, with: .color(AppTheme.ink))
            }
        }
    }
}

struct VideoPreviewCard: View {
    let title: String
    let subtitle: String
    let videoURL: URL?
    let envelope: [Float]

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.title3.weight(.bold))
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryInk)
                    }
                    Spacer()
                }

                if let videoURL {
                    InlineVideoPlayer(url: videoURL)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    WaveformThumbnailView(samples: envelope)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .padding(18)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
        }
        .accessibilityIdentifier("preview.card")
    }
}

struct GenerationProgressPanel: View {
    let progress: GenerationProgressState

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Генерация")
                            .font(.headline)
                        Text(progress.detailText)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryInk)
                    }

                    Spacer()

                    Text(progress.percentText)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.accent)
                        .monospacedDigit()
                }

                VStack(alignment: .leading, spacing: 10) {
                    ProgressView(value: progress.fractionCompleted)
                        .tint(AppTheme.accent)
                        .accessibilityIdentifier("generation.progressBar")

                    HStack(spacing: 10) {
                        ActivityWaveView(progress: progress)
                            .frame(width: 68, height: 18)
                            .accessibilityHidden(true)

                        Text(stageProgressText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.secondaryInk)
                            .monospacedDigit()

                        Spacer()
                    }

                    HStack(spacing: 8) {
                        ForEach(GenerationProgressStage.allCases, id: \.self) { stage in
                            ProgressStageChip(
                                title: stage.title,
                                state: chipState(for: stage)
                            )
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("generation.progressPanel")
    }

    private func chipState(for stage: GenerationProgressStage) -> ProgressStageChip.State {
        if stage.rawValue < progress.stage.rawValue {
            return .completed
        }

        if stage == progress.stage {
            return .active
        }

        return .pending
    }

    private var stageProgressText: String {
        let stagePercent = Int((progress.stageFraction * 100).rounded())
        return "\(progress.stage.title.lowercased()) · \(stagePercent)% этапа"
    }
}

private struct ActivityWaveView: View {
    let progress: GenerationProgressState

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: false)) { timeline in
            let baseTime = timeline.date.timeIntervalSinceReferenceDate

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<6, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(index < activeBarCount ? AppTheme.accent : AppTheme.accentSoft)
                        .frame(width: 7, height: barHeight(for: index, time: baseTime))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var activeBarCount: Int {
        max(1, Int(round(progress.stageFraction * 5)))
    }

    private func barHeight(for index: Int, time: TimeInterval) -> CGFloat {
        let amplitude = 6.0 + (progress.stageFraction * 5.0)
        let wave = sin((time * 6.4) + Double(index) * 0.95 + Double(progress.stage.rawValue))
        let normalized = (wave + 1) / 2
        return CGFloat(6.0 + normalized * amplitude)
    }
}

private struct ProgressStageChip: View {
    enum State {
        case completed
        case active
        case pending
    }

    let title: String
    let state: State

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(backgroundColor)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(borderColor, lineWidth: state == .active ? 1.5 : 1)
            )
    }

    private var foregroundColor: Color {
        switch state {
        case .completed:
            .white
        case .active:
            AppTheme.ink
        case .pending:
            AppTheme.secondaryInk
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .completed:
            AppTheme.ink
        case .active:
            AppTheme.accentSoft
        case .pending:
            Color.white
        }
    }

    private var borderColor: Color {
        switch state {
        case .completed:
            AppTheme.ink
        case .active:
            AppTheme.accent
        case .pending:
            Color.black.opacity(0.08)
        }
    }
}

struct GenerationExportPanel: View {
    @Bindable var model: BalabolkaAppModel
    let record: GenerationRecord

    @State private var selectedProfile: VideoQualityProfile = .hq
    @State private var isWorking = false
    @State private var shareURL: URL?
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Экспорт")
                            .font(.headline)
                        Text(selectedProfile.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryInk)
                    }

                    Spacer()

                    Text(selectedProfile.caption)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.accentSoft)
                        .clipShape(Capsule())
                }

                Picker("Профиль", selection: $selectedProfile) {
                    ForEach(VideoQualityProfile.allCases) { profile in
                        Text(profile.title).tag(profile)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("export.profile")

                HStack(spacing: 12) {
                    Button {
                        prepareShare()
                    } label: {
                        Label(isWorking ? "Готовлю…" : "Поделиться", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isWorking)
                    .accessibilityIdentifier("export.share")

                    Button {
                        saveToPhotos()
                    } label: {
                        Label(isWorking ? "Сохраняю…" : "В Фото", systemImage: "arrow.down.to.line")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(isWorking)
                    .accessibilityIdentifier("export.save")
                }

                Text("Локально: можно выгрузить чистый master или сильно сжатую X-копию.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
        }
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: { if !$0 { shareURL = nil } }
        )) {
            if let shareURL {
                ActivityShareSheet(items: [shareURL])
            }
        }
        .alert("Готово", isPresented: Binding(
            get: { statusMessage != nil },
            set: { if !$0 { statusMessage = nil } }
        )) {
            Button("ОК", role: .cancel) {}
        } message: {
            Text(statusMessage ?? "")
        }
        .alert("Ошибка", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("ОК", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func prepareShare() {
        runTask {
            shareURL = try await model.preparedVideoURL(for: record, profile: selectedProfile)
        }
    }

    private func saveToPhotos() {
        runTask {
            try await model.saveVideoToPhotos(for: record, profile: selectedProfile)
            statusMessage = "Видео сохранено в Фото."
        }
    }

    private func runTask(_ operation: @escaping () async throws -> Void) {
        guard !isWorking else { return }

        Task { @MainActor in
            isWorking = true
            defer { isWorking = false }

            do {
                try await operation()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct InlineVideoPlayer: View {
    let url: URL
    @State private var controller = InlineVideoPlayerController()

    var body: some View {
        VideoPlayer(player: controller.player)
            .task(id: url) {
                controller.load(
                    url: url,
                    autoplayDisabled: BalabolkaRuntime.disableInlineAutoplay
                )
            }
            .onDisappear {
                controller.teardown()
            }
    }
}

@MainActor
private final class InlineVideoPlayerController {
    let player = AVPlayer()

    private let playbackOwner = UUID()
    private var currentURL: URL?
    private var isPlaybackSessionActive = false
    private var timeControlObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    init() {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                self?.handleTimeControlStatusChange(player.timeControlStatus)
            }
        }
    }

    func load(url: URL, autoplayDisabled: Bool) {
        if currentURL != url {
            pauseAndDeactivate()
            currentURL = url

            let item = AVPlayerItem(url: url)
            observePlaybackEnd(for: item)
            player.replaceCurrentItem(with: item)
        }

        player.isMuted = false
        player.volume = 1

        if autoplayDisabled {
            player.pause()
        } else {
            activateAudioSessionIfNeeded()
            player.play()
        }
    }

    func teardown() {
        pauseAndDeactivate()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player.replaceCurrentItem(with: nil)
        currentURL = nil
    }

    private func observePlaybackEnd(for item: AVPlayerItem) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.player.seek(to: .zero)
                self.pauseAndDeactivate()
            }
        }
    }

    private func handleTimeControlStatusChange(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            activateAudioSessionIfNeeded()
        case .paused:
            deactivateAudioSessionIfNeeded()
        case .waitingToPlayAtSpecifiedRate:
            break
        @unknown default:
            break
        }
    }

    private func activateAudioSessionIfNeeded() {
        guard !isPlaybackSessionActive else { return }
        PlaybackAudioSessionCoordinator.shared.beginPlayback(for: playbackOwner)
        isPlaybackSessionActive = true
    }

    private func deactivateAudioSessionIfNeeded() {
        guard isPlaybackSessionActive else { return }
        PlaybackAudioSessionCoordinator.shared.endPlayback(for: playbackOwner)
        isPlaybackSessionActive = false
    }

    private func pauseAndDeactivate() {
        player.pause()
        deactivateAudioSessionIfNeeded()
    }
}
