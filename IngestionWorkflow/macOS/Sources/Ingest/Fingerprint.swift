// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import CryptoKit
import Foundation

/// What identifies a pressing: TheDiscDb's two keys, so a disc known there and a disc known here
/// are recognisably the same object. Both are plain reads of the mounted volume.
///
/// The content hash is an MD5 over each stream file's size as a little-endian 64-bit integer,
/// files sorted by name, over `BDMV/STREAM/*.m2ts` on a Blu-ray and every file in `VIDEO_TS` on a
/// DVD. Names and dates are not hashed. Recomputing it from TheDiscDb's own logs reproduced 4,189
/// of 4,193 stored hashes, the misses being swapped files upstream. The AACS disc id is a SHA1 of
/// `AACS/Unit_Key_RO.inf`, an unencrypted file, the same id libbluray prints; DVDs have none here.
struct DiscFingerprint: Hashable, Codable {
    enum Format: String, Codable {
        case bluray
        case dvd
    }

    var format: Format
    var contentHash: String
    var aacsDiscId: String?
}

enum DiscFingerprinter {
    /// The mounted volume for a disc MakeMKV named, by its volume label. macOS mounts a readable
    /// disc at `/Volumes/<label>`; a disc it cannot read has no volume, and no fingerprint.
    static func volume(named label: String) -> URL? {
        let url = URL(fileURLWithPath: "/Volumes").appendingPathComponent(label)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Fingerprint the disc rooted at `root`: a mounted volume, or a folder holding a `BDMV` or
    /// `VIDEO_TS` tree such as a MakeMKV backup. `nil` when there is neither.
    static func fingerprint(root: URL) throws -> DiscFingerprint? {
        let fm = FileManager.default
        let stream = root.appendingPathComponent("BDMV/STREAM")
        let videoTS = root.appendingPathComponent("VIDEO_TS")

        if fm.fileExists(atPath: stream.path) {
            let files = try fm.contentsOfDirectory(at: stream, includingPropertiesForKeys: [.fileSizeKey])
                .filter { $0.pathExtension.lowercased() == "m2ts" }
            let hash = try contentHash(of: files)
            let keyFile = root.appendingPathComponent("AACS/Unit_Key_RO.inf")
            let discId = fm.fileExists(atPath: keyFile.path)
                ? Insecure.SHA1.hash(data: try Data(contentsOf: keyFile)).map { String(format: "%02X", $0) }.joined()
                : nil
            return DiscFingerprint(format: .bluray, contentHash: hash, aacsDiscId: discId)
        }
        if fm.fileExists(atPath: videoTS.path) {
            let files = try fm.contentsOfDirectory(at: videoTS, includingPropertiesForKeys: [.fileSizeKey])
            return DiscFingerprint(format: .dvd, contentHash: try contentHash(of: files), aacsDiscId: nil)
        }
        return nil
    }

    /// MD5 over the sizes of `files` as little-endian Int64, in name order, upper-case hex.
    static func contentHash(of files: [URL]) throws -> String {
        var md5 = Insecure.MD5()
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let size = Int64(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            withUnsafeBytes(of: size.littleEndian) { md5.update(bufferPointer: $0) }
        }
        return md5.finalize().map { String(format: "%02X", $0) }.joined()
    }
}
