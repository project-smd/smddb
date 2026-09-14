// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import Foundation
import MakeMKV
import MakeMKVRobot
import Observation

/// What the window can point MakeMKV at. A drive is named by MakeMKV's own index, which is what the
/// `DRV` table hands out and what `disc:N` takes.
enum PickedSource: Hashable {
    case drive(Int)
    case folder(URL)
    case iso(URL)

    var source: Source {
        switch self {
        case .drive(let index): .disc(index)
        case .folder(let url): .folder(url)
        case .iso(let url): .iso(url)
        }
    }
}

/// One row of the log pane: a MakeMKV message or something the tool did.
struct LogEntry: Identifiable, Hashable {
    let id = UUID()
    var time: Date
    var text: String
    var isError = false
}

/// What the window is doing. One thing at a time, because MakeMKV is.
enum Phase: Hashable {
    case idle
    case listingDrives
    case scanning
    case ripping(titleIndex: Int, position: Int, count: Int)

    var isBusy: Bool { self != .idle }
}

@MainActor
@Observable
final class IngestModel {
    private(set) var makeMKV: MakeMKV?
    private(set) var startupError: String?

    private(set) var drives: [Drive] = []
    var picked: PickedSource?
    /// Read at scan time from the preferences, which own it; the settings window is where it is set.
    var minimumTitleLength: Int {
        UserDefaults.standard.integer(forKey: Preferences.minimumTitleLength)
    }

    private(set) var scan: Scan?
    private(set) var phase: Phase = .idle
    private(set) var progress: RipProgress?
    var selectedTitles: Set<Int> = []
    var destination: URL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser

    private(set) var log: [LogEntry] = []

    private var watcher: DriveWatcher?
    /// A change arrived while MakeMKV was busy. Re-read the drive table when it is free.
    private var refreshWanted = false
    private var lastListed: Date?

    // MARK: - Lifecycle

    func start() async {
        do {
            makeMKV = try MakeMKV()
            note("Using \(makeMKV!.executable.path)")
            await refreshDrives()
            // `Ingest --scan N` scans drive N straight away. A developer affordance: it gets the
            // results screen up without a click, which is what iterating on that screen needs.
            if let flag = CommandLine.arguments.firstIndex(of: "--scan"),
               flag + 1 < CommandLine.arguments.count, let index = Int(CommandLine.arguments[flag + 1]) {
                await scan(.drive(index))
            }
            watcher = DriveWatcher { [weak self] in
                Task { @MainActor in await self?.drivesMayHaveChanged() }
            }
            if watcher == nil {
                note("Drive changes will not be noticed automatically; use Refresh")
            }
        } catch MakeMKVError.executableNotFound(let searched) {
            startupError = "makemkvcon not found. Looked in:\n" + searched.map(\.path).joined(separator: "\n")
        } catch {
            startupError = "\(error)"
        }
    }

    /// The watcher saw a disc or a drive come or go. MakeMKV's table is the only view that matters,
    /// so re-read it — now, or as soon as MakeMKV is free.
    func drivesMayHaveChanged() async {
        note("Drive change detected")
        if phase.isBusy {
            refreshWanted = true
        } else {
            await refreshDrives()
        }
    }

    private func refreshIfWanted() async {
        guard refreshWanted else { return }
        refreshWanted = false
        await refreshDrives()
    }

    func refreshDrives() async {
        guard let makeMKV, !phase.isBusy else { return }
        phase = .listingDrives
        defer { phase = .idle }
        do {
            drives = try await makeMKV.drives().filter(\.isPresent)
            lastListed = .now
            let withDisc = drives.filter(\.hasDisc)
            note("\(drives.count) drive(s), \(withDisc.count) with a disc")
            if picked == nil, let first = withDisc.first ?? drives.first {
                picked = .drive(first.index)
            }
        } catch {
            fail("Listing drives failed", error)
        }
    }

    // MARK: - Scan

    /// Start a scan of one source. The drive buttons on the opening screen call this directly:
    /// picking a drive and scanning it are one gesture there, not two.
    func scan(_ source: PickedSource) async {
        picked = source
        await scanPickedSource()
    }

    /// Back to the opening screen. The scan is dropped, because a title index only means something
    /// against the scan that produced it and keeping a stale one around invites using it. The drive
    /// table is re-read on the way, since the disc has usually been swapped by now.
    func discardScan() async {
        guard !phase.isBusy else { return }
        scan = nil
        selectedTitles = []
        await refreshDrives()
    }

    /// The window came to the front. The watcher sees discs and drives come and go, but not a drive
    /// that MakeMKV lost sight of and found again with no hardware event — a drive that fell asleep
    /// does exactly that — so the table is re-read when the user comes back to the drive list after
    /// being away. The interval keeps the activation at launch, and a quick flick between windows,
    /// from listing twice.
    func windowBecameActive() async {
        guard scan == nil, !phase.isBusy, let lastListed, Date.now.timeIntervalSince(lastListed) > 10 else { return }
        await refreshDrives()
    }

    func scanPickedSource() async {
        guard let makeMKV, let picked, !phase.isBusy else { return }
        phase = .scanning
        defer {
            phase = .idle
            Task { await refreshIfWanted() }
        }
        scan = nil
        selectedTitles = []
        note("Scanning \(picked.source.argument) with minimum length \(minimumTitleLength)s")
        do {
            // Messages are logged as they arrive, so the log moves while the disc is being read.
            let result = try await makeMKV.scan(picked.source, settings: ScanSettings(minimumTitleLength: minimumTitleLength)) { [weak self] line in
                Task { @MainActor in self?.record(line) }
            }
            scan = result
            // MakeMKV ticks every title it lists; so do we.
            selectedTitles = Set(result.titles.map(\.index))
            note("\(result.titles.count) title(s) on \(result.disc?.name ?? "the disc")")
        } catch MakeMKVError.discUnavailable(let messages) {
            record(messages)
            fail("No disc could be opened", nil)
        } catch MakeMKVError.processFailed(let status, let messages) {
            record(messages)
            fail("makemkvcon exited with status \(status)", nil)
        } catch {
            fail("Scan failed", error)
        }
    }

    // MARK: - Rip

    var ripCandidates: [Title] {
        (scan?.titles ?? []).filter { selectedTitles.contains($0.index) }
    }

    var selectionState: MixedCheckbox.State {
        let titles = scan?.titles ?? []
        let selected = titles.filter { selectedTitles.contains($0.index) }.count
        return selected == 0 ? .none : selected == titles.count ? .all : .some
    }

    /// The header checkbox: everything ticked becomes nothing; anything else becomes everything.
    /// From a partial selection the useful move is to complete it, not to clear it.
    func toggleAllTitles() {
        selectedTitles = selectionState == .all ? [] : Set((scan?.titles ?? []).map(\.index))
    }

    func ripSelectedTitles() async {
        guard let makeMKV, let scan, !phase.isBusy else { return }
        let titles = ripCandidates
        guard !titles.isEmpty else { return }
        defer {
            phase = .idle
            progress = nil
            Task { await refreshIfWanted() }
        }
        // The extraction settings, read once for the whole batch so every file in it keeps the same
        // tracks, and passed as a profile so the result does not depend on this machine's MakeMKV
        // preferences.
        let profile = ConversionProfile(name: "smddb Ingest", selection: Preferences.extractionRule())
        note("Track selection: \(profile.selection)")
        for (position, title) in titles.enumerated() {
            phase = .ripping(titleIndex: title.index, position: position + 1, count: titles.count)
            progress = nil
            note("Ripping title \(title.index) (\(title.sourceIdentifier ?? "?")) to \(destination.path)")
            do {
                let result = try await makeMKV.rip(title, from: scan, to: destination, profile: profile) { [weak self] line in
                    Task { @MainActor in self?.record(line) }
                } progress: { [weak self] progress in
                    Task { @MainActor in self?.progress = progress }
                }
                note("Wrote \(result.outputURL.lastPathComponent)")
            } catch MakeMKVError.processFailed(let status, let messages) {
                record(messages)
                fail("makemkvcon exited with status \(status) on title \(title.index)", nil)
                return
            } catch MakeMKVError.outputMissing(let url, let messages) {
                record(messages)
                fail("MakeMKV finished but \(url.lastPathComponent) is not there", nil)
                return
            } catch {
                fail("Rip of title \(title.index) failed", error)
                return
            }
        }
    }

    // MARK: - Log

    private func note(_ text: String) {
        log.append(LogEntry(time: .now, text: text))
    }

    private func fail(_ text: String, _ error: Error?) {
        let detail = error.map { ": \($0)" } ?? ""
        log.append(LogEntry(time: .now, text: text + detail, isError: true))
    }

    /// MakeMKV's own messages, minus the debug chatter, which is voluminous and about MakeMKV.
    private func record(_ messages: [Message]) {
        for message in messages where !message.isDebug && !message.isHidden {
            log.append(LogEntry(time: .now, text: message.text))
        }
    }

    /// One line as it arrives. Only messages are logged; attribute and progress lines are data.
    private func record(_ line: RobotLine) {
        if case .message(let message) = line {
            record([message])
        }
    }
}
