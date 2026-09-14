// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import AppKit
import SwiftUI

@main
struct IngestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = IngestModel()

    var body: some Scene {
        // No fixed title: the content sets it — "Ingest" on the drive list, the disc's name once
        // one has been scanned.
        WindowGroup {
            ContentView()
                .environment(model)
                .task { await model.start() }
        }
        .defaultSize(width: 1100, height: 760)

        Settings {
            SettingsView()
        }
    }

    init() {
        Preferences.register()
    }
}

/// Run as a bare SwiftPM executable there is no app bundle, so the process starts as an accessory and
/// never takes focus. Promoting it to a regular app gives it a Dock icon, a menu bar, and a window
/// that comes to the front.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
