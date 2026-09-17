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

    /// A disc with a logo clip and a feature. `logoFile` is where this disc keeps the logo: the
    /// same clip sits under a different name, and a different title index, on each disc.
    private func discWithLogo(named name: String, logoFile: String, logoIndex: Int) -> Scan {
        Scan(source: .disc(0), settings: ScanSettings(), result: DiscScan(parsing: """
            TCOUNT:2
            CINFO:2,0,"\(name)"
            TINFO:\(logoIndex),16,0,"\(logoFile)"
            TINFO:\(logoIndex),9,0,"0:00:21"
            TINFO:\(logoIndex),11,0,"48234496"
            TINFO:\(logoIndex),27,0,"\(name)_t0\(logoIndex).mkv"
            SINFO:\(logoIndex),0,1,6201,"Video"
            SINFO:\(logoIndex),0,5,0,"V_MPEG4/ISO/AVC"
            SINFO:\(logoIndex),0,19,0,"1920x1080"
            SINFO:\(logoIndex),1,1,6202,"Audio"
            SINFO:\(logoIndex),1,5,0,"A_AC3"
            SINFO:\(logoIndex),1,14,0,"6"
            TINFO:5,16,0,"00800.mpls"
            TINFO:5,9,0,"1:41:07"
            TINFO:5,11,0,"31234567890"
            TINFO:5,27,0,"\(name)_t05.mkv"
            SINFO:5,0,1,6201,"Video"
            SINFO:5,0,5,0,"V_MPEG4/ISO/AVC"
            SINFO:5,0,19,0,"1920x1080"
            """))
    }

    @Test @MainActor func rejectingDeletesTheFileAndTurnsTheRecordToRejected() throws {
        let directory = temporaryDirectory()
        let print = DiscFingerprint(format: .bluray, contentHash: "AAAA", aacsDiscId: nil)
        let scan = discWithLogo(named: "Disc A", logoFile: "00005.m2ts", logoIndex: 0)
        let file = directory.appendingPathComponent("Disc A_t00.mkv")
        try Data("mkv".utf8).write(to: file)

        let model = IngestModel(store: IngestStore(directory: directory))
        model.adoptForTesting(scan, makeMKV: nil, fingerprint: print)
        let item = model.recordImport(of: scan.titles[0], from: scan, at: file)
        try model.reject(item, as: .rejected, description: "  menu loop ")

        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(model.assignQueue.isEmpty)
        // The disc is still the one scanned, so its row changes at once, description trimmed.
        guard case .rejected(let rejection)? = model.importStatus[0] else {
            Issue.record("title 0 should be rejected, got \(String(describing: model.importStatus[0]))")
            return
        }
        #expect(rejection.kind == .rejected)
        #expect(rejection.description == "menu loop")
        // A plain reject is this disc's business only.
        #expect(model.discLogos.isEmpty)

        // And it is what the disc shows after a relaunch, unticked, with the feature still offered.
        let relaunched = IngestModel(store: IngestStore(directory: directory))
        relaunched.adoptForTesting(scan, makeMKV: nil, fingerprint: print)
        // Compared by field: the store keeps dates to the second, so the date itself comes back rounded.
        guard case .rejected(let reloaded)? = relaunched.importStatus[0] else {
            Issue.record("title 0 should still be rejected, got \(String(describing: relaunched.importStatus[0]))")
            return
        }
        #expect(reloaded.kind == .rejected)
        #expect(reloaded.description == "menu loop")
        #expect(relaunched.selectedTitles == [5])

        // Cleared, it is offered again, and stays so.
        relaunched.clearRejection(of: scan.titles[0])
        #expect(relaunched.importStatus[0] == nil)
        let again = IngestModel(store: IngestStore(directory: directory))
        again.adoptForTesting(scan, makeMKV: nil, fingerprint: print)
        #expect(again.importStatus[0] == nil)
    }

    @Test @MainActor func aRejectedDiscLogoIsRecognisedOnAnotherDisc() throws {
        let directory = temporaryDirectory()
        let discA = discWithLogo(named: "Disc A", logoFile: "00005.m2ts", logoIndex: 0)
        let file = directory.appendingPathComponent("Disc A_t00.mkv")
        try Data("mkv".utf8).write(to: file)

        let model = IngestModel(store: IngestStore(directory: directory))
        model.adoptForTesting(discA, makeMKV: nil, fingerprint: DiscFingerprint(format: .bluray, contentHash: "AAAA", aacsDiscId: nil))
        let item = model.recordImport(of: discA.titles[0], from: discA, at: file)
        try model.reject(item, as: .discLogo, description: "Universal logo")
        #expect(model.discLogos.count == 1)

        // Another disc, never seen, keeps the same clip under another name and index. It comes up
        // rejected and unticked, under the description, with nothing imported; the feature, which
        // shares the logo's video shape but not its size, is untouched.
        let discB = discWithLogo(named: "Disc B", logoFile: "00012.m2ts", logoIndex: 3)
        let relaunched = IngestModel(store: IngestStore(directory: directory))
        relaunched.adoptForTesting(discB, makeMKV: nil, fingerprint: DiscFingerprint(format: .bluray, contentHash: "BBBB", aacsDiscId: nil))
        guard case .rejected(let rejection)? = relaunched.importStatus[3] else {
            Issue.record("the logo on disc B should be rejected, got \(String(describing: relaunched.importStatus[3]))")
            return
        }
        #expect(rejection.kind == .discLogo)
        #expect(rejection.description == "Universal logo")
        #expect(relaunched.importStatus[5] == nil)
        #expect(relaunched.selectedTitles == [5])
        #expect(relaunched.assignQueue.isEmpty)

        // Clearing it on disc B forgets the clip as a logo, so the next scan offers it.
        relaunched.clearRejection(of: discB.titles[0])
        #expect(relaunched.discLogos.isEmpty)
        relaunched.adoptForTesting(discB, makeMKV: nil, fingerprint: DiscFingerprint(format: .bluray, contentHash: "BBBB", aacsDiscId: nil))
        #expect(relaunched.importStatus[3] == nil)
    }

    @Test @MainActor func aFileThatWillNotDeleteIsNotRejected() throws {
        let directory = temporaryDirectory()
        let locked = directory.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let file = locked.appendingPathComponent("Disc A_t00.mkv")
        try Data("mkv".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let scan = discWithLogo(named: "Disc A", logoFile: "00005.m2ts", logoIndex: 0)
        let model = IngestModel(store: IngestStore(directory: directory))
        model.adoptForTesting(scan, makeMKV: nil)
        let item = model.recordImport(of: scan.titles[0], from: scan, at: file)
        #expect(throws: (any Error).self) { try model.reject(item, as: .discLogo, description: "Logo") }
        #expect(model.assignQueue.count == 1)
        #expect(model.discLogos.isEmpty)
        #expect(model.importStatus[0] == nil)

        // A file already gone is no obstacle: the rejection goes through.
        let missing = model.recordImport(of: scan.titles[1], from: scan, at: directory.appendingPathComponent("never-written.mkv"))
        try model.reject(missing, as: .rejected, description: "")
        #expect(model.assignQueue.count == 1)
        guard case .rejected(let rejection)? = model.importStatus[5] else {
            Issue.record("title 5 should be rejected")
            return
        }
        #expect(rejection.description == nil)
    }

    @Test func aStateFileFromBeforeRejectionsStillLoads() throws {
        // What the tool wrote before it knew about disc logos or rejections: no `discLogos` key,
        // no `rejection` in a record. Losing the queue to a new key would be a poor upgrade.
        let directory = temporaryDirectory()
        let store = IngestStore(directory: directory)
        try Data("""
            {"assignQueue": [], "imports": {"hash:ABCD": {"00015.m2ts|15|0:02:57": {"titleIndex": 0, "fileURL": "file:///tmp/out/a.mkv", "importedAt": "2026-09-01T10:00:00Z"}}}}
            """.utf8).write(to: store.fileURL)
        let state = store.load()
        #expect(state.imports["hash:ABCD"]?.count == 1)
        #expect(state.imports["hash:ABCD"]?.values.first?.rejection == nil)
        #expect(state.discLogos.isEmpty)
    }

    @Test func contentSignatureIgnoresWhereTheDiscKeepsTheClip() {
        let a = discWithLogo(named: "Disc A", logoFile: "00005.m2ts", logoIndex: 0)
        let b = discWithLogo(named: "Disc B", logoFile: "00012.m2ts", logoIndex: 3)
        #expect(IngestStore.contentSignature(a.titles[0]) == "48234496|21s|v:V_MPEG4/ISO/AVC:1920x1080|a:A_AC3:6")
        #expect(IngestStore.contentSignature(a.titles[0]) == IngestStore.contentSignature(b.titles[0]))
        #expect(IngestStore.contentSignature(a.titles[0]) != IngestStore.contentSignature(a.titles[1]))
        // Without a size there is nothing to recognise a clip by.
        let bare = Title(index: 0, attributes: [.duration: Attribute(id: .duration, messageCode: 0, value: "0:00:21")], tracks: [])
        #expect(IngestStore.contentSignature(bare) == nil)
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

    @Test func discFolderNameIsUniquePerDisc() {
        let print = DiscFingerprint(format: .bluray, contentHash: "3386B3B98C8E6DC3EAFB33E2170B15D6", aacsDiscId: nil)
        #expect(IngestStore.discFolderName(discName: "Doctor Who - S13 Disc 3", fingerprint: print) == "Doctor Who - S13 Disc 3 [3386B3B98C8E6DC3EAFB33E2170B15D6]")
        // No fingerprint: the name alone.
        #expect(IngestStore.discFolderName(discName: "Some Disc", fingerprint: nil) == "Some Disc")
        // Path separators in the disc name are replaced, and an empty name has a fallback.
        #expect(IngestStore.discFolderName(discName: "A/B: C", fingerprint: nil) == "A-B- C")
        #expect(IngestStore.discFolderName(discName: "", fingerprint: nil) == "Disc")
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
