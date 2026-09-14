// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import AppKit
import MakeMKV
import MakeMKVRobot
import SwiftUI

/// What can be selected in the title outline: a title, or one of its streams. With nothing selected
/// the info pane describes the disc, which has no row of its own.
enum Node: Hashable {
    case title(Int)
    case stream(title: Int, stream: Int)
}

/// The window: a sidebar of the workflow's stages, and the selected stage's own view.
@MainActor
struct ContentView: View {
    @Environment(IngestModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            // Rows are tagged with the stage itself, since the selection is a Stage and not its id.
            List(selection: Binding(get: { model.stage }, set: { model.stage = $0 ?? model.stage })) {
                ForEach(Stage.allCases) { stage in
                    Label(stage.title, systemImage: stage.systemImage)
                        .badge(stage == .assign ? model.assignQueue.count : 0)
                        .tag(stage)
                }
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170)
        } detail: {
            switch model.stage {
            case .import:
                ImportView()
            case .assign:
                AssignView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.windowBecameActive() }
        }
    }
}

/// The Import stage. Two screens: before a scan the only thing to do is start one, so that screen
/// is the drives; after a scan the view is MakeMKV's — titles, tracks, and the Import button.
@MainActor
struct ImportView: View {
    @Environment(IngestModel.self) private var model
    @State private var selection: Node?
    @State private var logPresented = true

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if let error = model.startupError {
                startupFailure(error)
            } else if model.scan == nil {
                DriveList()
            } else {
                HSplitView {
                    TitleOutline(selection: $selection)
                        .frame(minWidth: 420, idealWidth: 600)
                    InfoPane(selection: selection)
                        .frame(minWidth: 320, idealWidth: 420)
                }
                Divider()
                progressBar
            }
            if logPresented {
                Divider()
                LogView()
                    .frame(height: 160)
            }
        }
        .navigationTitle(model.scan?.disc?.name ?? "Import")
        .toolbar { toolbar }
        .onChange(of: model.scan) { selection = nil }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if model.scan != nil {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    Task { await model.discardScan() }
                } label: {
                    Label("Drives", systemImage: "chevron.left")
                }
                .help("Back to the drive list")
                .disabled(model.phase.isBusy)
            }
            ToolbarItem(placement: .primaryAction) {
                // The next step, and the one thing on this screen drawn in the accent colour.
                Button {
                    model.importSelectedTitles()
                } label: {
                    Text("Import")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canImport)
                .help(model.destination == nil
                      ? "Choose an output folder in Settings first"
                      : "Rip the ticked titles to \(model.destination!.path); each joins Assign as it finishes. Titles sent while a batch runs join it.")
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            // A plain button, not a toggle: a toggle in a toolbar fills with the accent colour when
            // on, and the log is not the thing to draw the eye.
            Button {
                logPresented.toggle()
            } label: {
                Label("Log", systemImage: logPresented ? "rectangle.bottomthird.inset.filled" : "rectangle.bottomthird.inset")
            }
            .help(logPresented ? "Hide the log" : "Show the log")
        }
    }

    // MARK: - Progress

    @ViewBuilder
    private var progressBar: some View {
        HStack(spacing: 12) {
            switch model.phase {
            case .idle, .listingDrives, .scanning:
                Text("Ready")
                    .foregroundStyle(.secondary)
            case .ripping(let titleIndex, let position, let count):
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Title \(titleIndex) — \(position) of \(count)")
                        Spacer()
                        Text(model.progress?.current?.name ?? "Starting")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    ProgressView(value: model.progress?.value.currentFraction ?? 0)
                    ProgressView(value: model.progress?.value.totalFraction ?? 0)
                        .tint(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func startupFailure(_ error: String) -> some View {
        ContentUnavailableView {
            Label("MakeMKV not found", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error)
                .font(.callout.monospaced())
                .multilineTextAlignment(.leading)
        }
    }
}

/// The opening screen: one button per drive, each of which starts a scan.
@MainActor
struct DriveList: View {
    @Environment(IngestModel.self) private var model

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            if model.phase == .scanning, let picked = model.picked {
                ProgressView()
                    .controlSize(.large)
                Text("Scanning \(name(for: picked))…")
                    .font(.title3)
            } else {
                Text("Scan a disc")
                    .font(.title)
                if model.drives.isEmpty {
                    ContentUnavailableView {
                        Label("No optical drives", systemImage: "opticaldisc")
                    } description: {
                        Text("MakeMKV found no drive. One that is plugged in will be noticed; one that has gone to sleep may need asking for.")
                    } actions: {
                        // The one place a manual re-read is offered: with nothing to press and no
                        // event coming, this is what the user would otherwise restart the app for.
                        Button("Look again") {
                            Task { await model.refreshDrives() }
                        }
                        .disabled(model.phase.isBusy)
                    }
                    .frame(maxHeight: 240)
                } else {
                    VStack(spacing: 10) {
                        ForEach(model.drives.sorted { $0.hasDisc && !$1.hasDisc }, id: \.index) { drive in
                            driveButton(drive)
                        }
                    }
                    .frame(maxWidth: 520)
                }
                HStack(spacing: 16) {
                    if model.phase == .listingDrives {
                        ProgressView().controlSize(.small)
                        Text("Reading drives…").foregroundStyle(.secondary)
                    }
                    // Not a drive, but the only way to exercise a scan on a machine whose drive is
                    // not visible: a MakeMKV backup folder or an ISO image.
                    Button("Open a folder or image…") { openFile() }
                        .buttonStyle(.link)
                        .disabled(model.phase.isBusy)
                }
                .padding(.top, 4)
            }
            Spacer()
        }
    }

    private func driveButton(_ drive: Drive) -> some View {
        Button {
            Task { await model.scan(.drive(drive.index)) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: drive.hasDisc ? "opticaldisc.fill" : "opticaldisc")
                    .font(.title)
                    .foregroundStyle(drive.hasDisc ? .primary : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(drive.driveName.trimmingCharacters(in: .whitespaces))
                        .font(.headline)
                    Text(drive.hasDisc ? drive.discName : "No disc")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(!drive.hasDisc || model.phase.isBusy)
        .help(drive.devicePath)
    }

    private func name(for source: PickedSource) -> String {
        switch source {
        case .drive(let index):
            model.drives.first { $0.index == index }.map { $0.discName.isEmpty ? $0.driveName : $0.discName } ?? "drive \(index)"
        case .folder(let url), .iso(let url):
            url.lastPathComponent
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.diskImage, .folder]
        panel.prompt = "Scan"
        panel.message = "A MakeMKV backup folder holding BDMV or VIDEO_TS, or an ISO image."
        if panel.runModal() == .OK, let url = panel.url {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            Task { await model.scan(isDirectory ? .folder(url) : .iso(url)) }
        }
    }
}
