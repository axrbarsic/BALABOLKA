import AVFAudio
import Foundation
import OSLog

protocol PlaybackAudioSessionBackend: AnyObject {
    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode) throws
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
}

final class SystemPlaybackAudioSessionBackend: PlaybackAudioSessionBackend {
    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode) throws {
        try AVAudioSession.sharedInstance().setCategory(category, mode: mode)
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        try AVAudioSession.sharedInstance().setActive(active, options: options)
    }
}

@MainActor
final class PlaybackAudioSessionCoordinator {
    static let shared = PlaybackAudioSessionCoordinator()

    private let backend: PlaybackAudioSessionBackend
    private let logger = Logger(subsystem: "AXR.BALABOLKA", category: "AudioSession")
    private let notificationCenter: NotificationCenter
    private var activeOwners: Set<UUID> = []
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private(set) var isConfigured = false

    var activePlaybackCount: Int {
        activeOwners.count
    }

    init(
        backend: PlaybackAudioSessionBackend = SystemPlaybackAudioSessionBackend(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.backend = backend
        self.notificationCenter = notificationCenter
        interruptionObserver = notificationCenter.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in
                self.handleInterruption(rawType: rawType)
            }
        }
        routeChangeObserver = notificationCenter.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in
                self.handleRouteChange(rawReason: rawReason)
            }
        }
    }

    deinit {
        if let interruptionObserver {
            notificationCenter.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            notificationCenter.removeObserver(routeChangeObserver)
        }
    }

    func prepareForPlayback() {
        guard !isConfigured else { return }

        do {
            try backend.setCategory(.playback, mode: .moviePlayback)
            isConfigured = true
        } catch {
            logger.error("Failed to configure audio session: \(error.localizedDescription, privacy: .public)")
        }
    }

    func beginPlayback(for owner: UUID) {
        prepareForPlayback()
        guard isConfigured else { return }

        let inserted = activeOwners.insert(owner).inserted
        guard inserted, activeOwners.count == 1 else { return }

        do {
            try backend.setActive(true, options: [])
        } catch {
            activeOwners.remove(owner)
            logger.error("Failed to activate audio session: \(error.localizedDescription, privacy: .public)")
        }
    }

    func endPlayback(for owner: UUID) {
        let removed = activeOwners.remove(owner) != nil
        guard removed, activeOwners.isEmpty else { return }

        deactivateSession()
    }

    func deactivateAllPlayback() {
        guard !activeOwners.isEmpty else { return }
        activeOwners.removeAll()
        deactivateSession()
    }

    private func deactivateSession() {
        do {
            try backend.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            logger.error("Failed to deactivate audio session: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleInterruption(rawType: UInt?) {
        guard let rawType, let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }

        switch type {
        case .began:
            logger.notice("Audio session interruption began")
            deactivateAllPlayback()
        case .ended:
            logger.notice("Audio session interruption ended")
        @unknown default:
            break
        }
    }

    private func handleRouteChange(rawReason: UInt?) {
        guard let rawReason, let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            logger.notice("Audio route changed: old device unavailable")
            deactivateAllPlayback()
        case .newDeviceAvailable:
            logger.notice("Audio route changed: new device available")
        default:
            logger.notice("Audio route changed: \(reason.rawValue, privacy: .public)")
        }
    }
}
