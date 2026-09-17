// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import Foundation

/// The database as a folder: a clone of the data repository, with one file per container under
/// `containers/`. Nothing else is assumed about the folder — it need not be a git checkout, and
/// committing what was written is the user's act, not this type's.
///
/// Every read goes to disk. The files are small and few, principle 1 of the database proposal
/// says they stay that way, and a cache would have to be told about edits made outside the tool,
/// which in a git clone is the normal case.
public struct LocalRepository: ContainerDatabase {
    public let root: URL

    public static let containersFolder = "containers"

    public init(root: URL) {
        self.root = root
    }

    public var containersURL: URL {
        root.appendingPathComponent(Self.containersFolder, isDirectory: true)
    }

    public func fileURL(for id: ContainerID) -> URL {
        containersURL.appendingPathComponent(ContainerFile.fileName(for: id))
    }

    public func containers() async throws -> [Container] {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: containersURL, includingPropertiesForKeys: nil)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
        return try files
            .filter { $0.pathExtension == ContainerFile.fileExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map(read)
    }

    public func container(_ id: ContainerID) async throws -> Container? {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try read(url)
    }

    public func containers(matching ref: ExternalRef) async throws -> [Container] {
        try await containers().filter { $0.externalRefs.contains(ref) }
    }

    public func save(_ container: Container) async throws {
        try FileManager.default.createDirectory(at: containersURL, withIntermediateDirectories: true)
        try ContainerFile.data(for: container).write(to: fileURL(for: container.id), options: .atomic)
    }

    /// A file is named for its id, so a file named for anything else is refused rather than read
    /// under a name the document did not claim.
    private func read(_ url: URL) throws -> Container {
        guard let expected = ContainerID(url.deletingPathExtension().lastPathComponent) else {
            throw LocalRepositoryError.unexpectedFile(url)
        }
        do {
            return try ContainerFile.container(from: try Data(contentsOf: url), expecting: expected)
        } catch let error as ContainerFileError {
            throw LocalRepositoryError.unreadable(url, error)
        }
    }
}

public enum LocalRepositoryError: Error, LocalizedError {
    case unexpectedFile(URL)
    case unreadable(URL, ContainerFileError)

    public var errorDescription: String? {
        switch self {
        case .unexpectedFile(let url): "\(url.lastPathComponent) is in the containers folder but is not named for a container id"
        case .unreadable(let url, let error): "\(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}
