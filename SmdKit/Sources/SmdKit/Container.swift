// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import Foundation

/// The identity of a container in the database: minted once, when the container is created, and
/// never reissued. Sixteen lowercase hex characters, 64 random bits, as `ContainerDatabase.md`
/// specifies: minted without coordination, as a clone of the data repository has to, and short
/// enough to read in a ref or a file listing. Readability in a review comes from the file's title,
/// not its name.
public struct ContainerID: Hashable, Sendable, Codable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The string as an id, or nil when it is not one: the shape is checked, not the provenance,
    /// so an id minted by any tool that draws sixteen hex characters is accepted.
    public init?(_ string: String) {
        guard string.count == 16, string.unicodeScalars.allSatisfy({ ($0.value >= 0x30 && $0.value <= 0x39) || ($0.value >= 0x61 && $0.value <= 0x66) }) else {
            return nil
        }
        self.init(rawValue: string)
    }

    public static func mint() -> ContainerID {
        ContainerID(rawValue: String(format: "%016llx", UInt64.random(in: .min ... .max)))
    }

    public var description: String { rawValue }
}

/// What a container is, from the sidecar's `type` attribute. The label shown for it is separate
/// (`Container.typeLabel`): a serial is called a story by one show and a serial by another.
public enum ContainerType: String, CaseIterable, Sendable, Codable {
    case series, season, serial, arc, volume, collection, episode, movie

    public var title: String {
        switch self {
        case .series: "Series"
        case .season: "Season"
        case .serial: "Serial"
        case .arc: "Arc"
        case .volume: "Volume"
        case .collection: "Collection"
        case .episode: "Episode"
        case .movie: "Movie"
        }
    }

    /// Whether a container of this type has a year of its own: a series began in one, a season
    /// aired in one, a film was released in one. A serial or an episode takes its year from the
    /// season it is in, and a collection has none.
    public var hasYear: Bool {
        switch self {
        case .series, .season, .movie: true
        case .serial, .arc, .volume, .collection, .episode: false
        }
    }
}

/// Who else knows this thing, and by what name. Providers are open-ended — a new one is a string,
/// not a code change — with the ones the proposals name given here so they are spelled once.
public struct Provider: Hashable, Sendable, Codable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let tvdb = Provider(rawValue: "tvdb")
    public static let tmdb = Provider(rawValue: "tmdb")
    public static let imdb = Provider(rawValue: "imdb")
    public static let wikidata = Provider(rawValue: "wikidata")
    public static let thediscdb = Provider(rawValue: "thediscdb")
    public static let upc = Provider(rawValue: "upc")
    public static let asin = Provider(rawValue: "asin")

    /// The ones a container or an entry is usually identified by, in the order a picker lists them.
    public static let known: [Provider] = [.tvdb, .tmdb, .imdb, .wikidata]

    public var title: String {
        switch self {
        case .tvdb: "TVDB"
        case .tmdb: "TMDb"
        case .imdb: "IMDb"
        case .wikidata: "Wikidata"
        case .thediscdb: "TheDiscDb"
        case .upc: "UPC"
        case .asin: "ASIN"
        default: rawValue
        }
    }

    public var description: String { rawValue }
}

public struct ExternalRef: Hashable, Sendable, Codable {
    public var provider: Provider
    public var value: String

    public init(provider: Provider, value: String) {
        self.provider = provider
        self.value = value
    }
}

/// One container, as the database keeps it: the sidecar's `<container>` with everything a library
/// adds — file paths and presentations — taken out, and what the database adds — external
/// references, and children named by identity rather than by path — put in.
public struct Container: Identifiable, Hashable, Sendable {
    public var id: ContainerID
    public var type: ContainerType
    /// What to call the type: "Story", "Season", "Volume". Nil means the type's own name.
    public var typeLabel: String?
    public var title: String
    /// The year a series began, a season aired or a film was released, for the types that have
    /// one (`ContainerType.hasYear`). Nil elsewhere.
    public var year: Int?
    /// Whether the year is part of how the container is named — "Doctor Who (1963)" against
    /// "Doctor Who" — as a library folder or a listing shows it. See `displayTitle`.
    public var yearInTitle: Bool
    public var outline: String?
    /// False for a companion series nobody browses to directly: reachable through a relation or a
    /// ref, and nowhere else.
    public var listed: Bool
    public var externalRefs: [ExternalRef]
    /// Which alternative a client plays when it has not been asked; the id of one in `alternatives`.
    public var defaultAlternative: String?
    public var alternatives: [Alternative]
    public var features: [Feature]
    public var sequences: [Sequence]
    /// The item in the sequences the extras hang off, when they hang off one.
    public var extrasAnchor: String?
    public var extras: [Entry]

    public init(
        id: ContainerID = .mint(),
        type: ContainerType,
        typeLabel: String? = nil,
        title: String,
        year: Int? = nil,
        yearInTitle: Bool = false,
        outline: String? = nil,
        listed: Bool = true,
        externalRefs: [ExternalRef] = [],
        defaultAlternative: String? = nil,
        alternatives: [Alternative] = [],
        features: [Feature] = [],
        sequences: [Sequence] = [],
        extrasAnchor: String? = nil,
        extras: [Entry] = []
    ) {
        self.id = id
        self.type = type
        self.typeLabel = typeLabel
        self.title = title
        self.year = year
        self.yearInTitle = yearInTitle
        self.outline = outline
        self.listed = listed
        self.externalRefs = externalRefs
        self.defaultAlternative = defaultAlternative
        self.alternatives = alternatives
        self.features = features
        self.sequences = sequences
        self.extrasAnchor = extrasAnchor
        self.extras = extras
    }

    /// The title with the year after it when `yearInTitle` says so and there is one.
    public var displayTitle: String {
        if yearInTitle, let year { "\(title) (\(year))" } else { title }
    }

    /// The containers this one holds, in the order its sequences and extras list them.
    public var childContainerIDs: [ContainerID] {
        (sequences.flatMap(\.items) + extras).compactMap(\.container)
    }

    /// Every item id declared here, sequences and extras together. Refs declare none.
    public var itemIDs: Set<String> {
        Set((sequences.flatMap(\.items) + extras).compactMap(\.id))
    }
}

/// A cut of the container: which sequence it plays, and what to call it.
public struct Alternative: Identifiable, Hashable, Sendable {
    public var id: String
    public var sequence: String
    public var title: String?
    public var outline: String?

    public init(id: String, sequence: String, title: String? = nil, outline: String? = nil) {
        self.id = id
        self.sequence = sequence
        self.title = title
        self.outline = outline
    }
}

/// Something an item can carry a track of: a commentary, an isolated score. Declared once, on the
/// container that owns it, and referenced by the items that have it.
public struct Feature: Identifiable, Hashable, Sendable {
    public var id: String
    public var type: FeatureType
    public var title: String?
    public var participants: [Participant]

    public init(id: String, type: FeatureType, title: String? = nil, participants: [Participant] = []) {
        self.id = id
        self.type = type
        self.title = title
        self.participants = participants
    }
}

public struct FeatureType: Hashable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let commentary = FeatureType(rawValue: "commentary")
    public static let isolatedMusic = FeatureType(rawValue: "isolatedMusic")

    public var description: String { rawValue }
}

public struct Participant: Hashable, Sendable {
    public var name: String
    public var role: String?

    public init(name: String, role: String? = nil) {
        self.name = name
        self.role = role
    }
}

/// An ordered run of items: the broadcast parts, the omnibus, a DVD order. A container with one
/// order of things has one sequence, and it need not be named.
public struct Sequence: Hashable, Sendable {
    public var id: String?
    public var exploded: Exploded
    public var items: [Entry]

    public init(id: String? = nil, exploded: Exploded = .never, items: [Entry] = []) {
        self.id = id
        self.exploded = exploded
        self.items = items
    }
}

/// Whether a client may show the sequence's items as if they were the container's parent's.
public enum Exploded: String, CaseIterable, Sendable, Codable {
    case never, allowed, preferred
}

/// The sidecar's `<item>`: an episode, a film, a featurette, a child container, or a ref to an
/// item declared elsewhere. Which of those it is determines which fields are set; the container
/// file's reader and the validator check the combination.
public struct Entry: Hashable, Sendable {
    /// The id, unique within the container. A ref has none.
    public var id: String?
    /// Nil on a ref, which takes its type from what it names.
    public var type: EntryType?
    public var optional: Bool
    /// A title and outline only when no provider has one for it.
    public var title: String?
    public var outline: String?
    /// The child container, when `type` is `.container`.
    public var container: ContainerID?
    /// What a ref names.
    public var ref: EntryRef?
    public var externalRefs: [ExternalRef]

    public init(
        id: String,
        type: EntryType,
        optional: Bool = false,
        title: String? = nil,
        outline: String? = nil,
        container: ContainerID? = nil,
        externalRefs: [ExternalRef] = []
    ) {
        self.id = id
        self.type = type
        self.optional = optional
        self.title = title
        self.outline = outline
        self.container = container
        self.ref = nil
        self.externalRefs = externalRefs
    }

    public init(ref: EntryRef) {
        self.id = nil
        self.type = nil
        self.optional = false
        self.ref = ref
        self.externalRefs = []
    }

    /// A child container item, named for the child so the parent reads on its own.
    public static func child(_ container: Container, id: String) -> Entry {
        Entry(id: id, type: .container, container: container.id)
    }
}

public struct EntryType: Hashable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let episode = EntryType(rawValue: "episode")
    public static let movie = EntryType(rawValue: "movie")
    public static let container = EntryType(rawValue: "container")
    public static let featurette = EntryType(rawValue: "featurette")

    public var description: String { rawValue }
}

/// An item in another sequence of the same container, or, with a container id, in any container.
public struct EntryRef: Hashable, Sendable {
    public var container: ContainerID?
    public var item: String

    public init(container: ContainerID? = nil, item: String) {
        self.container = container
        self.item = item
    }
}
