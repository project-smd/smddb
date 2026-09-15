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
}

/// Everything the tool remembers between launches. One JSON file, rewritten whole on every change:
/// it is small, and a file that is always complete is easier to reason about than a log.
struct PersistedState: Codable {
    var assignQueue: [ImportedItem] = []
    /// Import history, by disc key and then by title key. See `IngestStore.discKey` and `titleKey`.
    var imports: [String: [String: ImportRecord]] = [:]
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
}
