// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import AppKit
import SmdKit
import SwiftUI

/// The selected row's facts, editable. One draft of the whole container, because an alternative,
/// a feature, a sequence and an item are all parts of its file; the fields shown are the selected
/// part's. Nothing is written until Save, and what Save refuses is said beneath the fields. Ids
/// are shown and not edited: other files name items by them, and the default alternative and the
/// extras anchor name their targets by them.
@MainActor
struct ContainerEditor: View {
    @Environment(ContainerLibrary.self) private var library
    let container: Container
    let row: OutlineRow

    @State private var draft: Container
    /// The year as typed, so a half-typed one is not a number yet rather than not there.
    @State private var year: String
    /// A sequence's id as typed; applied at save, renaming it in the alternatives that play it.
    @State private var sequenceID: String
    @State private var saving = false
    @State private var failure: String?

    init(container: Container, row: OutlineRow) {
        self.container = container
        self.row = row
        _draft = State(initialValue: container)
        _year = State(initialValue: container.year.map(String.init) ?? "")
        var sequenceID = ""
        if case .sequence(_, let index) = row, container.sequences.indices.contains(index) {
            sequenceID = container.sequences[index].id ?? ""
        }
        _sequenceID = State(initialValue: sequenceID)
    }

    /// The draft with the typed year and sequence id applied: what Save writes.
    private var edited: Container {
        var edited = draft
        edited.year = edited.type.hasYear ? Int(year.trimmingCharacters(in: .whitespaces)) : nil
        if case .sequence(_, let index) = row, edited.sequences.indices.contains(index) {
            let old = edited.sequences[index].id
            let new = sequenceID.trimmingCharacters(in: .whitespaces).nonEmpty
            edited.sequences[index].id = new
            if let old, let new, old != new {
                for alternative in edited.alternatives.indices where edited.alternatives[alternative].sequence == old {
                    edited.alternatives[alternative].sequence = new
                }
            }
        }
        return edited
    }

    private var dirty: Bool {
        edited != container
    }

    private var yearIsValid: Bool {
        !draft.type.hasYear || year.trimmingCharacters(in: .whitespaces).isEmpty || Int(year.trimmingCharacters(in: .whitespaces)) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                fields
                if let failure {
                    Text(failure)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                if dirty {
                    Text("Edited")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Revert") { reset(to: container) }
                    .disabled(!dirty)
                Button("Save") { save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!dirty || saving || !yearIsValid)
            }
            .padding()
        }
        // The folder is re-read whenever the app comes to the front. A change under an untouched
        // editor is shown; one under an edited draft is not, since the edits are the user's.
        .onChange(of: container) { old, new in
            if edited == old { reset(to: new) }
        }
    }

    // MARK: Fields

    @ViewBuilder
    private var fields: some View {
        switch row {
        case .container, .group:
            containerFields
        case .alternative(_, let id):
            if let index = draft.alternatives.firstIndex(where: { $0.id == id }) {
                alternativeFields(index)
            } else {
                gone
            }
        case .feature(_, let id):
            if let index = draft.features.firstIndex(where: { $0.id == id }) {
                featureFields(index)
            } else {
                gone
            }
        case .sequence(_, let index):
            if draft.sequences.indices.contains(index) {
                sequenceFields(index)
            } else {
                gone
            }
        case .entry(_, let place, let index):
            if draft[place].indices.contains(index) {
                entryFields(place, index)
            } else {
                gone
            }
        }
    }

    private var gone: some View {
        Text("No longer there: the repository changed under the selection.")
            .foregroundStyle(.secondary)
    }

    private var containerFields: some View {
        Group {
            Section {
                TextField("Title", text: $draft.title)
                if draft.type.hasYear {
                    YearFields(year: $year, inTitle: $draft.yearInTitle)
                }
                Picker("Type", selection: $draft.type) {
                    ForEach(ContainerType.allCases, id: \.self) { type in
                        Text(type.title).tag(type)
                    }
                }
                LabeledContent {
                    TextField("", text: optional($draft.typeLabel), prompt: Text("Optional"))
                        .labelsHidden()
                } label: {
                    HStack(spacing: 4) {
                        Text("Type label")
                        HelpButton("The word this show uses for a \(draft.type.title.lowercased()), shown in place of it: Doctor Who calls a serial a Story, an anime release calls one a Volume, a British season is a Series. Leave it empty to show the type's own name.")
                    }
                }
                OutlineField(text: optional($draft.outline))
                Toggle(isOn: $draft.listed) {
                    HStack(spacing: 4) {
                        Text("Listed")
                        HelpButton("Off for a companion programme nobody browses to from the top of a library: reachable through a relation or a ref, and nowhere else.")
                    }
                }
                if !draft.alternatives.isEmpty {
                    Picker("Plays by default", selection: $draft.defaultAlternative) {
                        Text("Not set").tag(String?.none)
                        ForEach(draft.alternatives) { alternative in
                            Text(alternative.title ?? alternative.id).tag(String?.some(alternative.id))
                        }
                    }
                }
                if !draft.extras.isEmpty {
                    Picker(selection: $draft.extrasAnchor) {
                        Text("Nowhere").tag(String?.none)
                        ForEach(draft.sequences.flatMap(\.items).compactMap(\.id), id: \.self) { id in
                            Text(id).tag(String?.some(id))
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Extras anchored at")
                            HelpButton("The item the extras belong after, when they belong after one: a documentary about part four is anchored at part four.")
                        }
                    }
                }
                LabeledContent("Id") {
                    Text(draft.id.rawValue)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
                if let repository = library.repository {
                    LabeledContent("File") {
                        HStack {
                            Text(repository.fileURL(for: draft.id).lastPathComponent)
                                .truncationMode(.middle)
                                .lineLimit(1)
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([repository.fileURL(for: draft.id)])
                            }
                            .controlSize(.small)
                        }
                    }
                }
            } header: {
                heading(edited.displayTitle)
            }
            Section("External references") {
                ExternalRefsEditor(refs: $draft.externalRefs)
            }
        }
    }

    private func alternativeFields(_ index: Int) -> some View {
        let alternative = $draft.alternatives[index]
        let id = alternative.wrappedValue.id
        return Section {
            TextField("Title", text: optional(alternative.title), prompt: Text("Optional"))
            Picker("Plays", selection: alternative.sequence) {
                ForEach(draft.sequences.compactMap(\.id), id: \.self) { sequence in
                    Text(sequence).tag(sequence)
                }
            }
            OutlineField(text: optional(alternative.outline))
            Toggle("Play by default", isOn: Binding(
                get: { draft.defaultAlternative == id },
                set: { on in
                    if on { draft.defaultAlternative = id } else if draft.defaultAlternative == id { draft.defaultAlternative = nil }
                }
            ))
            LabeledContent("Id") {
                Text(id)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
        } header: {
            heading(alternative.wrappedValue.title ?? id)
        }
    }

    private func featureFields(_ index: Int) -> some View {
        let feature = $draft.features[index]
        return Group {
            Section {
                FeatureTypeField(type: feature.type)
                TextField("Title", text: optional(feature.title), prompt: Text("Optional"))
                LabeledContent("Id") {
                    Text(feature.wrappedValue.id)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
            } header: {
                heading(feature.wrappedValue.title ?? feature.wrappedValue.id)
            }
            Section("Participants") {
                if feature.wrappedValue.participants.isEmpty {
                    Text("None")
                        .foregroundStyle(.secondary)
                }
                ForEach(feature.wrappedValue.participants.indices, id: \.self) { participant in
                    let binding = self.participant(feature, participant)
                    HStack {
                        TextField("Name", text: binding.name, prompt: Text("Name"))
                            .labelsHidden()
                        TextField("Role", text: optional(binding.role), prompt: Text("Role, optional"))
                            .labelsHidden()
                        Button {
                            if feature.wrappedValue.participants.indices.contains(participant) {
                                feature.wrappedValue.participants.remove(at: participant)
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this participant")
                    }
                }
                Button {
                    feature.wrappedValue.participants.append(Participant(name: ""))
                } label: {
                    Label("Add participant", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func sequenceFields(_ index: Int) -> some View {
        let sequence = $draft.sequences[index]
        let playedBy = draft.alternatives.filter { $0.sequence == sequence.wrappedValue.id }
        return Section {
            LabeledContent {
                TextField("", text: $sequenceID, prompt: Text("Optional"))
                    .labelsHidden()
            } label: {
                HStack(spacing: 4) {
                    Text("Id")
                    HelpButton("A container with one order of things has one sequence, and it need not be named. Name them when there are two or more, because an alternative plays a sequence by its id. Renaming one renames it in the alternatives that play it.")
                }
            }
            Picker(selection: sequence.exploded) {
                ForEach(Exploded.allCases, id: \.self) { value in
                    Text(value.rawValue.capitalized).tag(value)
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Exploded")
                    HelpButton("Whether a client may show this sequence's items as if they were the parent's own: never, or allowed, or preferred.")
                }
            }
            LabeledContent("Items", value: "\(sequence.wrappedValue.items.count)")
            LabeledContent("Played by") {
                Text(playedBy.isEmpty ? "No alternative" : playedBy.map { $0.title ?? $0.id }.joined(separator: ", "))
                    .foregroundStyle(playedBy.isEmpty ? .secondary : .primary)
            }
        } header: {
            heading(sequence.wrappedValue.id ?? "Sequence \(index + 1)")
        }
    }

    @ViewBuilder
    private func entryFields(_ place: EntryPlace, _ index: Int) -> some View {
        let entry = self.entry(place, index)
        let value = entry.wrappedValue
        if let ref = value.ref {
            Section {
                LabeledContent("Ref") {
                    Text(ref.container.map { id in "\(library.containers[id]?.displayTitle ?? id.rawValue) › \(ref.item)" } ?? ref.item)
                }
                Text("A ref names an item declared elsewhere; edit that item.")
                    .foregroundStyle(.secondary)
            } header: {
                heading(ref.item)
            }
        } else if let child = value.container {
            Section {
                LabeledContent("Container") {
                    Text(library.containers[child]?.displayTitle ?? "Missing container \(child)")
                        .foregroundStyle(library.containers[child] == nil ? .red : .primary)
                }
                LabeledContent("Id") {
                    Text(value.id ?? "")
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
                Toggle("Optional", isOn: entry.optional)
            } header: {
                heading(library.containers[child]?.displayTitle ?? value.id ?? "")
            }
        } else {
            Section {
                TextField("Title", text: optional(entry.title), prompt: Text("Optional when a provider has one"))
                Picker("Type", selection: Binding(get: { value.type ?? .episode }, set: { entry.wrappedValue.type = $0 })) {
                    Text("Episode").tag(EntryType.episode)
                    Text("Movie").tag(EntryType.movie)
                    Text("Featurette").tag(EntryType.featurette)
                    if let type = value.type, ![.episode, .movie, .featurette].contains(type) {
                        Text(type.rawValue).tag(type)
                    }
                }
                OutlineField(text: optional(entry.outline))
                Toggle(isOn: entry.optional) {
                    HStack(spacing: 4) {
                        Text("Optional")
                        HelpButton("A client may leave this out and still have shown the whole thing: a recap, a cold open cut from a repeat, a title card.")
                    }
                }
                LabeledContent("Id") {
                    Text(value.id ?? "")
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
            } header: {
                heading(value.title ?? value.id ?? "")
            }
            Section("External references") {
                ExternalRefsEditor(refs: entry.externalRefs)
            }
        }
    }

    // MARK: Bindings

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.title2)
            .fontWeight(.semibold)
    }

    /// An optional string as a field: empty is nil, so clearing a field removes the element.
    private func optional(_ binding: Binding<String?>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue ?? "" },
            set: { binding.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }

    /// An item's binding, guarded through the container's place subscript: an index the container
    /// no longer has reads as an empty entry and writes nowhere.
    private func entry(_ place: EntryPlace, _ index: Int) -> Binding<Entry> {
        Binding(
            get: { draft[place].indices.contains(index) ? draft[place][index] : Entry(id: "", type: .episode) },
            set: { if draft[place].indices.contains(index) { draft[place][index] = $0 } }
        )
    }

    private func participant(_ feature: Binding<Feature>, _ index: Int) -> Binding<Participant> {
        Binding(
            get: { feature.wrappedValue.participants.indices.contains(index) ? feature.wrappedValue.participants[index] : Participant(name: "") },
            set: { if feature.wrappedValue.participants.indices.contains(index) { feature.wrappedValue.participants[index] = $0 } }
        )
    }

    // MARK: Saving

    private func reset(to container: Container) {
        draft = container
        year = container.year.map(String.init) ?? ""
        if case .sequence(_, let index) = row, container.sequences.indices.contains(index) {
            sequenceID = container.sequences[index].id ?? ""
        }
        failure = nil
    }

    private func save() {
        saving = true
        failure = nil
        Task {
            do {
                try await library.save(edited)
                if let fresh = library.containers[container.id] { reset(to: fresh) }
            } catch {
                failure = error.localizedDescription
            }
            saving = false
        }
    }
}
