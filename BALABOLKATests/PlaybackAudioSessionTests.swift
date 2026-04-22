import AVFAudio
import XCTest
@testable import BALABOLKA

@MainActor
final class PlaybackAudioSessionTests: XCTestCase {
    func testBeginPlaybackConfiguresAndActivatesSession() {
        let backend = MockPlaybackAudioSessionBackend()
        let coordinator = PlaybackAudioSessionCoordinator(backend: backend)
        let owner = UUID()

        coordinator.beginPlayback(for: owner)

        XCTAssertEqual(backend.categoryCalls.count, 1)
        XCTAssertEqual(backend.categoryCalls.first?.category, .playback)
        XCTAssertEqual(backend.categoryCalls.first?.mode, .moviePlayback)
        XCTAssertEqual(
            backend.activationCalls,
            [.init(active: true, options: [])]
        )
        XCTAssertTrue(coordinator.isConfigured)
        XCTAssertEqual(coordinator.activePlaybackCount, 1)
    }

    func testSameOwnerDoesNotRepeatedlyActivateSession() {
        let backend = MockPlaybackAudioSessionBackend()
        let coordinator = PlaybackAudioSessionCoordinator(backend: backend)
        let owner = UUID()

        coordinator.beginPlayback(for: owner)
        coordinator.beginPlayback(for: owner)

        XCTAssertEqual(backend.categoryCalls.count, 1)
        XCTAssertEqual(
            backend.activationCalls,
            [.init(active: true, options: [])]
        )
        XCTAssertEqual(coordinator.activePlaybackCount, 1)

        coordinator.endPlayback(for: owner)
        XCTAssertEqual(coordinator.activePlaybackCount, 0)
    }

    func testDifferentOwnersKeepSessionActiveUntilLastOwnerEnds() {
        let backend = MockPlaybackAudioSessionBackend()
        let coordinator = PlaybackAudioSessionCoordinator(backend: backend)
        let firstOwner = UUID()
        let secondOwner = UUID()

        coordinator.beginPlayback(for: firstOwner)
        coordinator.beginPlayback(for: secondOwner)
        coordinator.endPlayback(for: firstOwner)

        XCTAssertEqual(coordinator.activePlaybackCount, 1)
        XCTAssertEqual(
            backend.activationCalls,
            [.init(active: true, options: [])]
        )

        coordinator.endPlayback(for: secondOwner)

        XCTAssertEqual(
            backend.activationCalls,
            [
                .init(active: true, options: []),
                .init(active: false, options: [.notifyOthersOnDeactivation])
            ]
        )
        XCTAssertEqual(coordinator.activePlaybackCount, 0)
    }

    func testInterruptionBeganDeactivatesAllPlayback() {
        let backend = MockPlaybackAudioSessionBackend()
        let notificationCenter = NotificationCenter()
        let coordinator = PlaybackAudioSessionCoordinator(
            backend: backend,
            notificationCenter: notificationCenter
        )
        let owner = UUID()

        coordinator.beginPlayback(for: owner)
        notificationCenter.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(coordinator.activePlaybackCount, 0)
        XCTAssertEqual(
            backend.activationCalls,
            [
                .init(active: true, options: []),
                .init(active: false, options: [.notifyOthersOnDeactivation])
            ]
        )
    }

    func testOldDeviceUnavailableRouteChangeDeactivatesAllPlayback() {
        let backend = MockPlaybackAudioSessionBackend()
        let notificationCenter = NotificationCenter()
        let coordinator = PlaybackAudioSessionCoordinator(
            backend: backend,
            notificationCenter: notificationCenter
        )
        let owner = UUID()

        coordinator.beginPlayback(for: owner)
        notificationCenter.post(
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue]
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(coordinator.activePlaybackCount, 0)
        XCTAssertEqual(
            backend.activationCalls,
            [
                .init(active: true, options: []),
                .init(active: false, options: [.notifyOthersOnDeactivation])
            ]
        )
    }
}

private final class MockPlaybackAudioSessionBackend: PlaybackAudioSessionBackend {
    struct CategoryCall: Equatable {
        let category: AVAudioSession.Category
        let mode: AVAudioSession.Mode
    }

    struct ActivationCall: Equatable {
        let active: Bool
        let options: AVAudioSession.SetActiveOptions
    }

    var categoryCalls: [CategoryCall] = []
    var activationCalls: [ActivationCall] = []

    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode) throws {
        categoryCalls.append(CategoryCall(category: category, mode: mode))
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        activationCalls.append(ActivationCall(active: active, options: options))
    }
}
