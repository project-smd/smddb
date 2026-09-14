// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import MakeMKV
import SwiftUI

/// The preference keys, one place, so the settings window and the model agree on spelling and on
/// first-run values. Each step of the ingestion flow gets a page of its own as it arrives.
enum Preferences {
    // Scanning
    static let minimumTitleLength = "minimumTitleLength"

    // Extraction
    static let includeEmbeddedAudioTracks = "includeEmbeddedAudioTracks"
    static let includeSubtitles = "includeSubtitles"
    static let includeEmbeddedSubtitleTracks = "includeEmbeddedSubtitleTracks"

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

    /// Registered at launch, so a key that has never been set reads as its default rather than as
    /// zero or false, and the defaults are stated once rather than at every read.
    static func register() {
        UserDefaults.standard.register(defaults: [
            // MakeMKV's own default; TheDiscDb's contributors scan with it, so titles line up with theirs.
            minimumTitleLength: 120,
            // The lossy core inside a lossless track is the same audio again, smaller and worse.
            includeEmbeddedAudioTracks: false,
            includeSubtitles: true,
            // The forced-only stream MakeMKV extracts from the full subtitle track. On by default,
            // unlike the audio core: a core can be pulled out of the lossless track later, exactly,
            // whereas forced captions are flags inside the PGS stream that players do not honour,
            // and MakeMKV drops the derived track when it turns out to be empty, so it is free.
            includeEmbeddedSubtitleTracks: true,
        ])
    }
}

/// The standard preferences window, one tab per step of the flow.
struct SettingsView: View {
    var body: some View {
        TabView {
            ScanningSettings()
                .tabItem { Label("Scanning", systemImage: "opticaldisc") }
            ExtractionSettings()
                .tabItem { Label("Extraction", systemImage: "film.stack") }
        }
        .scenePadding()
        .frame(width: 460, height: 300)
    }
}

struct ScanningSettings: View {
    @AppStorage(Preferences.minimumTitleLength) private var minimumTitleLength = 120

    var body: some View {
        Form {
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
