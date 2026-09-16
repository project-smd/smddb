// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import Foundation
import SmdKit
import Testing
@testable import Ingest

/// The Containers window's model against a folder of its own: what it reads, what adding writes,
/// and how the tree is cut.
struct ContainerLibraryTests {
    /// A defaults suite of its own, so the repository folder preference here never touches the
    /// user's, and a temporary folder that the suite points at.
    @MainActor private func makeLibrary() -> (ContainerLibrary, LocalRepository, UserDefaults) {
        let folder = temporaryDirectory()
        let defaults = UserDefaults(suiteName: "ContainerLibraryTests-\(UUID().uuidString)")!
        defaults.set(folder.path, forKey: Preferences.repositoryFolder)
        return (ContainerLibrary(defaults: defaults), LocalRepository(root: folder), defaults)
    }

    @Test @MainActor func nothingChosenIsNoRepository() async {
        let defaults = UserDefaults(suiteName: "ContainerLibraryTests-\(UUID().uuidString)")!
        let library = ContainerLibrary(defaults: defaults)
        await library.reload()
        #expect(library.repository == nil)
        #expect(library.roots.isEmpty)
        #expect(library.loadError == nil)
        await #expect(throws: LibraryError.self) {
            try await library.add(ContainerDraft(type: .series, title: "x"), inside: nil)
        }
    }

    @Test @MainActor func addingFilesTheChildUnderItsParent() async throws {
        let (library, repository, _) = makeLibrary()
        await library.reload()
        #expect(library.repository != nil)
        #expect(library.roots.isEmpty)

        var draft = ContainerDraft(type: .series, title: " Doctor Who ", year: " 1963", yearInTitle: true, externalRefs: [ExternalRef(provider: .tvdb, value: "76107"), ExternalRef(provider: .imdb, value: " tt0056751 ")])
        let series = try await library.add(draft, inside: nil)
        draft = ContainerDraft(type: .season, title: "Season 13", typeLabel: "Series")
        let season = try await library.add(draft, inside: series)
        draft = ContainerDraft(type: .serial, title: "Pyramids of Mars", year: "1975", yearInTitle: true, typeLabel: "Story", outline: "A buried Osiran wakes under an Edwardian priory, and the Doctor has seen the future it leaves behind.\n", externalRefs: [ExternalRef(provider: .wikidata, value: " ")])
        let pyramids = try await library.add(draft, inside: season)

        // What was written: trimmed, an empty external id dropped, a year only on a type that has
        // one, the child named in its parent.
        let written = try #require(try await repository.container(series))
        #expect(written.title == "Doctor Who")
        #expect(written.year == 1963 && written.yearInTitle && written.displayTitle == "Doctor Who (1963)")
        #expect(written.externalRefs == [ExternalRef(provider: .tvdb, value: "76107"), ExternalRef(provider: .imdb, value: "tt0056751")])
        #expect(written.sequences.count == 1)
        #expect(written.sequences[0].items.map(\.id) == ["season-13"])
        #expect(written.childContainerIDs == [season])
        let writtenSeason = try #require(try await repository.container(season))
        #expect(writtenSeason.typeLabel == "Series")
        #expect(writtenSeason.outline == nil)
        let writtenPyramids = try #require(try await repository.container(pyramids))
        #expect(writtenPyramids.outline == "A buried Osiran wakes under an Edwardian priory, and the Doctor has seen the future it leaves behind.")
        #expect(writtenPyramids.externalRefs == [])
        #expect(writtenPyramids.year == nil && !writtenPyramids.yearInTitle)

        // What the window sees: one root, the tree beneath it, and a leaf with no children at all.
        #expect(library.roots.map(\.id) == [series])
        let tree = library.tree
        #expect(tree.count == 1)
        #expect(tree[0].children?.map(\.id) == [season])
        #expect(tree[0].children?[0].children?.map(\.id) == [pyramids])
        #expect(tree[0].children?[0].children?[0].children == nil)

        // A second child with the same title gets the next free item id.
        _ = try await library.add(ContainerDraft(type: .season, title: "Season 13"), inside: series)
        #expect(library.containers[series]?.sequences[0].items.map(\.id) == ["season-13", "season-13-2"])
    }

    /// Each of a container's lists grows at the end, from the outline's + buttons, and is re-ordered
    /// by a drag; ids are made from titles, and the first alternative is the one played by default.
    @Test @MainActor func listsGrowAtTheEndAndReorder() async throws {
        let (library, repository, _) = makeLibrary()
        await library.reload()
        let serial = try await library.add(ContainerDraft(type: .serial, title: "The Talons of Weng-Chiang"), inside: nil)

        // An alternative plays a sequence by id, so a named sequence has to exist first.
        await #expect(throws: LibraryError.noSuchSequence("parts")) {
            try await library.addAlternative(AlternativeDraft(title: "Broadcast version", sequence: "parts"), to: serial)
        }
        #expect(try await library.addSequence(SequenceDraft(id: "parts"), to: serial) == 0)
        #expect(try await library.addSequence(SequenceDraft(id: "omnibus", exploded: .allowed), to: serial) == 1)
        await #expect(throws: LibraryError.duplicateSlug("parts")) {
            try await library.addSequence(SequenceDraft(id: "parts"), to: serial)
        }
        await #expect(throws: LibraryError.invalidSlug("Not A Slug")) {
            try await library.addSequence(SequenceDraft(id: "Not A Slug"), to: serial)
        }
        await #expect(throws: LibraryError.noSuchSequence("3")) {
            try await library.addItem(ItemDraft(title: "Nowhere"), to: serial, in: .sequence(2))
        }

        let one = try await library.addItem(ItemDraft(title: "Part One", externalRefs: [ExternalRef(provider: .tvdb, value: " 1 ")]), to: serial, in: .sequence(0))
        let two = try await library.addItem(ItemDraft(title: "Part Two"), to: serial, in: .sequence(0))
        #expect(one == AddedItem(place: .sequence(0), index: 0, itemID: "part-one", container: nil))
        #expect(two.index == 1 && two.itemID == "part-two")
        try await library.addItem(ItemDraft(kind: .movie, title: "Omnibus"), to: serial, in: .sequence(1))
        try await library.addItem(ItemDraft(kind: .featurette, title: "Whose Doctor Who", outline: "Melvyn Bragg on why it works.\n", optional: true), to: serial, in: .extras)
        let documentaries = try await library.addItem(ItemDraft(kind: .container, container: ContainerDraft(type: .collection, title: "Documentaries")), to: serial, in: .extras)
        let documentariesID = try #require(documentaries.container)

        let broadcast = try await library.addAlternative(AlternativeDraft(title: "Broadcast version", sequence: "parts"), to: serial)
        let omnibus = try await library.addAlternative(AlternativeDraft(title: "Omnibus edition", sequence: "omnibus", outline: "The six parts edited into one feature-length film."), to: serial)
        #expect(broadcast == "broadcast-version" && omnibus == "omnibus-edition")
        #expect(try await library.addFeature(FeatureDraft(title: "Cast commentary", participantNames: "Louise Jameson, Philip Hinchcliffe\n"), to: serial) == "cast-commentary")
        #expect(try await library.addFeature(FeatureDraft(type: .isolatedMusic), to: serial) == "isolatedmusic")

        var written = try #require(try await repository.container(serial))
        #expect(written.sequences.map(\.id) == ["parts", "omnibus"])
        #expect(written.sequences[1].exploded == .allowed)
        #expect(written.sequences[0].items.map(\.title) == ["Part One", "Part Two"])
        #expect(written.sequences[0].items[0].externalRefs == [ExternalRef(provider: .tvdb, value: "1")])
        #expect(written.sequences[1].items.map(\.type) == [.movie])
        #expect(written.extras.map(\.id) == ["whose-doctor-who", "documentaries"])
        #expect(written.extras[0].optional && written.extras[0].outline == "Melvyn Bragg on why it works.")
        #expect(written.childContainerIDs == [documentariesID])
        #expect(try await repository.container(documentariesID)?.type == .collection)
        #expect(written.alternatives.map(\.id) == [broadcast, omnibus])
        #expect(written.defaultAlternative == broadcast)
        #expect(written.alternatives[1].outline == "The six parts edited into one feature-length film.")
        #expect(written.features.map(\.id) == ["cast-commentary", "isolatedmusic"])
        #expect(written.features[0].participants.map(\.name) == ["Louise Jameson", "Philip Hinchcliffe"])
        #expect(library.tree[0].children?.map(\.id) == [documentariesID])

        // A drag in the outline: the moved list is re-ordered and nothing else changes, including
        // which alternative plays by default.
        try await library.move(.items(.sequence(0)), in: serial, from: [1], to: 0)
        try await library.move(.sequences, in: serial, from: [1], to: 0)
        try await library.move(.alternatives, in: serial, from: [1], to: 0)
        try await library.move(.features, in: serial, from: [0], to: 2)
        try await library.move(.items(.extras), in: serial, from: [1], to: 0)
        written = try #require(try await repository.container(serial))
        #expect(written.sequences.map(\.id) == ["omnibus", "parts"])
        #expect(written.sequences[1].items.map(\.title) == ["Part Two", "Part One"])
        #expect(written.alternatives.map(\.id) == [omnibus, broadcast])
        #expect(written.defaultAlternative == broadcast)
        #expect(written.features.map(\.id) == ["isolatedmusic", "cast-commentary"])
        #expect(written.extras.map(\.id) == ["documentaries", "whose-doctor-who"])
    }

    /// An edited container is tidied and checked before it is written, and nothing is written
    /// when the check fails.
    @Test @MainActor func editsAreCheckedThenSaved() async throws {
        let (library, repository, _) = makeLibrary()
        await library.reload()
        let series = try await library.add(ContainerDraft(type: .series, title: "Doctor Who", year: "1963", yearInTitle: true), inside: nil)
        try await library.addSequence(SequenceDraft(id: "parts"), to: series)
        try await library.addAlternative(AlternativeDraft(title: "Broadcast", sequence: "parts"), to: series)
        try await library.addFeature(FeatureDraft(title: "Commentary", participantNames: "Louise Jameson"), to: series)
        try await library.addItem(ItemDraft(title: "Part One"), to: series, in: .sequence(0))

        var edited = try #require(library.containers[series])
        edited.title = "  Doctor Who "
        edited.typeLabel = " "
        edited.externalRefs = [ExternalRef(provider: .tvdb, value: " 76107 "), ExternalRef(provider: .imdb, value: "  ")]
        edited.features[0].participants = [Participant(name: " Louise Jameson ", role: " "), Participant(name: "  ")]
        edited.sequences[0].items[0].externalRefs = [ExternalRef(provider: .tvdb, value: "")]
        edited.type = .collection
        try await library.save(edited)
        let written = try #require(try await repository.container(series))
        #expect(written.title == "Doctor Who" && written.typeLabel == nil)
        #expect(written.year == nil && !written.yearInTitle, "a collection has no year")
        #expect(written.externalRefs == [ExternalRef(provider: .tvdb, value: "76107")])
        #expect(written.features[0].participants == [Participant(name: "Louise Jameson")])
        #expect(written.sequences[0].items[0].externalRefs == [])

        // Refused, and not written.
        edited = written
        edited.title = " "
        await #expect(throws: LibraryError.emptyTitle) { try await library.save(edited) }
        edited = written
        edited.sequences[0].id = "episodes"
        await #expect(throws: LibraryError.noSuchSequence("parts")) { try await library.save(edited) }
        edited = written
        edited.sequences.append(Sequence(id: "parts"))
        await #expect(throws: LibraryError.duplicateSlug("parts")) { try await library.save(edited) }
        edited = written
        edited.defaultAlternative = "omnibus"
        await #expect(throws: LibraryError.noSuchAlternative("omnibus")) { try await library.save(edited) }
        edited = written
        edited.extrasAnchor = "part-two"
        await #expect(throws: LibraryError.noSuchItem("part-two")) { try await library.save(edited) }
        edited = written
        edited.features[0].type = FeatureType(rawValue: "Not A Slug")
        await #expect(throws: LibraryError.invalidSlug("Not A Slug")) { try await library.save(edited) }
        #expect(try await repository.container(series) == written)
    }

    @Test @MainActor func cyclesAreCutAndUnreadableFoldersAreReported() async throws {
        let (library, repository, _) = makeLibrary()
        var a = Container(type: .series, title: "A")
        var b = Container(type: .season, title: "B")
        a.sequences = [Sequence(items: [.child(b, id: "b")])]
        b.sequences = [Sequence(items: [.child(a, id: "a")])]
        try await repository.save(a)
        try await repository.save(b)
        await library.reload()
        // Each holds the other, so neither is a root; nothing to draw, and nothing to loop over.
        #expect(library.roots.isEmpty)
        #expect(library.tree.isEmpty)

        try Data("<container/>".utf8).write(to: repository.containersURL.appendingPathComponent("stray.xml"))
        await library.reload()
        #expect(library.loadError?.contains("stray.xml") == true)
        #expect(library.roots.isEmpty)
    }
}
