// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import Foundation
import MakeMKVRobot

/// What a completed import left behind, kept per disc and per title so a disc put back in the
/// drive shows what was already taken from it.
struct ImportRecord: Hashable, Codable {
    var titleIndex: Int
    var fileURL: URL
    var importedAt: Date
    /// Set once the file was looked at in Assign and thrown away. The record stays, so the disc
    /// still shows the title as dealt with rather than offering it again.
    var rejection: Rejection?
}

/// Why an imported file was thrown away, and what the user called it.
struct Rejection: Hashable, Codable {
    enum Kind: String, Codable {
        /// Not useful content, on this disc.
        case rejected
        /// A studio logo, a warning card: the same clip turns up on other discs, and is rejected
        /// there too without being imported. See `PersistedState.discLogos`.
        case discLogo
    }

    var kind: Kind
    /// Shown after the title's name in Import: "Title 9 (FBI warning)". Required for a disc logo,
    /// where it is the only thing that says what was recognised on a disc nobody has looked at.
    var description: String?
    var rejectedAt: Date
}

/// A clip rejected as a disc logo or warning, remembered apart from any disc so that it is
/// recognised on the next one. Filed under `IngestStore.contentSignature`.
struct DiscLogo: Hashable, Codable {
    var description: String
    var rejectedAt: Date
    /// The disc it was first rejected from, for a person reading the state file.
    var discName: String
}

/// Everything the tool remembers between launches. One JSON file, rewritten whole on every change:
/// it is small, and a file that is always complete is easier to reason about than a log.
struct PersistedState: Codable {
    var assignQueue: [ImportedItem] = []
    /// Import history, by disc key and then by title key. See `IngestStore.discKey` and `titleKey`.
    var imports: [String: [String: ImportRecord]] = [:]
    /// Clips rejected as disc logos or warnings, by content signature, across all discs.
    var discLogos: [String: DiscLogo] = [:]

    init(assignQueue: [ImportedItem] = [], imports: [String: [String: ImportRecord]] = [:], discLogos: [String: DiscLogo] = [:]) {
        self.assignQueue = assignQueue
        self.imports = imports
        self.discLogos = discLogos
    }

    /// Every key is optional on the way in, so a state file written before a key existed still
    /// loads: a synthesized decoder would throw on the missing key and the whole state with it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assignQueue = try container.decodeIfPresent([ImportedItem].self, forKey: .assignQueue) ?? []
        imports = try container.decodeIfPresent([String: [String: ImportRecord]].self, forKey: .imports) ?? [:]
        discLogos = try container.decodeIfPresent([String: DiscLogo].self, forKey: .discLogos) ?? [:]
    }
}

/// The file behind `PersistedState`, in Application Support unless a directory is given.
struct IngestStore {
    let fileURL: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("smddb Ingest", isDirectory: true)
        fileURL = base.appendingPathComponent("state.json")
    }

    func load() -> PersistedState {
        guard let data = try? Data(contentsOf: fileURL) else { return PersistedState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(PersistedState.self, from: data)) ?? PersistedState()
    }

    func save(_ state: PersistedState) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: fileURL, options: .atomic)
    }

    /// The key a disc's history is filed under: its content hash when the disc could be
    /// fingerprinted, otherwise its MakeMKV name, marked as such so the two never collide.
    static func discKey(fingerprint: DiscFingerprint?, discName: String) -> String {
        fingerprint.map { "hash:" + $0.contentHash } ?? "name:" + discName
    }

    /// The subfolder within the output folder that a disc's files go in, so two discs with the
    /// same MakeMKV filename for a title do not overwrite each other. Shaped "<name> [<hash>]",
    /// the content hash being the disc's thumbprint; without a fingerprint (an unmountable disc or
    /// an ISO) it is the name alone. Characters that are path separators on macOS are replaced.
    static func discFolderName(discName: String, fingerprint: DiscFingerprint?) -> String {
        let safe = discName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        let name = safe.isEmpty ? "Disc" : safe
        return fingerprint.map { "\(name) [\($0.contentHash)]" } ?? name
    }

    /// The key a title is filed under within a disc: its natural identity, which survives a change
    /// of minimum length where MakeMKV's index does not.
    static func titleKey(_ title: Title) -> String {
        [title.sourceIdentifier ?? "?", title.segmentMap ?? "", title.durationText ?? ""].joined(separator: "|")
    }

    /// What a clip is, apart from where a disc keeps it: its exact size, its length, and the shape
    /// of each primary stream. The same studio logo on two discs has a different file name and
    /// sits in a different playlist, so neither is here, and nor are chapters or languages, which
    /// belong to the playlist rather than the clip. The bytes themselves cannot be compared: a
    /// Blu-ray's streams are encrypted per disc, and MakeMKV writes a fresh UID and date into each
    /// file. `nil` without a size and a duration, which is too little to recognise anything by.
    static func contentSignature(_ title: Title) -> String? {
        guard let size = title.sizeBytes, size > 0, let duration = title.durationSeconds else { return nil }
        let streams = title.primaryTracks.map { track -> String in
            let kind = switch track.kind {
            case .video: "v"
            case .audio: "a"
            case .subtitles: "s"
            case .unknown: "?"
            }
            let shape = track.videoSize ?? track.audioChannelsCount.map(String.init) ?? ""
            return [kind, track.codecId ?? "", shape].joined(separator: ":")
        }
        return (["\(size)", "\(duration)s"] + streams).joined(separator: "|")
    }
}
