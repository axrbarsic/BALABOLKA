//
//  BALABOLKAApp.swift
//  BALABOLKA
//
//  Created by Alex Lane on 4/20/26.
//

import SwiftUI

@main
struct BALABOLKAApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            ContentView(model: container.model)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                PlaybackAudioSessionCoordinator.shared.deactivateAllPlayback()
            }
        }
    }
}
