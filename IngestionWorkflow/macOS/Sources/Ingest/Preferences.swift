// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import AppKit
import MakeMKV
import MakeMKVRobot
import SwiftUI

/// The preference keys, one place, so the settings window and the model agree on spelling and on
/// first-run values. Each step of the ingestion flow gets a page of its own as it arrives.
enum Preferences {
    // Ingestion
    /// The folder imported files land in, as a path. No default: it is chosen, and until it is the
    /// Import button says why it is disabled.
    static let outputFolder = "outputFolder"
    /// The local clone of the data repository, as a path: where containers are read from and
    /// written to. No default, for the same reason as the output folder.
    static let repositoryFolder = "repositoryFolder"

    // Scanning
    static let minimumTitleLength = "minimumTitleLength"
    /// Keep one MakeMKV engine running and the disc open between scanning and importing, through
    /// the protocol MakeMKV's own GUI uses, so importing several titles reads the disc once. Off by
    /// default: the protocol is MakeMKV's and unpublished, where robot mode is documented.
    static let useEngineSession = "useEngineSession"

    // Extraction
    static let includeEmbeddedAudioTracks = "includeEmbeddedAudioTracks"
    static let includeSubtitles = "includeSubtitles"
    static let includeEmbeddedSubtitleTracks = "includeEmbeddedSubtitleTracks"

    // Playback
    static let autoplay = "autoplay"

    /// The extraction settings as MakeMKV's selection rule: every track on the disc, minus what the
    /// switches leave out. Everything, not MakeMKV's own default, because that default drops tracks
    /// on grounds of language and channel count — a stereo track when a 5.1 exists in the same
    /// language — and on a Collection disc the stereo track is the original mix. 3D dependent-view
    /// video is left out as MakeMKV leaves it out; nothing here plays it.
    static func extractionRule(_ defaults: UserDefaults = .standard) -> SelectionRule {
        var actions: [SelectionRule.Action] = [
            .select(.attribute(.all)),
            .deselect(.attribute(.mvcvideo)),
        ]
        if !defaults.bool(forKey: includeEmbeddedAudioTracks) {
            actions.append(.deselect(.attribute(.core)))
        }
        if !defaults.bool(forKey: includeSubtitles) {
            actions.append(.deselect(.attribute(.subtitle)))
        } else if !defaults.bool(forKey: includeEmbeddedSubtitleTracks) {
            actions.append(.deselect(.and(.attribute(.subtitle), .attribute(.forced))))
        }
        return SelectionRule(actions)
    }

    /// The extraction settings as a per-track decision, for the engine path, where tracks are
    /// ticked one by one rather than selected by rule. Mirrors `extractionRule` exactly.
    static func keepTrack(_ track: Track, _ defaults: UserDefaults = .standard) -> Bool {
        if track.isCore && !defaults.bool(forKey: includeEmbeddedAudioTracks) { return false }
        if track.kind == .subtitles {
            if !defaults.bool(forKey: includeSubtitles) { return false }
            if track.isForcedOnly && !defaults.bool(forKey: includeEmbeddedSubtitleTracks) { return false }
        }
        return true
    }

    /// Registered at launch, so a key that has never been set reads as its default rather than as
    /// zero or false, and the defaults are stated once rather than at every read.
    static func register() {
        UserDefaults.standard.register(defaults: [
            // MakeMKV's own default; TheDiscDb's contributors scan with it, so titles line up with theirs.
            minimumTitleLength: 120,
            useEngineSession: false,
            // The lossy core inside a lossless track is the same audio again, smaller and worse.
            includeEmbeddedAudioTracks: false,
            includeSubtitles: true,
            // The forced-only stream MakeMKV extracts from the full subtitle track. On by default,
            // unlike the audio core: a core can be pulled out of the lossless track later, exactly,
            // whereas forced captions are flags inside the PGS stream that players do not honour,
            // and MakeMKV drops the derived track when it turns out to be empty, so it is free.
            includeEmbeddedSubtitleTracks: true,
            // Selecting a file shows its first frame, paused. Off because selecting is how the queue
            // is browsed, and a file starting up with sound each time is not browsing.
            autoplay: false,
        ])
    }
}

/// The standard preferences window, one tab per step of the flow.
struct SettingsView: View {
    var body: some View {
        TabView {
            IngestionSettings()
                .tabItem { Label("Ingestion", systemImage: "tray.and.arrow.down") }
            ScanningSettings()
                .tabItem { Label("Scanning", systemImage: "opticaldisc") }
            ExtractionSettings()
                .tabItem { Label("Extraction", systemImage: "film.stack") }
            PlaybackSettings()
                .tabItem { Label("Playback", systemImage: "play.rectangle") }
        }
        .scenePadding()
        .frame(width: 460, height: 340)
    }
}

struct IngestionSettings: View {
    @AppStorage(Preferences.outputFolder) private var outputFolder = ""
    @AppStorage(Preferences.repositoryFolder) private var repositoryFolder = ""

    var body: some View {
        Form {
            Section {
                FolderField(label: "Output folder", path: $outputFolder, prompt: "Use as output folder")
                Text("Where imported files are written. Import is disabled until a folder is chosen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                FolderField(label: "Repository folder", path: $repositoryFolder, prompt: "Use as repository")
                Text("A local clone of the smddb data repository. Containers are read from it and written to it; committing what was written is up to you.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// A path preference: the path, middle-truncated, or "Not chosen", and a button that opens the
/// folder panel.
struct FolderField: View {
    let label: String
    @Binding var path: String
    let prompt: String

    var body: some View {
        LabeledContent(label) {
            HStack {
                if path.isEmpty {
                    Text("Not chosen")
                        .foregroundStyle(.secondary)
                } else {
                    Text(path)
                        .truncationMode(.middle)
                        .lineLimit(1)
                        .help(path)
                }
                Button("Choose…") { choose() }
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if !path.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: path)
        }
        panel.prompt = prompt
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
        }
    }
}

struct ScanningSettings: View {
    @AppStorage(Preferences.minimumTitleLength) private var minimumTitleLength = 120
    @AppStorage(Preferences.useEngineSession) private var useEngineSession = false

    var body: some View {
        Form {
            Section {
                Toggle("Keep MakeMKV open between operations", isOn: $useEngineSession)
                Text("Talks to the MakeMKV engine the way its own window does, so a disc is read once for a scan and every import from it, instead of once per title. Uses a protocol MakeMKV does not document; off, the tool uses the documented command line. Takes effect at the next scan.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Minimum title length") {
                HStack {
                    // No title on the field: inside a grouped form a title becomes a second label.
                    TextField("", value: $minimumTitleLength, format: .number)
                        .labelsHidden()
                        .frame(width: 64)
                        .multilineTextAlignment(.trailing)
                    Stepper("", value: $minimumTitleLength, in: 0...3600, step: 10)
                        .labelsHidden()
                    Text("seconds")
                        .foregroundStyle(.secondary)
                }
            }
            Text("Titles shorter than this are left out of a scan. MakeMKV's own default is 120; 0 lists everything, menus and logos included.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

struct ExtractionSettings: View {
    @AppStorage(Preferences.includeEmbeddedAudioTracks) private var includeEmbeddedAudioTracks = false
    @AppStorage(Preferences.includeSubtitles) private var includeSubtitles = true
    @AppStorage(Preferences.includeEmbeddedSubtitleTracks) private var includeEmbeddedSubtitleTracks = true

    var body: some View {
        Form {
            Section {
                Toggle("Include embedded audio tracks", isOn: $includeEmbeddedAudioTracks)
                Text("The lossy core a lossless track carries inside it — the DTS within DTS-HD MA — as a track of its own.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Include subtitles", isOn: $includeSubtitles)
                Toggle("Include embedded subtitle tracks", isOn: $includeEmbeddedSubtitleTracks)
                    .disabled(!includeSubtitles)
                    .padding(.leading, 20)
                Text("The forced-only stream MakeMKV derives from a subtitle track, beside the full one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }
        }
        .formStyle(.grouped)
    }
}

struct PlaybackSettings: View {
    @AppStorage(Preferences.autoplay) private var autoplay = false

    var body: some View {
        Form {
            Toggle("Play a file when it is selected", isOn: $autoplay)
            Text("Otherwise a selected file opens paused on its first frame, and Space plays it.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
