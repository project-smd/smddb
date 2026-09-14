// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import Foundation
import MakeMKV
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

    @Test func phaseBusyness() {
        #expect(!Phase.idle.isBusy)
        #expect(Phase.listingDrives.isBusy)
        #expect(Phase.scanning.isBusy)
        #expect(Phase.ripping(titleIndex: 0, position: 1, count: 1).isBusy)
    }
}
