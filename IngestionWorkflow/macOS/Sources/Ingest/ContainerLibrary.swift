// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import Foundation
import Observation
import SmdKit

/// The containers in the repository folder, as the Containers window sees them: loaded whole,
/// indexed by id, and re-read whenever the folder might have changed under the tool, which in a
/// git clone is any time the window was not in front.
@MainActor
@Observable
final class ContainerLibrary {
    /// Nil until a repository folder is chosen in Settings.
    private(set) var repository: LocalRepository?
    private(set) var containers: [ContainerID: Container] = [:]
    /// The containers nothing holds, by title.
    private(set) var roots: [Container] = []
    /// Why the last load failed, when it did. Shown in place of the list: a repository that cannot
    /// be read is not an empty one.
    private(set) var loadError: String?
    private(set) var isLoading = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Picks up the repository folder preference and reads the folder. Cheap enough to call on
    /// every occasion the folder might have changed.
    func reload() async {
        let path = defaults.string(forKey: Preferences.repositoryFolder) ?? ""
        guard !path.isEmpty else {
            repository = nil
            containers = [:]
            roots = []
            loadError = nil
            return
        }
        let repository = LocalRepository(root: URL(fileURLWithPath: path, isDirectory: true))
        self.repository = repository
        isLoading = true
        defer { isLoading = false }
        do {
            let all = try await repository.containers()
            containers = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let held = Set(all.flatMap(\.childContainerIDs))
            roots = all.filter { !held.contains($0.id) }.sorted(by: Self.byTitle)
            loadError = nil
        } catch {
            containers = [:]
            roots = []
            loadError = error.localizedDescription
        }
    }

    /// Creates a container from the draft and returns its id: at the top level, or, when `parent`
    /// is given, as the last item of the parent's first sequence, which is made if there is none.
    func add(_ draft: ContainerDraft, inside parent: ContainerID?) async throws -> ContainerID {
        guard let repository else { throw LibraryError.noRepository }
        guard let parent else {
            let root = draft.container()
            try await repository.save(root)
            await reload()
            return root.id
        }
        let added = try await addItem(ItemDraft(kind: .container, container: draft), to: parent, in: .sequence(0))
        guard let child = added.container else { throw LibraryError.missingContainer(parent) }
        return child
    }

    /// Appends an item to one of the container's sequences or to its extras, and says where it
    /// landed. A child container is written first: if writing the parent then fails, the child
    /// shows as a loose root rather than being lost. Adding to the first sequence of a container
    /// that has none makes it, since that is where a first child goes.
    @discardableResult
    func addItem(_ draft: ItemDraft, to id: ContainerID, in place: EntryPlace) async throws -> AddedItem {
        guard let repository else { throw LibraryError.noRepository }
        var child: Container?
        if draft.kind == .container {
            let container = draft.container.container()
            try await repository.save(container)
            child = container
        }
        var added: AddedItem?
        try await update(id) { container in
            if case .sequence(let index) = place {
                if index == 0, container.sequences.isEmpty { container.sequences.append(Sequence()) }
                guard container.sequences.indices.contains(index) else { throw LibraryError.noSuchSequence("\(index + 1)") }
            }
            let itemID = Slug.unique(from: draft.itemTitle, avoiding: container.itemIDs)
            let entry = child.map { Entry.child($0, id: itemID) } ?? draft.entry(id: itemID)
            container[place].append(entry)
            added = AddedItem(place: place, index: container[place].count - 1, itemID: itemID, container: child?.id)
        }
        guard let added else { throw LibraryError.missingContainer(id) }
        return added
    }

    /// Appends an alternative and returns its id. The first alternative a container gets becomes
    /// the one played by default, since a client has to play something when it has not asked.
    @discardableResult
    func addAlternative(_ draft: AlternativeDraft, to id: ContainerID) async throws -> String {
        var alternativeID = ""
        try await update(id) { container in
            guard container.sequences.contains(where: { $0.id == draft.sequence }) else {
                throw LibraryError.noSuchSequence(draft.sequence)
            }
            alternativeID = Slug.unique(from: draft.title, avoiding: Set(container.alternatives.map(\.id)))
            container.alternatives.append(Alternative(
                id: alternativeID,
                sequence: draft.sequence,
                title: draft.title.trimmingCharacters(in: .whitespaces).nonEmpty,
                outline: draft.outline.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ))
            if draft.isDefault || container.defaultAlternative == nil {
                container.defaultAlternative = alternativeID
            }
        }
        return alternativeID
    }

    /// Appends a feature and returns its id, made from the title, or from the type when there is
    /// no title: one untitled commentary is "commentary", the next "commentary-2".
    @discardableResult
    func addFeature(_ draft: FeatureDraft, to id: ContainerID) async throws -> String {
        var featureID = ""
        try await update(id) { container in
            let title = draft.title.trimmingCharacters(in: .whitespaces)
            featureID = Slug.unique(from: title.isEmpty ? draft.type.rawValue : title, avoiding: Set(container.features.map(\.id)))
            container.features.append(Feature(id: featureID, type: draft.type, title: title.nonEmpty, participants: draft.participants))
        }
        return featureID
    }

    /// Appends a sequence and returns its index. An id is optional, as the sidecar allows, but one
    /// that is given must be a slug no other sequence of the container uses.
    @discardableResult
    func addSequence(_ draft: SequenceDraft, to id: ContainerID) async throws -> Int {
        var index = 0
        try await update(id) { container in
            let sequenceID = draft.id.trimmingCharacters(in: .whitespaces).nonEmpty
            if let sequenceID {
                guard Slug.isValid(sequenceID) else { throw LibraryError.invalidSlug(sequenceID) }
                guard !container.sequences.contains(where: { $0.id == sequenceID }) else { throw LibraryError.duplicateSlug(sequenceID) }
            }
            container.sequences.append(Sequence(id: sequenceID, exploded: draft.exploded))
            index = container.sequences.count - 1
        }
        return index
    }

    /// Re-orders one of the container's lists, as a drag in the outline does. Which alternative
    /// plays by default is an id, so moving alternatives does not change it.
    func move(_ section: OutlineSection, in id: ContainerID, from source: IndexSet, to destination: Int) async throws {
        try await update(id) { container in
            switch section {
            case .alternatives: container.alternatives.move(fromOffsets: source, toOffset: destination)
            case .features: container.features.move(fromOffsets: source, toOffset: destination)
            case .sequences: container.sequences.move(fromOffsets: source, toOffset: destination)
            case .items(let place): container[place].move(fromOffsets: source, toOffset: destination)
            }
        }
    }

    /// Writes an edited container back, after tidying what an editor leaves — padding, empty
    /// references, a year on a type that has none — and refusing what the sidecar's validator
    /// would: no title, a sequence id that is not a slug or not unique, an alternative playing a
    /// sequence that is not there, a default that is not an alternative, an anchor that is not an
    /// item. Nothing is written when anything is refused.
    func save(_ edited: Container) async throws {
        guard let repository else { throw LibraryError.noRepository }
        var container = edited
        container.title = container.title.trimmingCharacters(in: .whitespaces)
        container.typeLabel = container.typeLabel?.trimmingCharacters(in: .whitespaces).nonEmpty
        container.outline = container.outline?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        container.externalRefs = container.externalRefs.cleaned
        if !container.type.hasYear { container.year = nil }
        if container.year == nil { container.yearInTitle = false }
        for index in container.alternatives.indices {
            container.alternatives[index].title = container.alternatives[index].title?.trimmingCharacters(in: .whitespaces).nonEmpty
            container.alternatives[index].outline = container.alternatives[index].outline?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        }
        for index in container.features.indices {
            container.features[index].title = container.features[index].title?.trimmingCharacters(in: .whitespaces).nonEmpty
            container.features[index].participants = container.features[index].participants.compactMap { participant in
                let name = participant.name.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return nil }
                return Participant(name: name, role: participant.role?.trimmingCharacters(in: .whitespaces).nonEmpty)
            }
        }
        let places = container.sequences.indices.map(EntryPlace.sequence) + [.extras]
        for place in places {
            var items = container[place]
            for index in items.indices where items[index].ref == nil {
                items[index].title = items[index].title?.trimmingCharacters(in: .whitespaces).nonEmpty
                items[index].outline = items[index].outline?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                items[index].externalRefs = items[index].externalRefs.cleaned
            }
            container[place] = items
        }
        try Self.check(container)
        try await repository.save(container)
        await reload()
    }

    static func check(_ container: Container) throws {
        guard !container.title.isEmpty else { throw LibraryError.emptyTitle }
        var sequenceIDs = Set<String>()
        for sequence in container.sequences {
            guard let id = sequence.id else { continue }
            guard Slug.isValid(id) else { throw LibraryError.invalidSlug(id) }
            guard sequenceIDs.insert(id).inserted else { throw LibraryError.duplicateSlug(id) }
        }
        for alternative in container.alternatives {
            guard sequenceIDs.contains(alternative.sequence) else { throw LibraryError.noSuchSequence(alternative.sequence) }
        }
        if let id = container.defaultAlternative {
            guard container.alternatives.contains(where: { $0.id == id }) else { throw LibraryError.noSuchAlternative(id) }
        }
        for feature in container.features {
            guard Slug.isValid(feature.type.rawValue) else { throw LibraryError.invalidSlug(feature.type.rawValue) }
        }
        if let anchor = container.extrasAnchor {
            guard container.sequences.flatMap(\.items).compactMap(\.id).contains(anchor) else { throw LibraryError.noSuchItem(anchor) }
        }
    }

    /// Applies `change` to the container as last read, writes it, and re-reads the folder.
    private func update(_ id: ContainerID, _ change: (inout Container) throws -> Void) async throws {
        guard let repository else { throw LibraryError.noRepository }
        guard var container = containers[id] else { throw LibraryError.missingContainer(id) }
        try change(&container)
        try await repository.save(container)
        await reload()
    }

    /// The tree under each root, for an outline. A container held by two parents appears under
    /// both; one that holds itself, however indirectly, is cut where the cycle closes rather
    /// than looped over.
    var tree: [ContainerNode] {
        roots.map { node(for: $0, ancestors: []) }
    }

    private func node(for container: Container, ancestors: Set<ContainerID>) -> ContainerNode {
        let ancestors = ancestors.union([container.id])
        let children = container.childContainerIDs.compactMap { id -> ContainerNode? in
            guard !ancestors.contains(id), let child = containers[id] else { return nil }
            return node(for: child, ancestors: ancestors)
        }
        return ContainerNode(container: container, children: children.isEmpty ? nil : children)
    }

    private static func byTitle(_ a: Container, _ b: Container) -> Bool {
        a.title.localizedStandardCompare(b.title) == .orderedAscending
    }
}

/// Where an item goes in a container: one of its sequences, by index, or its extras.
enum EntryPlace: Hashable {
    case sequence(Int)
    case extras
}

/// The lists a container has that the outline shows and re-orders.
enum OutlineSection: Hashable {
    case alternatives, features, sequences
    case items(EntryPlace)
}

extension Container {
    /// The items at a place. Reading a sequence the container does not have gives nothing, and
    /// writing to one is dropped: a place is a position the outline showed, and the container may
    /// have changed under it since.
    subscript(place: EntryPlace) -> [Entry] {
        get {
            switch place {
            case .sequence(let index): sequences.indices.contains(index) ? sequences[index].items : []
            case .extras: extras
            }
        }
        set {
            switch place {
            case .sequence(let index): if sequences.indices.contains(index) { sequences[index].items = newValue }
            case .extras: extras = newValue
            }
        }
    }
}

/// Where an item landed when it was added.
struct AddedItem: Hashable {
    let place: EntryPlace
    let index: Int
    let itemID: String
    /// The child container's id, when the item is one.
    let container: ContainerID?
}

/// What the Add sheet collects for a container: only what it needs to exist. Its sequences,
/// alternatives, features and extras are added to it afterwards, from the outline.
struct ContainerDraft {
    var type: ContainerType = .series
    var title = ""
    /// As typed; `yearValue` is the number, when it is one.
    var year = ""
    var yearInTitle = false
    var typeLabel = ""
    var outline = ""
    var externalRefs: [ExternalRef] = []

    var yearValue: Int? {
        Int(year.trimmingCharacters(in: .whitespaces))
    }

    /// A year that is typed has to be a number; one that is not typed is fine, and one on a type
    /// that has no year is ignored rather than refused, since the type may change after it.
    var yearIsValid: Bool {
        !type.hasYear || year.trimmingCharacters(in: .whitespaces).isEmpty || yearValue != nil
    }

    var isComplete: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && yearIsValid
    }

    func container() -> Container {
        let year = type.hasYear ? yearValue : nil
        return Container(
            type: type,
            typeLabel: typeLabel.trimmingCharacters(in: .whitespaces).nonEmpty,
            title: title.trimmingCharacters(in: .whitespaces),
            year: year,
            yearInTitle: year != nil && yearInTitle,
            outline: outline.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
            externalRefs: externalRefs.cleaned
        )
    }

    /// The type a child of `parent` most often is, as the sheet's first guess.
    static func usualChildType(of parent: ContainerType?) -> ContainerType {
        switch parent {
        case nil: .series
        case .series: .season
        case .season: .serial
        case .serial, .arc, .volume: .episode
        case .collection: .movie
        case .episode, .movie: .episode
        }
    }
}

/// What the Add sheet collects for an item: an episode, a film or a featurette with a title of
/// its own, or a child container, in which case the container draft is the item and the title
/// is its title.
struct ItemDraft {
    enum Kind: String, CaseIterable, Hashable {
        case episode = "Episode"
        case movie = "Movie"
        case featurette = "Featurette"
        case container = "Container"

        var entryType: EntryType {
            switch self {
            case .episode: .episode
            case .movie: .movie
            case .featurette: .featurette
            case .container: .container
            }
        }
    }

    var kind: Kind = .episode
    var title = ""
    var outline = ""
    var optional = false
    var externalRefs: [ExternalRef] = []
    var container = ContainerDraft()

    var itemTitle: String {
        (kind == .container ? container.title : title).trimmingCharacters(in: .whitespaces)
    }

    var isComplete: Bool {
        kind == .container ? container.isComplete : !itemTitle.isEmpty
    }

    /// The entry for a kind other than `.container`, whose entry is made from the child instead.
    func entry(id: String) -> Entry {
        Entry(
            id: id,
            type: kind.entryType,
            optional: optional,
            title: itemTitle,
            outline: outline.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
            externalRefs: externalRefs.cleaned
        )
    }
}

struct AlternativeDraft {
    var title = ""
    /// The id of the sequence it plays; an alternative cannot name an unnamed one.
    var sequence = ""
    var outline = ""
    var isDefault = false

    var isComplete: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !sequence.isEmpty
    }
}

struct FeatureDraft {
    var type: FeatureType = .commentary
    var title = ""
    /// Names, one per line or comma-separated; roles are authored later, when a binding needs them.
    var participantNames = ""

    var participants: [Participant] {
        participantNames
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { Participant(name: $0) }
    }
}

struct SequenceDraft {
    var id = ""
    var exploded: Exploded = .never
}

/// A container and the containers it holds, for `List(children:)`.
struct ContainerNode: Identifiable {
    let container: Container
    /// Nil, not empty, for a leaf: an empty array draws a disclosure triangle with nothing under it.
    let children: [ContainerNode]?

    var id: ContainerID { container.id }
}

enum LibraryError: LocalizedError, Equatable {
    case noRepository
    case missingContainer(ContainerID)
    case emptyTitle
    case noSuchSequence(String)
    case noSuchAlternative(String)
    case noSuchItem(String)
    case invalidSlug(String)
    case duplicateSlug(String)

    var errorDescription: String? {
        switch self {
        case .noRepository: "Choose a repository folder in Settings first"
        case .missingContainer(let id): "Container \(id) is no longer in the repository"
        case .emptyTitle: "A container needs a title"
        case .noSuchSequence(let id): "There is no sequence \"\(id)\""
        case .noSuchAlternative(let id): "There is no alternative \"\(id)\" to play by default"
        case .noSuchItem(let id): "There is no item \"\(id)\" in a sequence to anchor the extras at"
        case .invalidSlug(let id): "\"\(id)\" is not an id: use lowercase letters, digits and hyphens"
        case .duplicateSlug(let id): "There is already a sequence called \"\(id)\""
        }
    }
}

extension [ExternalRef] {
    /// Values trimmed, and references with no value dropped: an editor's empty row is not a fact.
    var cleaned: [ExternalRef] {
        compactMap { ref in
            let value = ref.value.trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : ExternalRef(provider: ref.provider, value: value)
        }
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
