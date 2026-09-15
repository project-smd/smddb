// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import MakeMKVRobot
import SwiftUI
import VLCKit

/// The Assign stage's detail: the selected file playing, with the transport, its chapters, and the
/// facts MakeMKV recorded about the title it came from. What a person needs in front of them to say
/// which episode this is, whether it is the play-all title, and which audio track is the commentary.
@MainActor
struct FileViewer: View {
    let item: ImportedItem
    let player: FilePlayer

    var body: some View {
        VStack(spacing: 0) {
            heading
            Divider()
            // The video view is given the picture's own shape, fitted to the space, so VLC has no
            // room to letterbox: black bars on screen are in the picture, and the space either
            // side is the window's colour. Before the shape is known, a placeholder shape.
            ZStack {
                VideoSurface(view: player.videoView)
                    .aspectRatio(player.videoAspectRatio ?? 16 / 9, contentMode: .fit)
                if let failure = player.failure {
                    failureOverlay(failure)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
            Divider()
            TransportBar(player: player)
            Divider()
            HStack(spacing: 0) {
                ChapterList(player: player)
                    .frame(minWidth: 220, idealWidth: 300, maxWidth: 360)
                Divider()
                TitleFacts(title: item.title)
            }
            .frame(height: 200)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.fileName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Text([
                item.discName,
                "title \(item.title.index)",
                item.title.sourceIdentifier,
                item.fingerprint.map { String($0.contentHash.prefix(8)) },
            ].compactMap { $0 }.joined(separator: " · "))
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func failureOverlay(_ failure: FilePlayer.Failure) -> some View {
        ContentUnavailableView {
            Label(failure == .fileMissing ? "File not found" : "Cannot play this file", systemImage: "film")
        } description: {
            Text(failure == .fileMissing
                 ? "Nothing at \(item.fileURL.path). It may have been moved or deleted since Import wrote it."
                 : "VLC could not open it.")
        }
        .background(.background)
    }
}

/// The player's video view, handed to SwiftUI as is. It belongs to the player, so a rebuilt SwiftUI
/// tree gets the same one back and playback carries on.
private struct VideoSurface: NSViewRepresentable {
    let view: FilePlayer.VideoHostView

    func makeNSView(context: Context) -> FilePlayer.VideoHostView { view }
    func updateNSView(_ nsView: FilePlayer.VideoHostView, context: Context) {}
}

/// Play and pause, chapter and frame steps, a scrubber, and the audio and subtitle track menus.
@MainActor
private struct TransportBar: View {
    let player: FilePlayer
    @State private var scrubbing = false
    @State private var scrubMilliseconds = 0.0

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Button { player.previousChapter() } label: { Image(systemName: "backward.end") }
                    .help("Previous chapter (⌘[)")
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(player.chapters.isEmpty)
                Button { player.jump(seconds: -10) } label: { Image(systemName: "gobackward.10") }
                    .help("Back 10 seconds (⇧←)")
                    .keyboardShortcut(.leftArrow, modifiers: .shift)
                Button { player.togglePlayback() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 16)
                }
                .help(player.isPlaying ? "Pause (Space)" : "Play (Space)")
                .keyboardShortcut(.space, modifiers: [])
                Button { player.jump(seconds: 10) } label: { Image(systemName: "goforward.10") }
                    .help("Forward 10 seconds (⇧→)")
                    .keyboardShortcut(.rightArrow, modifiers: .shift)
                Button { player.nextChapter() } label: { Image(systemName: "forward.end") }
                    .help("Next chapter (⌘])")
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(player.chapters.isEmpty)
            }
            HStack(spacing: 4) {
                Button { player.stepBackward() } label: { Image(systemName: "backward.frame") }
                    .help("Previous frame (⌥←)")
                    .keyboardShortcut(.leftArrow, modifiers: .option)
                Button { player.stepForward() } label: { Image(systemName: "forward.frame") }
                    .help("Next frame (⌥→)")
                    .keyboardShortcut(.rightArrow, modifiers: .option)
            }

            Text(Timecode.string(milliseconds: shownMilliseconds))
                .monospacedDigit()
                .frame(minWidth: 64, alignment: .trailing)
            Slider(value: scrubBinding, in: 0...Double(max(player.lengthMilliseconds, 1))) { editing in
                scrubbing = editing
            }
            .disabled(player.lengthMilliseconds == 0)
            Text("−" + Timecode.string(milliseconds: max(player.lengthMilliseconds - shownMilliseconds, 0)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 64, alignment: .leading)

            trackMenu("Audio", systemImage: "waveform", tracks: player.audioTracks, off: false) { id in
                if let id { player.selectAudioTrack(id: id) }
            }
            trackMenu("Subtitles", systemImage: "captions.bubble", tracks: player.subtitleTracks, off: true) { id in
                player.selectSubtitleTrack(id: id)
            }
        }
        .buttonStyle(.borderless)
        .disabled(player.url == nil || player.failure != nil)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var shownMilliseconds: Int {
        scrubbing ? Int(scrubMilliseconds) : player.timeMilliseconds
    }

    /// Seeks as the knob moves, so the picture follows the drag; while dragging, the knob is where
    /// the drag put it rather than where the player has got to.
    private var scrubBinding: Binding<Double> {
        Binding(
            get: { scrubbing ? scrubMilliseconds : Double(player.timeMilliseconds) },
            set: {
                scrubMilliseconds = $0
                player.seek(toMilliseconds: Int($0))
            }
        )
    }

    /// A menu of one kind of track, with the selected one ticked; `off` adds an entry for none.
    private func trackMenu(_ title: String, systemImage: String, tracks: [FilePlayer.Track], off: Bool, select: @escaping (String?) -> Void) -> some View {
        Menu {
            if off {
                Toggle("Off", isOn: Binding(
                    get: { !tracks.contains(where: \.isSelected) },
                    set: { if $0 { select(nil) } }
                ))
            }
            ForEach(tracks) { track in
                Toggle(isOn: Binding(get: { track.isSelected }, set: { if $0 { select(track.id) } })) {
                    Text(trackLabel(track))
                }
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(tracks.isEmpty)
        .help(tracks.isEmpty ? "No \(title.lowercased()) tracks" : title)
    }

    private func trackLabel(_ track: FilePlayer.Track) -> String {
        var parts = ["\(track.index)"]
        if let language = track.language, !language.isEmpty {
            parts.append(language)
        }
        parts.append(track.name)
        return parts.joined(separator: " · ")
    }
}

/// The file's chapters, the current one selected; selecting another goes there.
@MainActor
private struct ChapterList: View {
    let player: FilePlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(player.chapters.isEmpty ? "Chapters" : "Chapters (\(player.chapters.count))")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Divider()
            if player.chapters.isEmpty {
                Text(player.url == nil ? "" : "None")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(player.chapters, selection: selection) { chapter in
                    HStack {
                        Text("\(chapter.index + 1)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        Text(chapter.name ?? "Chapter \(chapter.index + 1)")
                            .lineLimit(1)
                        Spacer()
                        Text(Timecode.string(milliseconds: chapter.offsetMilliseconds))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .tag(chapter.index)
                }
                .listStyle(.inset)
            }
        }
    }

    private var selection: Binding<Int?> {
        Binding(
            get: { player.currentChapterIndex },
            set: { if let index = $0 { player.goToChapter(index) } }
        )
    }
}

/// What MakeMKV said about the title at rip time: the playlist, its segments and length, and every
/// stream with the disc's index, which is the index a binding records. The file's own tracks, in
/// the transport's menus, are numbered differently: a rip drops streams and renumbers.
@MainActor
private struct TitleFacts: View {
    let title: Title

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Title \(title.index)")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Divider()
            List {
                Section {
                    fact("Playlist", title.sourceIdentifier)
                    fact("Segments", title.segmentMap)
                    fact("Duration", title.durationText)
                    fact("Chapters", title.chapterCount.map(String.init))
                    fact("Size", title.diskSizeText)
                }
                Section("Streams, by disc index") {
                    ForEach(title.tracks, id: \.index) { track in
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(track.index)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                            Text(streamLabel(track))
                                .foregroundStyle(track.isDerived ? .secondary : .primary)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .font(.callout)
        }
    }

    @ViewBuilder
    private func fact(_ name: String, _ value: String?) -> some View {
        if let value {
            LabeledContent(name, value: value)
        }
    }

    private func streamLabel(_ track: Track) -> String {
        var parts: [String] = []
        switch track.kind {
        case .video: parts.append("Video")
        case .audio: parts.append("Audio")
        case .subtitles: parts.append("Subtitles")
        case .unknown: parts.append("Stream")
        }
        if let language = track.languageName { parts.append(language) }
        if let codec = track.codecShort { parts.append(codec) }
        if let layout = track.audioChannelLayoutName { parts.append(layout) }
        if let size = track.videoSize { parts.append(size) }
        if let name = track.name, !name.isEmpty { parts.append(name) }
        if track.isDerived { parts.append(track.isForcedOnly ? "forced only" : "core") }
        return parts.joined(separator: " · ")
    }
}

/// `h:mm:ss` from milliseconds, the form MakeMKV prints durations in.
enum Timecode {
    static func string(milliseconds: Int) -> String {
        let seconds = max(milliseconds, 0) / 1000
        return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
}
