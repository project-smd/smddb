// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A container as the data repository keeps it: one XML document, rooted at `<container>`, with
/// the shape of the sidecar's element and none of a library's own facts in it.
///
/// Read against an `.smd` the differences are exactly the ones `ContainerDatabase.md` lists:
/// the id is the database's, not a path-relative slug; a child is `container="<id>"` where the
/// sidecar has `smd="<path>"`; `<externalRef provider="…" value="…"/>` stands where the sidecar
/// has an `nfo` pointer; and there are no `<presentation>` elements, because which file holds a
/// thing is a library's fact, not the database's. Everything else — titles, alternatives,
/// features, sequences, items, refs, extras — is spelled as the sidecar spells it, so the `.smd`
/// writer is a projection and not a translation.
///
/// The id is both the file's name and its root attribute. That is the format's usual trade —
/// duplicate for legibility, verify mechanically — and the reader refuses a file whose two
/// disagree.
public enum ContainerFile {
    /// The format this reads and writes. A file with a higher number is refused rather than
    /// half-read.
    public static let format = 1

    public static let fileExtension = "xml"

    public static func fileName(for id: ContainerID) -> String {
        "\(id.rawValue).\(fileExtension)"
    }

    // MARK: - Writing

    public static func data(for container: Container) -> Data {
        let root = XMLElement(name: "container")
        root.set("format", String(format))
        root.set("id", container.id.rawValue)
        root.set("type", container.type.rawValue)
        if !container.listed { root.set("listed", "false") }
        root.addText("title", container.title)
        if let year = container.year {
            let element = XMLElement(name: "year", stringValue: String(year))
            if container.yearInTitle { element.set("inTitle", "true") }
            root.addChild(element)
        }
        root.addText("typeLabel", container.typeLabel)
        root.addText("outline", container.outline)
        root.addExternalRefs(container.externalRefs)

        if !container.alternatives.isEmpty {
            let alternatives = XMLElement(name: "alternatives")
            alternatives.set("default", container.defaultAlternative)
            for alternative in container.alternatives {
                let element = XMLElement(name: "alternative")
                element.set("id", alternative.id)
                element.set("sequence", alternative.sequence)
                element.addText("title", alternative.title)
                element.addText("outline", alternative.outline)
                alternatives.addChild(element)
            }
            root.addChild(alternatives)
        }

        if !container.features.isEmpty {
            let features = XMLElement(name: "features")
            for feature in container.features {
                let element = XMLElement(name: "feature")
                element.set("id", feature.id)
                element.set("type", feature.type.rawValue)
                element.addText("title", feature.title)
                for participant in feature.participants {
                    let child = XMLElement(name: "participant")
                    child.set("name", participant.name)
                    child.set("role", participant.role)
                    element.addChild(child)
                }
                features.addChild(element)
            }
            root.addChild(features)
        }

        for sequence in container.sequences {
            let element = XMLElement(name: "sequence")
            element.set("id", sequence.id)
            if sequence.exploded != .never { element.set("exploded", sequence.exploded.rawValue) }
            for item in sequence.items { element.addChild(itemElement(item)) }
            root.addChild(element)
        }

        if !container.extras.isEmpty || container.extrasAnchor != nil {
            let element = XMLElement(name: "extras")
            element.set("anchor", container.extrasAnchor)
            for item in container.extras { element.addChild(itemElement(item)) }
            root.addChild(element)
        }

        let document = XMLDocument(rootElement: root)
        document.version = "1.0"
        document.characterEncoding = "UTF-8"
        var data = document.xmlData(options: [.nodePrettyPrint, .nodeCompactEmptyElement])
        if data.last != UInt8(ascii: "\n") { data.append(UInt8(ascii: "\n")) }
        return data
    }

    private static func itemElement(_ item: Entry) -> XMLElement {
        let element = XMLElement(name: "item")
        if let ref = item.ref {
            element.set("ref", ref.container.map { "\($0.rawValue)#\(ref.item)" } ?? ref.item)
            return element
        }
        element.set("type", item.type?.rawValue)
        element.set("id", item.id)
        if item.optional { element.set("optional", "true") }
        element.set("container", item.container?.rawValue)
        element.addText("title", item.title)
        element.addText("outline", item.outline)
        element.addExternalRefs(item.externalRefs)
        return element
    }

    // MARK: - Reading

    /// Reads a container document. `expecting` is the id the file's name carries, when it has one;
    /// a document whose root disagrees with it is refused.
    public static func container(from data: Data, expecting expected: ContainerID? = nil) throws -> Container {
        // Well-formedness first, through the event parser. The document parser on Linux is
        // libxml2 in recovery mode: a truncated file comes back as a document with the tags
        // closed for it, which is not what was written and must not be read as if it were. The
        // event parser notices on both platforms, but reports it differently — a false return
        // on Darwin, a true return with `parserError` set on Linux — so both are checked.
        let parser = XMLParser(data: data)
        let parsed = parser.parse()
        if let error = parser.parserError {
            throw ContainerFileError.malformed(error.localizedDescription)
        }
        guard parsed else { throw ContainerFileError.malformed("not well-formed XML") }
        let document: XMLDocument
        do {
            document = try XMLDocument(data: data, options: [])
        } catch {
            throw ContainerFileError.malformed(error.localizedDescription)
        }
        guard let root = document.rootElement(), root.name == "container" else {
            throw ContainerFileError.notAContainer
        }
        let format = try root.integer("format")
        guard format <= Self.format else { throw ContainerFileError.unsupportedFormat(format) }
        guard let id = ContainerID(try root.required("id")) else {
            throw ContainerFileError.invalidValue(element: "container", attribute: "id", value: try root.required("id"))
        }
        if let expected, expected != id {
            throw ContainerFileError.idMismatch(file: expected, document: id)
        }
        let typeValue = try root.required("type")
        guard let type = ContainerType(rawValue: typeValue) else {
            throw ContainerFileError.invalidValue(element: "container", attribute: "type", value: typeValue)
        }

        var container = Container(
            id: id,
            type: type,
            typeLabel: root.text("typeLabel"),
            title: try root.requiredText("title"),
            outline: root.text("outline"),
            listed: try root.bool("listed") ?? true,
            externalRefs: try root.externalRefs()
        )
        if let yearElement = root.child("year") {
            let text = yearElement.stringValue ?? ""
            guard let year = Int(text) else {
                throw ContainerFileError.invalidText(element: "year", value: text)
            }
            container.year = year
            container.yearInTitle = try yearElement.bool("inTitle") ?? false
        }

        if let alternatives = root.child("alternatives") {
            container.defaultAlternative = alternatives.attribute("default")
            container.alternatives = try alternatives.elements(forName: "alternative").map { element in
                Alternative(
                    id: try element.required("id"),
                    sequence: try element.required("sequence"),
                    title: element.text("title"),
                    outline: element.text("outline")
                )
            }
        }

        if let features = root.child("features") {
            container.features = try features.elements(forName: "feature").map { element in
                Feature(
                    id: try element.required("id"),
                    type: FeatureType(rawValue: try element.required("type")),
                    title: element.text("title"),
                    participants: try element.elements(forName: "participant").map {
                        Participant(name: try $0.required("name"), role: $0.attribute("role"))
                    }
                )
            }
        }

        container.sequences = try root.elements(forName: "sequence").map { element in
            var sequence = Sequence(id: element.attribute("id"))
            if let exploded = element.attribute("exploded") {
                guard let value = Exploded(rawValue: exploded) else {
                    throw ContainerFileError.invalidValue(element: "sequence", attribute: "exploded", value: exploded)
                }
                sequence.exploded = value
            }
            sequence.items = try element.elements(forName: "item").map(item)
            return sequence
        }

        if let extras = root.child("extras") {
            container.extrasAnchor = extras.attribute("anchor")
            container.extras = try extras.elements(forName: "item").map(item)
        }

        return container
    }

    private static func item(_ element: XMLElement) throws -> Entry {
        if let ref = element.attribute("ref") {
            guard element.attribute("id") == nil, element.attribute("type") == nil else {
                throw ContainerFileError.refWithIdentity(ref)
            }
            let parts = ref.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                guard let container = ContainerID(String(parts[0])), !parts[1].isEmpty else {
                    throw ContainerFileError.invalidValue(element: "item", attribute: "ref", value: ref)
                }
                return Entry(ref: EntryRef(container: container, item: String(parts[1])))
            }
            guard !ref.isEmpty else {
                throw ContainerFileError.invalidValue(element: "item", attribute: "ref", value: ref)
            }
            return Entry(ref: EntryRef(item: ref))
        }
        let type = EntryType(rawValue: try element.required("type"))
        var entry = Entry(
            id: try element.required("id"),
            type: type,
            optional: try element.bool("optional") ?? false,
            title: element.text("title"),
            outline: element.text("outline"),
            externalRefs: try element.externalRefs()
        )
        if let child = element.attribute("container") {
            guard type == .container, let id = ContainerID(child) else {
                throw ContainerFileError.invalidValue(element: "item", attribute: "container", value: child)
            }
            entry.container = id
        } else if type == .container {
            throw ContainerFileError.missingAttribute(element: "item", attribute: "container")
        }
        return entry
    }
}

public enum ContainerFileError: Error, Equatable, LocalizedError {
    case malformed(String)
    case notAContainer
    case unsupportedFormat(Int)
    case missingAttribute(element: String, attribute: String)
    case missingElement(element: String, child: String)
    case invalidValue(element: String, attribute: String, value: String)
    case invalidText(element: String, value: String)
    case idMismatch(file: ContainerID, document: ContainerID)
    case refWithIdentity(String)

    public var errorDescription: String? {
        switch self {
        case .malformed(let detail): "Not well-formed XML: \(detail)"
        case .notAContainer: "The document is not rooted at <container>"
        case .unsupportedFormat(let format): "Container format \(format) is newer than this reader (format \(ContainerFile.format))"
        case .missingAttribute(let element, let attribute): "<\(element)> has no \(attribute) attribute"
        case .missingElement(let element, let child): "<\(element)> has no <\(child)>"
        case .invalidValue(let element, let attribute, let value): "<\(element) \(attribute)=\"\(value)\"> is not a valid \(attribute)"
        case .invalidText(let element, let value): "<\(element)>\(value)</\(element)> is not a valid \(element)"
        case .idMismatch(let file, let document): "The file is named \(file) but its <container> says \(document)"
        case .refWithIdentity(let ref): "<item ref=\"\(ref)\"> also carries an id or a type; a ref has neither"
        }
    }
}

// MARK: - XML helpers

private extension XMLElement {
    func set(_ name: String, _ value: String?) {
        guard let value else { return }
        addAttribute(XMLNode.attribute(withName: name, stringValue: value) as! XMLNode)
    }

    func addText(_ name: String, _ value: String?) {
        guard let value, !value.isEmpty else { return }
        addChild(XMLElement(name: name, stringValue: value))
    }

    func addExternalRefs(_ refs: [ExternalRef]) {
        for ref in refs {
            let element = XMLElement(name: "externalRef")
            element.set("provider", ref.provider.rawValue)
            element.set("value", ref.value)
            addChild(element)
        }
    }

    func attribute(_ name: String) -> String? {
        attribute(forName: name)?.stringValue
    }

    func required(_ name: String) throws -> String {
        guard let value = attribute(name) else {
            throw ContainerFileError.missingAttribute(element: self.name ?? "?", attribute: name)
        }
        return value
    }

    func integer(_ name: String) throws -> Int {
        let value = try required(name)
        guard let integer = Int(value) else {
            throw ContainerFileError.invalidValue(element: self.name ?? "?", attribute: name, value: value)
        }
        return integer
    }

    func bool(_ name: String) throws -> Bool? {
        guard let value = attribute(name) else { return nil }
        switch value {
        case "true": return true
        case "false": return false
        default: throw ContainerFileError.invalidValue(element: self.name ?? "?", attribute: name, value: value)
        }
    }

    func child(_ name: String) -> XMLElement? {
        elements(forName: name).first
    }

    func text(_ name: String) -> String? {
        child(name)?.stringValue.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func requiredText(_ name: String) throws -> String {
        guard let value = text(name) else {
            throw ContainerFileError.missingElement(element: self.name ?? "?", child: name)
        }
        return value
    }

    func externalRefs() throws -> [ExternalRef] {
        try elements(forName: "externalRef").map {
            ExternalRef(provider: Provider(rawValue: try $0.required("provider")), value: try $0.required("value"))
        }
    }
}
