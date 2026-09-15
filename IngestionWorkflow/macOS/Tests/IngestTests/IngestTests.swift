// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import Foundation
import MakeMKV
import MakeMKVRobot
import Testing
@testable import Ingest

/// What the window can be checked for without a drive, a disc or MakeMKV: the model's own rules.
/// Swift Testing throughout; anything added here should be too.
struct IngestTests {
    @Test func pickedSourceMapsToMakeMKVSource() {
        #expect(PickedSource.drive(2).source == .disc(2))
        #expect(PickedSource.folder(URL(fileURLWithPath: "/tmp/backup")).source == .folder(URL(fileURLWithPath: "/tmp/backup")))
        #expect(PickedSource.iso(URL(fileURLWithPath: "/tmp/a.iso")).source == .iso(URL(fileURLWithPath: "/tmp/a.iso")))
    }

    @Test func registeredDefaultsReadBackWhenNothingIsSet() {
        Preferences.register()
        let defaults = UserDefaults.standard
        // Registered values sit beneath anything set, so an unset key reads as its default; a key
        // this test process happens to have set would shadow it, which is why only keys nobody
        // sets in a test host are checked.
        #expect(defaults.integer(forKey: Preferences.minimumTitleLength) == 120)
        #expect(defaults.bool(forKey: Preferences.includeEmbeddedAudioTracks) == false)
        #expect(defaults.bool(forKey: Preferences.includeSubtitles) == true)
        #expect(defaults.bool(forKey: Preferences.includeEmbeddedSubtitleTracks) == true)
    }

    @Test @MainActor func selectionStateFollowsTheTicks() {
        let model = IngestModel(store: IngestStore(directory: temporaryDirectory()))
        // With nothing scanned there is nothing to tick, and that reads as none rather than all.
        #expect(model.selectionState == .none)
        #expect(model.ripCandidates.isEmpty)
        model.toggleAllTitles()
        #expect(model.selectedTitles.isEmpty)
    }

    @Test func extractionRuleFollowsTheSwitches() {
        // Registered defaults are process-wide, so every switch is set explicitly per case rather
        // than relying on an unset key reading false.
        func rule(audio: Bool, subtitles: Bool, embeddedSubtitles: Bool) -> String {
            let defaults = UserDefaults(suiteName: "IngestTests.extractionRule")!
            defer { defaults.removePersistentDomain(forName: "IngestTests.extractionRule") }
            defaults.set(audio, forKey: Preferences.includeEmbeddedAudioTracks)
            defaults.set(subtitles, forKey: Preferences.includeSubtitles)
            defaults.set(embeddedSubtitles, forKey: Preferences.includeEmbeddedSubtitleTracks)
            return Preferences.extractionRule(defaults).description
        }
        #expect(rule(audio: false, subtitles: false, embeddedSubtitles: false) == "+sel:all,-sel:mvcvideo,-sel:core,-sel:subtitle")
        #expect(rule(audio: false, subtitles: true, embeddedSubtitles: false) == "+sel:all,-sel:mvcvideo,-sel:core,-sel:(subtitle*forced)")
        #expect(rule(audio: false, subtitles: true, embeddedSubtitles: true) == "+sel:all,-sel:mvcvideo,-sel:core")
        #expect(rule(audio: true, subtitles: true, embeddedSubtitles: true) == "+sel:all,-sel:mvcvideo")
        // Subtitles off overrides the embedded-subtitle switch entirely.
        #expect(rule(audio: true, subtitles: false, embeddedSubtitles: true) == "+sel:all,-sel:mvcvideo,-sel:subtitle")
    }

    @Test @MainActor func aFinishedImportJoinsTheAssignQueue() {
        let model = IngestModel(store: IngestStore(directory: temporaryDirectory()))
        #expect(model.assignQueue.isEmpty)
        let scan = Scan(source: .disc(0), settings: ScanSettings(), result: DiscScan(parsing: """
            TCOUNT:1
            CINFO:2,0,"Some Disc"
            TINFO:0,16,0,"00015.m2ts"
            TINFO:0,9,0,"0:02:57"
            TINFO:0,27,0,"Some Disc_t00.mkv"
            """))
        let title = scan.titles[0]
        model.recordImport(of: title, from: scan, at: URL(fileURLWithPath: "/tmp/out/Some Disc_t00.mkv"))
        #expect(model.assignQueue.count == 1)
        let item = model.assignQueue[0]
        #expect(item.fileName == "Some Disc_t00.mkv")
        #expect(item.discName == "Some Disc")
        #expect(item.title == title)
        #expect(item.title.sourceIdentifier == "00015.m2ts")
    }

    @Test @MainActor func sendingToImportMarksTitlesAndLeavesTheRestTickable() {
        let model = IngestModel(store: IngestStore(directory: temporaryDirectory()))
        // A scan, a destination and ticks, without a drive: the model's own state is enough to
        // check what Import sends and what it leaves alone.
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: Preferences.outputFolder)
        defaults.set("/tmp/ingest-tests", forKey: Preferences.outputFolder)
        defer { defaults.set(previous, forKey: Preferences.outputFolder) }
        model.adoptForTesting(Scan(source: .disc(0), settings: ScanSettings(), result: DiscScan(parsing: """
            TCOUNT:3
            TINFO:0,16,0,"00001.mpls"
            TINFO:0,27,0,"a_t00.mkv"
            TINFO:1,16,0,"00002.mpls"
            TINFO:1,27,0,"a_t01.mkv"
            TINFO:2,16,0,"00003.mpls"
            TINFO:2,27,0,"a_t02.mkv"
            """)), makeMKV: nil)

        model.selectedTitles = [0, 1]
        #expect(model.selectionState == .some)
        let sent = model.importSelectedTitles()
        #expect(sent.map(\.index) == [0, 1])
        #expect(model.importStatus[0] == .queued)
        #expect(model.importStatus[1] == .queued)
        #expect(model.importStatus[2] == nil)

        // The sent titles are unticked as they go, and are no longer candidates or in the count.
        #expect(model.selectedTitles == [])
        #expect(model.ripCandidates.isEmpty)
        #expect(model.availableTitles.map(\.index) == [2])
        #expect(model.selectionState == .none)
        #expect(!model.canImport)

        // Sending again with nothing new sends nothing; ticking the last one and sending adds it.
        #expect(model.importSelectedTitles().isEmpty)
        model.toggleAllTitles()
        #expect(model.selectedTitles == [2])
        #expect(model.importSelectedTitles().map(\.index) == [2])
        #expect(model.importStatus[2] == .queued)
        // The batch total counts everything sent so far, which is what the progress bar shows.
        #expect(model.importBatchTotal == 3)
    }

    @Test func contentHashMatchesTheDiscDbAlgorithm() throws {
        // Three files of sizes 1, 2 and 3 bytes under BDMV/STREAM: MD5 over the sizes as
        // little-endian Int64 in name order, computed independently in Python.
        let root = temporaryDirectory()
        let stream = root.appendingPathComponent("BDMV/STREAM")
        try FileManager.default.createDirectory(at: stream, withIntermediateDirectories: true)
        for (name, size) in [("00002.m2ts", 2), ("00001.m2ts", 1), ("00003.m2ts", 3)] {
            try Data(repeating: 0, count: size).write(to: stream.appendingPathComponent(name))
        }
        try Data("not a stream".utf8).write(to: stream.appendingPathComponent("ignored.txt"))
        let print = try #require(try DiscFingerprinter.fingerprint(root: root))
        #expect(print.format == .bluray)
        #expect(print.contentHash == "AA341A15F5ADE44FAAFBE190F98C2587")
        #expect(print.aacsDiscId == nil)

        try FileManager.default.createDirectory(at: root.appendingPathComponent("AACS"), withIntermediateDirectories: true)
        try Data("key".utf8).write(to: root.appendingPathComponent("AACS/Unit_Key_RO.inf"))
        #expect(try DiscFingerprinter.fingerprint(root: root)?.aacsDiscId == "A62F2225BF70BFACCBC7F1EF2A397836717377DE")
        #expect(try DiscFingerprinter.fingerprint(root: temporaryDirectory()) == nil)
    }

    @Test @MainActor func queueAndHistorySurviveARelaunch() throws {
        let directory = temporaryDirectory()
        let print = DiscFingerprint(format: .bluray, contentHash: "ABCD", aacsDiscId: nil)
        let scan = Scan(source: .disc(0), settings: ScanSettings(), result: DiscScan(parsing: """
            TCOUNT:2
            CINFO:2,0,"Some Disc"
            TINFO:0,16,0,"00015.m2ts"
            TINFO:0,26,0,"15"
            TINFO:0,9,0,"0:02:57"
            TINFO:1,16,0,"00016.m2ts"
            TINFO:1,26,0,"16"
            TINFO:1,9,0,"0:05:00"
            """))

        let first = IngestModel(store: IngestStore(directory: directory))
        first.adoptForTesting(scan, makeMKV: nil, fingerprint: print)
        first.recordImport(of: scan.titles[0], from: scan, at: URL(fileURLWithPath: "/tmp/out/a.mkv"))
        #expect(first.assignQueue.count == 1)

        // A new model over the same store: the queue is back, and the same disc shows the title
        // as already imported, unticked, while the other is offered as before.
        let second = IngestModel(store: IngestStore(directory: directory))
        #expect(second.assignQueue.map(\.fileName) == ["a.mkv"])
        #expect(second.assignQueue[0].fingerprint == print)
        #expect(second.assignQueue[0].title.sourceIdentifier == "00015.m2ts")
        second.adoptForTesting(scan, makeMKV: nil, fingerprint: print)
        guard case .previouslyImported? = second.importStatus[0] else {
            Issue.record("title 0 should be marked as previously imported, got \(String(describing: second.importStatus[0]))")
            return
        }
        #expect(second.importStatus[1] == nil)
        #expect(second.selectedTitles == [1])
        #expect(second.availableTitles.map(\.index) == [1])

        // The same disc scanned with a different minimum length renumbers titles; the history is
        // keyed by the title's natural identity, so it still finds it.
        let renumbered = Scan(source: .disc(0), settings: ScanSettings(), result: DiscScan(parsing: """
            TCOUNT:1
            CINFO:2,0,"Some Disc"
            TINFO:7,16,0,"00015.m2ts"
            TINFO:7,26,0,"15"
            TINFO:7,9,0,"0:02:57"
            """))
        second.adoptForTesting(renumbered, makeMKV: nil, fingerprint: print)
        #expect(second.importStatus[7] != nil)
    }

    @Test func keepTrackMirrorsTheExtractionRule() {
        let defaults = UserDefaults(suiteName: "IngestTests.keepTrack")!
        defer { defaults.removePersistentDomain(forName: "IngestTests.keepTrack") }
        func track(_ kind: Int, flags: Int) -> Track {
            Track(index: 0, attributes: [
                .type: Attribute(id: .type, messageCode: kind, value: ""),
                .streamFlags: Attribute(id: .streamFlags, messageCode: 0, value: String(flags)),
            ])
        }
        let video = track(6201, flags: 0), lossless = track(6202, flags: 1024), core = track(6202, flags: 2304)
        let subtitle = track(6203, flags: 0), forced = track(6203, flags: 6144)

        defaults.set(false, forKey: Preferences.includeEmbeddedAudioTracks)
        defaults.set(false, forKey: Preferences.includeSubtitles)
        defaults.set(false, forKey: Preferences.includeEmbeddedSubtitleTracks)
        #expect([video, lossless, core, subtitle, forced].map { Preferences.keepTrack($0, defaults) } == [true, true, false, false, false])

        defaults.set(true, forKey: Preferences.includeSubtitles)
        #expect([video, lossless, core, subtitle, forced].map { Preferences.keepTrack($0, defaults) } == [true, true, false, true, false])

        defaults.set(true, forKey: Preferences.includeEmbeddedSubtitleTracks)
        defaults.set(true, forKey: Preferences.includeEmbeddedAudioTracks)
        #expect([video, lossless, core, subtitle, forced].map { Preferences.keepTrack($0, defaults) } == [true, true, true, true, true])
    }

    @Test func phaseBusyness() {
        #expect(!Phase.idle.isBusy)
        #expect(Phase.listingDrives.isBusy)
        #expect(Phase.scanning.isBusy)
        #expect(Phase.ripping(titleIndex: 0).isBusy)
    }
}

/// A fresh directory under the temporary folder, for stores and fingerprints that must not touch
/// the real ones.
func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("IngestTests-" + UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
