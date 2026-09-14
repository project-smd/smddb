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

/// Where a title stands with Import once the user has asked for it. A title with no status is
/// still available to tick and queue.
enum ImportStatus: Hashable {
    case queued
    case importing
    case imported
    case failed
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

    /// Which stage the window is showing. The sidebar's selection.
    var stage: Stage = .import

    /// Files the Import stage has finished with, oldest first. A file joins the moment its own rip
    /// completes, while later titles in the same batch are still being ripped.
    private(set) var assignQueue: [ImportedItem] = []

    private(set) var scan: Scan?
    private(set) var phase: Phase = .idle
    private(set) var progress: RipProgress?
    var selectedTitles: Set<Int> = []

    /// Titles the user has sent to Import, by index, and how far each has got. A title here stays
    /// ticked and can no longer be unticked; more can be ticked and sent while these are running.
    private(set) var importStatus: [Int: ImportStatus] = [:]
    /// Titles waiting for the import worker, in the order they were sent.
    private var importQueue: [Int] = []
    /// How many titles have been sent this batch, for the "n of m" in the progress bar. The count
    /// grows if more are sent while the batch runs.
    private var importBatchTotal = 0
    private var importBatchDone = 0
    /// Whether the worker is running. Tracked on its own rather than through `phase`, which a drive
    /// listing also occupies: Import pressed during one must still start the worker.
    private var importWorkerRunning = false

    /// Bumped whenever the preferences change, so a view that reads a preference through the
    /// model re-renders when the settings window edits it. Preferences are not observable on their
    /// own; this makes the ones the window depends on behave as if they were.
    private(set) var preferencesVersion = 0

    /// The output folder from the preferences, or `nil` until one is chosen there.
    var destination: URL? {
        _ = preferencesVersion
        let path = UserDefaults.standard.string(forKey: Preferences.outputFolder) ?? ""
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }

    private(set) var log: [LogEntry] = []

    private var watcher: DriveWatcher?
    /// A change arrived while MakeMKV was busy. Re-read the drive table when it is free.
    private var refreshWanted = false
    private var lastListed: Date?

    // MARK: - Lifecycle

    func start() async {
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.preferencesVersion += 1 }
        }
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
            // `Ingest --stage assign` opens on that stage.
            if let flag = CommandLine.arguments.firstIndex(of: "--stage"),
               flag + 1 < CommandLine.arguments.count, let requested = Stage(rawValue: CommandLine.arguments[flag + 1]) {
                stage = requested
            }
            // `Ingest --seed-queue N` puts N made-up files in the Assign queue. The same kind of
            // affordance as --scan: it gets the Assign screen populated without a rip.
            if let flag = CommandLine.arguments.firstIndex(of: "--seed-queue"),
               flag + 1 < CommandLine.arguments.count, let count = Int(CommandLine.arguments[flag + 1]) {
                for n in 0..<count {
                    let title = Title(index: n, attributes: [
                        .sourceFileName: Attribute(id: .sourceFileName, messageCode: 0, value: String(format: "%05d.mpls", 178 + n)),
                        .duration: Attribute(id: .duration, messageCode: 0, value: "0:24:41"),
                    ], tracks: [])
                    assignQueue.append(ImportedItem(fileURL: URL(fileURLWithPath: "/tmp/Seeded_t\(n).mkv"), discName: "Seeded disc", title: title))
                }
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
        // Only give the phase back if nothing took it over meanwhile: an import sent during the
        // listing starts its worker, and the worker owns the phase from then on.
        defer { if phase == .listingDrives { phase = .idle } }
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
        importStatus = [:]
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
        importStatus = [:]
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

    /// Ticked titles not yet sent to Import: what the Import button would send.
    var ripCandidates: [Title] {
        (scan?.titles ?? []).filter { selectedTitles.contains($0.index) && importStatus[$0.index] == nil }
    }

    /// Titles the user can still tick or untick: those not sent to Import.
    var availableTitles: [Title] {
        (scan?.titles ?? []).filter { importStatus[$0.index] == nil }
    }

    /// The header checkbox's state, over the titles that can still be ticked. Sent titles stay
    /// ticked but are out of the count, so a batch in progress reads as none selected, not some.
    var selectionState: MixedCheckbox.State {
        let available = availableTitles
        let selected = available.filter { selectedTitles.contains($0.index) }.count
        return selected == 0 ? .none : selected == available.count ? .all : .some
    }

    /// The header checkbox: everything ticked becomes nothing; anything else becomes everything.
    /// From a partial selection the useful move is to complete it, not to clear it. Sent titles
    /// are left as they are either way.
    func toggleAllTitles() {
        let available = Set(availableTitles.map(\.index))
        if selectionState == .all {
            selectedTitles.subtract(available)
        } else {
            selectedTitles.formUnion(available)
        }
    }

    /// Whether Import can send something: a ticked title not yet sent, and somewhere to write. Not
    /// gated on MakeMKV being free: sending while a batch runs adds to that batch.
    var canImport: Bool {
        !ripCandidates.isEmpty && destination != nil && scan != nil
    }

    /// Send the ticked, unsent titles to Import. They are marked queued at once, which is what
    /// disables their checkboxes, and the worker picks them up in order; if it is already running
    /// they join the end of the current batch. Returns what was sent.
    @discardableResult
    func importSelectedTitles() -> [Title] {
        guard let scan, destination != nil else { return [] }
        let sending = ripCandidates
        guard !sending.isEmpty else { return [] }
        for title in sending {
            importStatus[title.index] = .queued
            importQueue.append(title.index)
        }
        importBatchTotal += sending.count
        note("Sent \(sending.count) title(s) to Import")
        if !importWorkerRunning {
            importWorkerRunning = true
            Task { await runImportQueue(from: scan) }
        }
        return sending
    }

    /// A rip finished: the file is Import's no longer, and Assign's from now. Called once per title
    /// as each completes, so the queue grows while the batch is still running.
    func recordImport(of title: Title, from scan: Scan, at fileURL: URL) {
        assignQueue.append(ImportedItem(fileURL: fileURL, discName: scan.disc?.name ?? "Disc", title: title))
    }

    /// The import worker: rip queued titles one at a time until the queue is empty. Runs once per
    /// batch; `importSelectedTitles` starts it when MakeMKV is idle and otherwise just queues.
    private func runImportQueue(from scan: Scan) async {
        defer {
            importWorkerRunning = false
            phase = .idle
            progress = nil
            importBatchTotal = 0
            importBatchDone = 0
            Task { await refreshIfWanted() }
        }
        guard let makeMKV, let destination else { return }
        // The extraction settings, read once for the whole batch so every file in it keeps the same
        // tracks, and passed as a profile so the result does not depend on this machine's MakeMKV
        // preferences.
        let profile = ConversionProfile(name: "smddb Ingest", selection: Preferences.extractionRule())
        note("Track selection: \(profile.selection)")
        while !importQueue.isEmpty {
            let index = importQueue.removeFirst()
            guard let title = scan.title(index: index) else { continue }
            importBatchDone += 1
            phase = .ripping(titleIndex: index, position: importBatchDone, count: importBatchTotal)
            progress = nil
            importStatus[index] = .importing
            note("Importing title \(index) (\(title.sourceIdentifier ?? "?")) to \(destination.path)")
            do {
                let result = try await makeMKV.rip(title, from: scan, to: destination, profile: profile) { [weak self] line in
                    Task { @MainActor in self?.record(line) }
                } progress: { [weak self] progress in
                    Task { @MainActor in self?.progress = progress }
                }
                note("Wrote \(result.outputURL.lastPathComponent)")
                importStatus[index] = .imported
                recordImport(of: title, from: scan, at: result.outputURL)
            } catch MakeMKVError.processFailed(let status, let messages) {
                record(messages)
                importStatus[index] = .failed
                fail("makemkvcon exited with status \(status) on title \(index)", nil)
            } catch MakeMKVError.outputMissing(let url, let messages) {
                record(messages)
                importStatus[index] = .failed
                fail("MakeMKV finished but \(url.lastPathComponent) is not there", nil)
            } catch {
                importStatus[index] = .failed
                fail("Import of title \(index) failed", error)
            }
        }
    }

    // MARK: - Testing

    /// Install a scan, and optionally a MakeMKV, without a drive. With `makeMKV` nil the import
    /// worker starts and returns at once, so sending titles can be checked without ripping.
    func adoptForTesting(_ scan: Scan, makeMKV: MakeMKV?) {
        self.scan = scan
        self.makeMKV = makeMKV
        selectedTitles = []
        importStatus = [:]
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
