// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import AppKit
import VLCKit

/// One VLC player, the view it draws into, and what the viewer shows of it read out into observable
/// state: where it is, what chapters and tracks the file has, which are current.
///
/// VLCKit is used because the files are Matroska straight from MakeMKV — VC-1 and MPEG-2 video,
/// DTS and TrueHD audio, PGS subtitles — and AVFoundation opens none of that. Its objects are kept
/// private and on the main actor; the viewer sees plain values.
@MainActor
@Observable
final class FilePlayer {
    /// A chapter of the file, as VLC read it from the Matroska chapter atoms MakeMKV wrote.
    struct Chapter: Identifiable, Hashable {
        var index: Int
        var name: String?
        var offsetMilliseconds: Int
        var durationMilliseconds: Int

        var id: Int { index }
    }

    /// An audio or subtitle track of the file, by VLC's own id, which is what selecting one takes.
    /// The index is the track's place among its kind in the file, which is not the disc's stream
    /// index that a binding records: a rip drops tracks and renumbers.
    struct Track: Identifiable, Hashable {
        var id: String
        var index: Int
        var name: String
        var language: String?
        var isSelected: Bool
    }

    enum Failure: Equatable {
        case fileMissing
        case cannotPlay
    }

    /// The view the video is drawn into. Owned here rather than by the SwiftUI view so it survives
    /// the view being rebuilt.
    let videoView: VLCVideoView
    @ObservationIgnored private let player: VLCMediaPlayer
    /// VLCKit holds its delegate weakly; this keeps it alive.
    @ObservationIgnored private let events: Events

    private(set) var url: URL?
    private(set) var isPlaying = false
    private(set) var failure: Failure?
    /// Milliseconds, which is what `VLCTime` counts in.
    private(set) var timeMilliseconds = 0
    private(set) var lengthMilliseconds = 0
    private(set) var chapters: [Chapter] = []
    /// `nil` before playback has started, or when the file has no chapters.
    private(set) var currentChapterIndex: Int?
    private(set) var audioTracks: [Track] = []
    private(set) var subtitleTracks: [Track] = []

    init() {
        videoView = VLCVideoView()
        videoView.backColor = .black
        // VLCKit's default macOS video output draws through an NSOpenGLView it adds to the video
        // view. Inside a SwiftUI hierarchy, which is layer-backed throughout, AppKit drives that
        // view's drawing from its backing layer's display pass, which reaches libvlc's renderer
        // before the output has a size and trips an assertion. libvlc's other macOS output renders
        // in a CAOpenGLLayer on Core Animation's terms, and is the one to use here. The option goes
        // after VLCKit's defaults, so it overrides the `--vout=macosx` among them.
        player = VLCMediaPlayer(library: VLCLibrary(options: ["--vout=caopengllayer"]))
        player.setVideoView(videoView)
        events = Events()
        events.player = self
        player.delegate = events
        // The default is one report a second, which makes the scrubber crawl.
        player.timeChangeUpdateInterval = 0.25
    }

    /// Open the file and start playing it. Playing rather than pausing on the first frame because
    /// the point of selecting a file is to see what it is, and VLC shows nothing until it plays.
    func load(_ url: URL) {
        guard url != self.url else { return }
        player.stop()
        self.url = url
        reset()
        guard FileManager.default.fileExists(atPath: url.path) else {
            failure = .fileMissing
            return
        }
        guard let media = VLCMedia(url: url) else {
            failure = .cannotPlay
            return
        }
        player.media = media
        player.play()
    }

    func stop() {
        player.stop()
        url = nil
        reset()
    }

    private func reset() {
        isPlaying = false
        failure = nil
        timeMilliseconds = 0
        lengthMilliseconds = 0
        chapters = []
        currentChapterIndex = nil
        audioTracks = []
        subtitleTracks = []
    }

    // MARK: Transport

    func togglePlayback() {
        guard url != nil, failure == nil else { return }
        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }

    func seek(toMilliseconds milliseconds: Int) {
        guard player.isSeekable else { return }
        player.time = VLCTime(int: Int32(clamping: milliseconds))
        timeMilliseconds = milliseconds
    }

    func jump(seconds: Double) {
        if seconds < 0 {
            player.jumpBackward(-seconds)
        } else {
            player.jumpForward(seconds)
        }
    }

    /// One frame on, which pauses the player if it was playing; the way to find a cut point.
    func stepForward() {
        player.gotoNextFrame()
    }

    func stepBackward() {
        player.gotoPreviousFrame()
    }

    func goToChapter(_ index: Int) {
        guard chapters.contains(where: { $0.index == index }) else { return }
        player.currentChapterIndex = Int32(index)
        currentChapterIndex = index
    }

    func previousChapter() {
        player.previousChapter()
    }

    func nextChapter() {
        player.nextChapter()
    }

    // MARK: Tracks

    func selectAudioTrack(id: String) {
        guard let track = player.audioTracks.first(where: { $0.trackId == id }) else { return }
        track.isSelectedExclusively = true
        refreshTracks()
    }

    /// `nil` turns subtitles off.
    func selectSubtitleTrack(id: String?) {
        if let id, let track = player.textTracks.first(where: { $0.trackId == id }) {
            track.isSelectedExclusively = true
        } else {
            player.deselectAllTextTracks()
        }
        refreshTracks()
    }

    // MARK: Reading the player back

    private func refreshState() {
        isPlaying = player.isPlaying
        if player.state == .error {
            failure = .cannotPlay
        }
    }

    private func refreshTime() {
        timeMilliseconds = Int(player.time.intValue)
    }

    private func refreshLength(_ milliseconds: Int64) {
        lengthMilliseconds = Int(milliseconds)
    }

    private func refreshChapters() {
        guard player.numberOfTitles > 0 else {
            chapters = []
            currentChapterIndex = nil
            return
        }
        let descriptions = player.chapterDescriptions(ofTitle: player.currentTitleIndex)
        chapters = descriptions.enumerated().map { position, chapter in
            Chapter(
                index: position,
                name: chapter.name?.isEmpty == false ? chapter.name : nil,
                offsetMilliseconds: Int(chapter.timeOffset.intValue),
                durationMilliseconds: Int(chapter.durationTime.intValue)
            )
        }
        refreshCurrentChapter()
    }

    private func refreshCurrentChapter() {
        let index = Int(player.currentChapterIndex)
        currentChapterIndex = chapters.isEmpty || index < 0 ? nil : index
    }

    private func refreshTracks() {
        audioTracks = FilePlayer.tracks(player.audioTracks)
        subtitleTracks = FilePlayer.tracks(player.textTracks)
    }

    private static func tracks(_ tracks: [VLCMediaPlayer.Track]) -> [Track] {
        tracks.enumerated().map { position, track in
            Track(
                id: track.trackId,
                index: position + 1,
                name: track.trackName,
                language: track.language,
                isSelected: track.isSelected
            )
        }
    }

    /// VLCKit's delegate. libvlc raises events on its own threads, and VLCKit forwards them on
    /// whatever queue it is configured with, so nothing here touches the player directly: each
    /// callback hops to the main actor and reads the player from there.
    private final class Events: NSObject, VLCMediaPlayerDelegate {
        nonisolated(unsafe) weak var player: FilePlayer?

        func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
            onMain { $0.refreshState(); $0.refreshChapters(); $0.refreshTracks() }
        }

        func mediaPlayerTimeChanged(_ aNotification: Notification) {
            onMain { $0.refreshTime() }
        }

        func mediaPlayerLengthChanged(_ length: Int64) {
            onMain { $0.refreshLength(length) }
        }

        func mediaPlayerTitleListChanged(_ aNotification: Notification) {
            onMain { $0.refreshChapters() }
        }

        func mediaPlayerTitleSelectionChanged(_ aNotification: Notification) {
            onMain { $0.refreshChapters() }
        }

        func mediaPlayerChapterChanged(_ aNotification: Notification) {
            onMain { $0.refreshCurrentChapter() }
        }

        func mediaPlayerTrackAdded(_ trackId: String, with trackType: VLCMedia.TrackType) {
            onMain { $0.refreshTracks() }
        }

        func mediaPlayerTrackRemoved(_ trackId: String, with trackType: VLCMedia.TrackType) {
            onMain { $0.refreshTracks() }
        }

        func mediaPlayerTrackSelected(_ trackType: VLCMedia.TrackType, selectedId: String, unselectedId: String) {
            onMain { $0.refreshTracks() }
        }

        private func onMain(_ body: @escaping @MainActor (FilePlayer) -> Void) {
            let player = self.player
            Task { @MainActor in
                if let player { body(player) }
            }
        }
    }
}
