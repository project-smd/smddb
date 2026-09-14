// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import DiskArbitration
import Foundation
import IOKit

/// Reports when the set of optical drives, or the discs in them, may have changed.
///
/// Two sources, because no one channel covers both events. A disc going in or coming out is a
/// DiskArbitration disk appearing or disappearing, matched on the optical media kinds; that fires
/// whether or not a volume mounts, which matters for a disc macOS cannot read. A drive being
/// plugged in or unplugged is an IOKit matching notification on the drive's own service class,
/// which exists with or without a disc in it. File system events cover neither: an empty drive
/// has no directory to watch.
///
/// Events are debounced, since one insertion produces several, and delivered as a single "look
/// again" — the watcher never says what changed, because MakeMKV's drive table is the only view
/// of drives the rest of the tool uses, and it has to be re-read anyway.
final class DriveWatcher: @unchecked Sendable {
    /// The `IOMedia` subclasses for optical discs, as DiskArbitration reports them.
    static let opticalMediaKinds: Set<String> = ["IOBDMedia", "IODVDMedia", "IOCDMedia"]
    /// The IOKit service classes an optical drive registers as.
    static let driveClasses = ["IOBDServices", "IODVDServices"]

    private let queue = DispatchQueue(label: "smddb.ingest.drive-watcher")
    private let session: DASession
    private let notificationPort: IONotificationPortRef
    private var iterators: [io_iterator_t] = []
    private let mediaKinds: Set<String>?
    private let onChange: @Sendable () -> Void
    private var debounce: DispatchWorkItem?
    /// Registration replays the current state — every existing disk "appears" — and that is not a
    /// change. Nothing is reported until this is set, a moment after registration completes.
    private var armed = false

    /// - Parameter mediaKinds: the DiskArbitration media kinds to react to; `nil` reacts to every
    ///   disk, which exists so the plumbing can be exercised with a disk image.
    init?(mediaKinds: Set<String>? = DriveWatcher.opticalMediaKinds, onChange: @escaping @Sendable () -> Void) {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return nil }
        self.session = session
        self.notificationPort = IONotificationPortCreate(kIOMainPortDefault)
        self.mediaKinds = mediaKinds
        self.onChange = onChange

        let context = Unmanaged.passUnretained(self).toOpaque()

        DASessionSetDispatchQueue(session, queue)
        DARegisterDiskAppearedCallback(session, nil, DriveWatcher.diskChanged, context)
        DARegisterDiskDisappearedCallback(session, nil, DriveWatcher.diskChanged, context)

        IONotificationPortSetDispatchQueue(notificationPort, queue)
        for driveClass in Self.driveClasses {
            for kind in [kIOFirstMatchNotification, kIOTerminatedNotification] {
                var iterator: io_iterator_t = 0
                let status = IOServiceAddMatchingNotification(
                    notificationPort, kind, IOServiceMatching(driveClass), DriveWatcher.driveChanged, context, &iterator
                )
                guard status == KERN_SUCCESS else { continue }
                // The iterator starts holding every existing match, and delivers nothing further
                // until it has been drained once.
                Self.drain(iterator)
                iterators.append(iterator)
            }
        }

        queue.asyncAfter(deadline: .now() + 1) { [self] in armed = true }
    }

    deinit {
        DAUnregisterCallback(session, unsafeBitCast(DriveWatcher.diskChanged, to: UnsafeMutableRawPointer.self), Unmanaged.passUnretained(self).toOpaque())
        DASessionSetDispatchQueue(session, nil)
        for iterator in iterators {
            IOObjectRelease(iterator)
        }
        IONotificationPortDestroy(notificationPort)
    }

    // MARK: - Callbacks

    private static let diskChanged: DADiskAppearedCallback = { disk, context in
        let watcher = Unmanaged<DriveWatcher>.fromOpaque(context!).takeUnretainedValue()
        guard watcher.isRelevant(disk) else { return }
        watcher.scheduleChange()
    }

    private static let driveChanged: IOServiceMatchingCallback = { context, iterator in
        drain(iterator)
        let watcher = Unmanaged<DriveWatcher>.fromOpaque(context!).takeUnretainedValue()
        watcher.scheduleChange()
    }

    private func isRelevant(_ disk: DADisk) -> Bool {
        guard let mediaKinds else { return true }
        guard let description = DADiskCopyDescription(disk) as? [String: Any],
              let kind = description[kDADiskDescriptionMediaKindKey as String] as? String else {
            return false
        }
        return mediaKinds.contains(kind)
    }

    private func scheduleChange() {
        guard armed else { return }
        debounce?.cancel()
        let work = DispatchWorkItem { [onChange] in onChange() }
        debounce = work
        queue.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private static func drain(_ iterator: io_iterator_t) {
        var object = IOIteratorNext(iterator)
        while object != 0 {
            IOObjectRelease(object)
            object = IOIteratorNext(iterator)
        }
    }
}
