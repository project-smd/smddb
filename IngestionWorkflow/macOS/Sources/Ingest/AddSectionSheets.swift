// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import SmdKit
import SwiftUI

/// The sheets the outline's + buttons open, one per kind of thing a container holds. Each adds at
/// the end of its list and reports where, so the outline can open to it.

@MainActor
struct AddItemSheet: View {
    @Environment(ContainerLibrary.self) private var library
    let container: Container
    let place: EntryPlace
    let added: (AddedItem) -> Void

    @State private var draft: ItemDraft

    init(container: Container, place: EntryPlace, added: @escaping (AddedItem) -> Void) {
        self.container = container
        self.place = place
        self.added = added
        var draft = ItemDraft()
        // An extra is usually a featurette; anything in a sequence is usually the next level down,
        // which for a serial or a season is a child container. Both are first guesses.
        if place == .extras {
            draft.kind = .featurette
        } else if [.series, .season, .collection].contains(container.type) {
            draft.kind = .container
        }
        draft.container.type = ContainerDraft.usualChildType(of: container.type)
        self.draft = draft
    }

    var body: some View {
        AddSheet(title: "New item in \(container.title)", canAdd: draft.isComplete, height: 520) {
            added(try await library.addItem(draft, to: container.id, in: place))
        } content: {
            Picker("Kind", selection: $draft.kind) {
                ForEach(ItemDraft.Kind.allCases, id: \.self) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            if draft.kind == .container {
                ContainerFields(draft: $draft.container)
            } else {
                TextField("Title", text: $draft.title)
                OutlineField(text: $draft.outline)
                Toggle(isOn: $draft.optional) {
                    HStack(spacing: 4) {
                        Text("Optional")
                        HelpButton("A client may leave this out and still have shown the whole thing: a recap, a cold open cut from a repeat, a title card.")
                    }
                }
                Section("External references") {
                    ExternalRefsEditor(refs: $draft.externalRefs)
                }
            }
        }
    }
}

@MainActor
struct AddAlternativeSheet: View {
    @Environment(ContainerLibrary.self) private var library
    let container: Container
    let added: (String) -> Void

    @State private var draft: AlternativeDraft

    init(container: Container, added: @escaping (String) -> Void) {
        self.container = container
        self.added = added
        var draft = AlternativeDraft()
        draft.sequence = container.sequences.compactMap(\.id).first ?? ""
        draft.isDefault = container.alternatives.isEmpty
        _draft = State(initialValue: draft)
    }

    private var namedSequences: [String] {
        container.sequences.compactMap(\.id)
    }

    var body: some View {
        AddSheet(title: "New alternative of \(container.title)", canAdd: draft.isComplete && !namedSequences.isEmpty, height: 400) {
            added(try await library.addAlternative(draft, to: container.id))
        } content: {
            TextField("Title", text: $draft.title)
            if namedSequences.isEmpty {
                LabeledContent("Plays") {
                    Text("Name a sequence first: an alternative plays one by its id.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Picker("Plays", selection: $draft.sequence) {
                    ForEach(namedSequences, id: \.self) { id in
                        Text(id).tag(id)
                    }
                }
            }
            OutlineField(text: $draft.outline)
            Toggle("Play by default", isOn: $draft.isDefault)
                .disabled(container.alternatives.isEmpty)
        }
    }
}

@MainActor
struct AddFeatureSheet: View {
    @Environment(ContainerLibrary.self) private var library
    let container: Container
    let added: (String) -> Void

    @State private var draft = FeatureDraft()

    var body: some View {
        AddSheet(title: "New feature of \(container.title)", canAdd: Slug.isValid(draft.type.rawValue), height: 400) {
            added(try await library.addFeature(draft, to: container.id))
        } content: {
            FeatureTypeField(type: $draft.type)
            TextField("Title", text: $draft.title, prompt: Text("Optional"))
            LabeledContent {
                TextField("", text: $draft.participantNames, prompt: Text("Optional, comma-separated"), axis: .vertical)
                    .labelsHidden()
                    .lineLimit(1...3)
            } label: {
                HStack(spacing: 4) {
                    Text("Participants")
                    HelpButton("Who is on it, by name. Roles are added afterwards, from the outline.")
                }
            }
        }
    }
}

@MainActor
struct AddSequenceSheet: View {
    @Environment(ContainerLibrary.self) private var library
    let container: Container
    let added: (Int) -> Void

    @State private var draft = SequenceDraft()

    var body: some View {
        AddSheet(title: "New sequence of \(container.title)", canAdd: true, height: 320) {
            added(try await library.addSequence(draft, to: container.id))
        } content: {
            LabeledContent {
                TextField("", text: $draft.id, prompt: Text("Optional"))
                    .labelsHidden()
            } label: {
                HStack(spacing: 4) {
                    Text("Id")
                    HelpButton("A container with one order of things has one sequence, and it need not be named. Name them when there are two or more, because an alternative plays a sequence by its id.")
                }
            }
            Picker(selection: $draft.exploded) {
                ForEach(Exploded.allCases, id: \.self) { value in
                    Text(value.rawValue.capitalized).tag(value)
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Exploded")
                    HelpButton("Whether a client may show this sequence's items as if they were the parent's own: never, or allowed, or preferred.")
                }
            }
        }
    }
}
