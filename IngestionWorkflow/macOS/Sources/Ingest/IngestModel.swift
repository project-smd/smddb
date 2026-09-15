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
    /// Imported on an earlier launch, per the history kept for this disc.
    case previouslyImported(Date)
}

/// What the window is doing. One thing at a time, because MakeMKV is.
enum Phase: Hashable {
    case idle
    case listingDrives
    case scanning
    /// Ripping one title. Its place in the batch is not carried here, because the batch can grow
    /// while it runs; `IngestModel.importBatchDone` and `importBatchTotal` are read live instead.
    case ripping(titleIndex: Int)

    var isBusy: Bool { self != .idle }
}

@MainActor
@Observable
final class IngestModel {
    private(set) var makeMKV: MakeMKV?
    private(set) var startupError: String?

    /// The engine kept open between operations, when the Scanning preference asks for it. Started
    /// on the first operation that wants it and kept until the app quits; `nil` means robot mode.
    private var engine: EngineSession?
    /// Whether the scan in hand was made through the engine, which is where its titles must then
    /// be imported from: the engine's disc is the one that is open.
    private(set) var scanUsedEngine = false

    var useEngineSession: Bool {
        _ = preferencesVersion
        return UserDefaults.standard.bool(forKey: Preferences.useEngineSession)
    }

    private(set) var drives: [Drive] = []
    var picked: PickedSource?
    /// Read at scan time from the preferences, which own it; the settings window is where it is set.
    var minimumTitleLength: Int {
        UserDefaults.standard.integer(forKey: Preferences.minimumTitleLength)
    }

    /// Which stage the window is showing. The sidebar's selection.
    var stage: Stage = .import

    /// Files the Import stage has finished with, oldest first. A file joins the moment its own rip
    /// completes, while later titles in the same batch are still being ripped. Kept across launches.
    private(set) var assignQueue: [ImportedItem] = []

    /// What has been imported from which disc, across launches, so a disc put back in the drive
    /// shows the titles already taken from it as done rather than offering them again.
    private(set) var imports: [String: [String: ImportRecord]] = [:]
    private let store: IngestStore

    /// The fingerprint of the scanned disc, when its volume could be read; the key its history is
    /// filed under, and the provenance each imported file carries.
    private(set) var fingerprint: DiscFingerprint?

    init(store: IngestStore = IngestStore()) {
        self.store = store
        let state = store.load()
        assignQueue = state.assignQueue
        imports = state.imports
    }

    private func persist() {
        do {
            try store.save(PersistedState(assignQueue: assignQueue, imports: imports))
        } catch {
            fail("Could not save the queue", error)
        }
    }

    private(set) var scan: Scan?
    private(set) var phase: Phase = .idle
    private(set) var progress: RipProgress?
    var selectedTitles: Set<Int> = []

    /// Titles the user has sent to Import, by index, and how far each has got. A title here stays
    /// ticked and can no longer be unticked; more can be ticked and sent while these are running.
    private(set) var importStatus: [Int: ImportStatus] = [:]
    /// Titles waiting for the import worker, in the order they were sent.
    private var importQueue: [Int] = []
    /// How many titles have been sent this batch and how many the worker has started, for the
    /// "n of m" in the progress bar. The total grows when more are sent while the batch runs, and
    /// the bar reads both live rather than a snapshot taken when the current title began.
    private(set) var importBatchTotal = 0
    private(set) var importBatchDone = 0
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

    // MARK: - Engine

    /// The running engine, started on first use. Its messages and progress land where robot mode's
    /// do, so the rest of the window does not know which path is in use.
    private func engineSession() async throws -> EngineSession {
        if let engine { return engine }
        guard let makeMKV else { throw MakeMKVError.executableNotFound(searched: []) }
        let session = EngineSession(executable: makeMKV.executable)
        await session.setEventHandler { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                switch event.kind {
                case .message(let message): self.record([message])
                case .progress(let progress): self.progress = progress
                case .currentInfo, .jobStarted, .jobFinished: break
                }
            }
        }
        try await session.start()
        let version = try await session.appString(.version) ?? "?"
        note("MakeMKV engine \(version) started and kept open")
        engine = session
        return session
    }

    /// Quit the engine, if one is running. Called when the app exits.
    func shutdown() async {
        await engine?.quit()
        engine = nil
    }

    func refreshDrives() async {
        guard let makeMKV, !phase.isBusy else { return }
        phase = .listingDrives
        // Only give the phase back if nothing took it over meanwhile: an import sent during the
        // listing starts its worker, and the worker owns the phase from then on.
        defer { if phase == .listingDrives { phase = .idle } }
        do {
            drives = try await (useEngineSession ? engineSession().drives() : makeMKV.drives()).filter(\.isPresent)
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
        if scanUsedEngine, let engine {
            try? await engine.close()
        }
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
            let settings = ScanSettings(minimumTitleLength: minimumTitleLength)
            let result: Scan
            if useEngineSession {
                // The engine opens the disc and keeps it open; the titles it hands back are the
                // same shape a robot scan gives, and imports then come from the open disc.
                let session = try await engineSession()
                let disc = try await session.open(picked.source, minimumTitleLength: minimumTitleLength)
                result = Scan(source: picked.source, settings: settings, disc: disc)
                scanUsedEngine = true
            } else {
                // Messages are logged as they arrive, so the log moves while the disc is being read.
                result = try await makeMKV.scan(picked.source, settings: settings) { [weak self] line in
                    Task { @MainActor in self?.record(line) }
                }
                scanUsedEngine = false
            }
            scan = result
            // MakeMKV ticks every title it lists; so do we, minus what this disc's history says
            // has already been imported.
            selectedTitles = Set(result.titles.map(\.index))
            note("\(result.titles.count) title(s) on \(result.disc?.name ?? "the disc")")
            await fingerprintScannedDisc(picked, volumeName: result.disc?.volumeName)
            applyImportHistory()
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
    /// as each completes, so the queue grows while the batch is still running. Both the queue and
    /// the disc's history are saved at once, so a quit mid-batch loses nothing already done.
    func recordImport(of title: Title, from scan: Scan, at fileURL: URL) {
        let discName = scan.disc?.name ?? "Disc"
        let item = ImportedItem(fileURL: fileURL, discName: discName, fingerprint: fingerprint, title: title)
        assignQueue.append(item)
        let discKey = IngestStore.discKey(fingerprint: fingerprint, discName: discName)
        imports[discKey, default: [:]][IngestStore.titleKey(title)] = ImportRecord(titleIndex: title.index, fileURL: fileURL, importedAt: item.importedAt)
        persist()
    }

    /// The disc's key in the import history, for the scan in hand.
    var currentDiscKey: String? {
        scan.map { IngestStore.discKey(fingerprint: fingerprint, discName: $0.disc?.name ?? "Disc") }
    }

    /// After a scan: mark the titles this disc's history says were imported, and tick the rest.
    func applyImportHistory() {
        guard let scan, let discKey = currentDiscKey else { return }
        let history = imports[discKey] ?? [:]
        var marked = 0
        for title in scan.titles {
            if let record = history[IngestStore.titleKey(title)] {
                importStatus[title.index] = .previouslyImported(record.importedAt)
                selectedTitles.remove(title.index)
                marked += 1
            }
        }
        if marked > 0 {
            note("\(marked) title(s) already imported from this disc")
        }
    }

    /// Read the disc's fingerprint from its volume, off the main thread, since the scan already
    /// told us which volume it is. A disc macOS cannot mount, or an ISO, has none and is filed by
    /// name instead.
    private func fingerprintScannedDisc(_ picked: PickedSource, volumeName: String?) async {
        let root: URL? = switch picked {
        case .drive: volumeName.flatMap(DiscFingerprinter.volume(named:))
        case .folder(let url): url
        case .iso: nil
        }
        guard let root else {
            fingerprint = nil
            note("Disc volume not readable; its history is filed by name")
            return
        }
        let result = await Task.detached { try DiscFingerprinter.fingerprint(root: root) }.result
        switch result {
        case .success(let print):
            fingerprint = print
            if let print {
                note("Fingerprint \(print.contentHash)" + (print.aacsDiscId.map { ", AACS \($0)" } ?? ""))
            }
        case .failure(let error):
            fingerprint = nil
            fail("Could not fingerprint the disc", error)
        }
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
            phase = .ripping(titleIndex: index)
            progress = nil
            importStatus[index] = .importing
            note("Importing title \(index) (\(title.sourceIdentifier ?? "?")) to \(destination.path)")
            do {
                let outputURL: URL
                if scanUsedEngine, let engine {
                    // One title per job from the disc the engine still has open: no re-read, and
                    // each file is complete when its job ends, so the queue moves file by file.
                    for other in scan.titles {
                        try await engine.setSelected(other.index == index, title: other.index)
                    }
                    for track in title.tracks {
                        try await engine.setSelected(Preferences.keepTrack(track), title: index, track: track.index)
                    }
                    try await engine.saveSelectedTitles(to: destination)
                    outputURL = destination.appendingPathComponent(title.outputFileName ?? "title\(index).mkv")
                    guard FileManager.default.fileExists(atPath: outputURL.path) else {
                        throw MakeMKVError.outputMissing(outputURL, messages: [])
                    }
                } else {
                    let result = try await makeMKV.rip(title, from: scan, to: destination, profile: profile) { [weak self] line in
                        Task { @MainActor in self?.record(line) }
                    } progress: { [weak self] progress in
                        Task { @MainActor in self?.progress = progress }
                    }
                    outputURL = result.outputURL
                }
                note("Wrote \(outputURL.lastPathComponent)")
                importStatus[index] = .imported
                recordImport(of: title, from: scan, at: outputURL)
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
    func adoptForTesting(_ scan: Scan, makeMKV: MakeMKV?, fingerprint: DiscFingerprint? = nil) {
        self.scan = scan
        self.makeMKV = makeMKV
        self.fingerprint = fingerprint
        selectedTitles = Set(scan.titles.map(\.index))
        importStatus = [:]
        applyImportHistory()
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
