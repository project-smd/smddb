// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import AppKit
import SwiftUI

@main
struct IngestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = IngestModel()
    @State private var library = ContainerLibrary()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // No fixed title: the content sets it — "Ingest" on the drive list, the disc's name once
        // one has been scanned.
        WindowGroup {
            ContentView()
                .environment(model)
                .task {
                    AppDelegate.model = model
                    // `--containers` opens the Containers window at launch, for working on it
                    // without going through the menu each time.
                    if CommandLine.arguments.contains("--containers") {
                        openWindow(id: ContainersWindow.id)
                    }
                    await model.start()
                }
        }
        .defaultSize(width: 1100, height: 760)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Containers") {
                    openWindow(id: ContainersWindow.id)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }

        // One window, not a group: there is one repository, and a second view of it would only
        // disagree with the first about what was selected.
        Window("Containers", id: ContainersWindow.id) {
            ContainersView()
                .environment(library)
        }
        .defaultSize(width: 960, height: 640)

        Settings {
            SettingsView()
        }
    }

    init() {
        Preferences.register()
    }
}

enum ContainersWindow {
    static let id = "containers"
}

/// Run as `Ingest.app` this changes nothing: the bundle's Info.plist makes it a regular app. Run as
/// the bare executable — `swift run Ingest`, which still works once `Scripts/build-app.sh` has staged
/// VLCKit — there is no bundle, so the process starts as an accessory and never takes focus.
/// Promoting it gives it a Dock icon, a menu bar, and a window that comes to the front.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the app so the engine, if one is running, is told to quit rather than killed.
    @MainActor static var model: IngestModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = Self.model else { return .terminateNow }
        Task { @MainActor in
            await model.shutdown()
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
