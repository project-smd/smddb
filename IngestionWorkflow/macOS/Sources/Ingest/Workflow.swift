// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import Foundation
import MakeMKVRobot

/// The stages of the ingestion flow, in the order a file moves through them. The sidebar lists
/// them; a file enters the next stage's queue the moment it is done with the previous one.
enum Stage: String, CaseIterable, Identifiable, Hashable {
    /// Scan a disc and rip the ticked titles. Everything the tool did before it had stages.
    case `import`
    /// Say what each ripped file is: which container, which entry, which cut.
    case assign

    var id: String { rawValue }

    var title: String {
        switch self {
        case .import: "Import"
        case .assign: "Assign"
        }
    }

    var systemImage: String {
        switch self {
        case .import: "square.and.arrow.down"
        case .assign: "tag"
        }
    }
}

/// A file the Import stage has finished with, waiting in the Assign queue.
///
/// Carries what was known at rip time and is unrecoverable afterwards: the disc it came from and
/// the title on that disc, which is the `<source>` the sidecar proposal records. The title is kept
/// whole rather than by index, because an index only means something against the scan it came
/// from and the scan is gone by the time anyone assigns.
struct ImportedItem: Identifiable, Hashable, Codable {
    let id: UUID
    var fileURL: URL
    var discName: String
    /// The pressing the file came from, when the disc could be fingerprinted at import time. This
    /// is what the sidecar's source element names, and what the database is keyed on.
    var fingerprint: DiscFingerprint?
    var title: Title
    var importedAt: Date

    init(id: UUID = UUID(), fileURL: URL, discName: String, fingerprint: DiscFingerprint? = nil, title: Title, importedAt: Date = .now) {
        self.id = id
        self.fileURL = fileURL
        self.discName = discName
        self.fingerprint = fingerprint
        self.title = title
        self.importedAt = importedAt
    }

    var fileName: String { fileURL.lastPathComponent }
}
