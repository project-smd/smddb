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
        let model = IngestModel()
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
        let model = IngestModel()
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
        let model = IngestModel()
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

        // The sent titles stay ticked but are no longer candidates or part of the header's count.
        #expect(model.selectedTitles == [0, 1])
        #expect(model.ripCandidates.isEmpty)
        #expect(model.availableTitles.map(\.index) == [2])
        #expect(model.selectionState == .none)
        #expect(!model.canImport)

        // Sending again with nothing new sends nothing; ticking the last one and sending adds it.
        #expect(model.importSelectedTitles().isEmpty)
        model.toggleAllTitles()
        #expect(model.selectedTitles == [0, 1, 2])
        #expect(model.importSelectedTitles().map(\.index) == [2])
        #expect(model.importStatus[2] == .queued)
    }

    @Test func phaseBusyness() {
        #expect(!Phase.idle.isBusy)
        #expect(Phase.listingDrives.isBusy)
        #expect(Phase.scanning.isBusy)
        #expect(Phase.ripping(titleIndex: 0, position: 1, count: 1).isBusy)
    }
}
