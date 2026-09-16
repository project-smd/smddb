// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import Foundation
import Testing
@testable import SmdKit

/// The container file and the folder behind it, checked against the worked example in the
/// proposals: Talons as a serial with three cuts, a commentary, a ref and an extra.
struct SmdKitTests {
    static let talons = Container(
        id: ContainerID("6a1f0c2e9b7d4e3a")!,
        type: .serial,
        typeLabel: "Story",
        title: "The Talons of Weng-Chiang",
        outline: "Fog-bound Victorian London, a stage magician, and a war criminal from the fifty-first century.",
        externalRefs: [ExternalRef(provider: .wikidata, value: "Q3475469")],
        defaultAlternative: "broadcast",
        alternatives: [
            Alternative(id: "broadcast", sequence: "parts", title: "Broadcast version"),
            Alternative(id: "se", sequence: "parts", title: "Updated special effects", outline: "2010 DVD release."),
            Alternative(id: "omnibus", sequence: "omnibus", title: "Omnibus edition"),
        ],
        features: [
            Feature(id: "commentary1", type: .commentary, title: "Commentary — Louise Jameson, John Bennett, Christopher Barry", participants: [
                Participant(name: "Louise Jameson", role: "Leela"),
                Participant(name: "Christopher Barry", role: "Director"),
            ]),
            Feature(id: "music1", type: .isolatedMusic),
        ],
        sequences: [
            Sequence(id: "parts", items: [
                Entry(id: "prequel", type: .episode, optional: true),
                Entry(id: "part1", type: .episode, externalRefs: [ExternalRef(provider: .tvdb, value: "1234"), ExternalRef(provider: .tmdb, value: "5678")]),
                Entry(id: "part2", type: .episode, externalRefs: [ExternalRef(provider: .tvdb, value: "1235")]),
            ]),
            Sequence(id: "omnibus", items: [
                Entry(id: "omnibus-feature", type: .episode, title: "Omnibus edition"),
            ]),
            Sequence(id: "dvd-order", exploded: .allowed, items: [
                Entry(ref: EntryRef(item: "part2")),
                Entry(ref: EntryRef(item: "part1")),
            ]),
        ],
        extrasAnchor: "part1",
        extras: [
            Entry(id: "now-and-then", type: .featurette, title: "Now and Then"),
            Entry(ref: EntryRef(container: ContainerID("0b9e8d7c6f5a4b3c")!, item: "s14-talons")),
        ]
    )

    @Test func containerSurvivesTheFile() throws {
        let data = ContainerFile.data(for: Self.talons)
        let text = String(decoding: data, as: UTF8.self)
        // Spelled as the sidecar spells it, with the database's differences and nothing else.
        #expect(text.contains(#"<container format="1" id="6a1f0c2e9b7d4e3a" type="serial">"#))
        #expect(text.contains(#"<externalRef provider="wikidata" value="Q3475469"/>"#))
        #expect(text.contains(#"<alternatives default="broadcast">"#))
        #expect(text.contains(#"<item ref="0b9e8d7c6f5a4b3c#s14-talons""#))
        #expect(text.contains(#"<sequence id="dvd-order" exploded="allowed">"#))
        #expect(!text.contains("presentation"))
        #expect(!text.contains("listed"), "the default is not written")
        #expect(try ContainerFile.container(from: data, expecting: Self.talons.id) == Self.talons)
    }

    @Test func childrenAreNamedByIdentity() throws {
        let child = Container(type: .season, title: "Season 14", year: 1976)
        var series = Container(type: .series, title: "Doctor Who", year: 1963, yearInTitle: true, listed: false)
        series.sequences = [Sequence(items: [.child(child, id: "season-14")])]
        let data = ContainerFile.data(for: series)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#"listed="false""#))
        #expect(text.contains(#"<year inTitle="true">1963</year>"#))
        #expect(series.displayTitle == "Doctor Who (1963)")
        #expect(child.displayTitle == "Season 14")
        #expect(String(decoding: ContainerFile.data(for: child), as: UTF8.self).contains("<year>1976</year>"))
        #expect(text.contains(#"<item type="container" id="season-14" container="\#(child.id)""#))
        let read = try ContainerFile.container(from: data)
        #expect(read == series)
        #expect(read.childContainerIDs == [child.id])
    }

    @Test func fileRefusesWhatItCannotRead() throws {
        func read(_ xml: String, expecting: ContainerID? = nil) throws -> Container {
            try ContainerFile.container(from: Data(xml.utf8), expecting: expecting)
        }
        let id = ContainerID.mint()
        let other = ContainerID.mint()
        #expect(throws: ContainerFileError.notAContainer) {
            try read(#"<sequence id="x"/>"#)
        }
        #expect(throws: ContainerFileError.unsupportedFormat(2)) {
            try read(#"<container format="2" id="\#(id)" type="series"><title>x</title></container>"#)
        }
        #expect(throws: ContainerFileError.idMismatch(file: other, document: id)) {
            try read(#"<container format="1" id="\#(id)" type="series"><title>x</title></container>"#, expecting: other)
        }
        #expect(throws: ContainerFileError.missingElement(element: "container", child: "title")) {
            try read(#"<container format="1" id="\#(id)" type="series"/>"#)
        }
        #expect(throws: ContainerFileError.invalidValue(element: "container", attribute: "type", value: "box")) {
            try read(#"<container format="1" id="\#(id)" type="box"><title>x</title></container>"#)
        }
        #expect(throws: ContainerFileError.missingAttribute(element: "item", attribute: "container")) {
            try read(#"<container format="1" id="\#(id)" type="series"><title>x</title><sequence><item type="container" id="s1"/></sequence></container>"#)
        }
        #expect(throws: ContainerFileError.refWithIdentity("part1")) {
            try read(#"<container format="1" id="\#(id)" type="series"><title>x</title><sequence><item ref="part1" id="p"/></sequence></container>"#)
        }
        #expect(throws: ContainerFileError.self) {
            try read("<container format=\"1\" id=\"\(id)\" type=\"series\"><title>x</title>")
        }
    }

    @Test func repositoryKeepsOneFilePerContainer() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SmdKitTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = LocalRepository(root: folder)
        // An empty folder, or none, is an empty database and not an error.
        #expect(try await repository.containers().isEmpty)
        #expect(try await repository.container(Self.talons.id) == nil)

        let season = Container(type: .season, title: "Season 14", externalRefs: [ExternalRef(provider: .tvdb, value: "76107/14")])
        var series = Container(type: .series, title: "Doctor Who (1963)", externalRefs: [ExternalRef(provider: .tvdb, value: "76107")])
        series.sequences = [Sequence(items: [.child(season, id: "season-14")])]
        try await repository.save(series)
        try await repository.save(season)
        try await repository.save(Self.talons)

        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("containers/\(series.id).xml").path))
        #expect(try await repository.containers().count == 3)
        #expect(try await repository.container(Self.talons.id) == Self.talons)
        #expect(try await repository.containers(matching: ExternalRef(provider: .tvdb, value: "76107")) == [series])
        #expect(try await repository.containers(matching: ExternalRef(provider: .tvdb, value: "1")).isEmpty)
        // Roots are what nothing holds: the season is inside the series, Talons is loose.
        #expect(Set(try await repository.roots().map(\.id)) == [series.id, Self.talons.id])

        // Saving again replaces, and a stray file is refused with its name rather than skipped.
        series.title = "Doctor Who"
        try await repository.save(series)
        #expect(try await repository.container(series.id)?.title == "Doctor Who")
        try Data("<container/>".utf8).write(to: folder.appendingPathComponent("containers/notes.xml"))
        await #expect(throws: LocalRepositoryError.self) {
            try await repository.containers()
        }
    }

    @Test func slugsAreMadeFromTitles() {
        #expect(Slug.make(from: "The Talons of Weng-Chiang") == "the-talons-of-weng-chiang")
        #expect(Slug.make(from: "  Pyramids of Mars: Part 1 (1975) ") == "pyramids-of-mars-part-1-1975")
        #expect(Slug.make(from: "Café Ünïcode") == "cafe-unicode")
        #expect(Slug.make(from: "???") == "item")
        #expect(Slug.unique(from: "Part 1", avoiding: ["part-1", "part-1-2"]) == "part-1-3")
        #expect(Slug.isValid("season-14"))
        #expect(!Slug.isValid("-season"))
        #expect(!Slug.isValid("Season 14"))
    }
}
