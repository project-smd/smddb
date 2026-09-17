// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import SmdKit
import SwiftUI

/// Adds one container at the top level, by hand: what it is, what it is called, and one provider's
/// id for it. A container inside another is added from the outline, as an item of the sequence or
/// the extras it belongs to. Building one from a provider's own record — a TVDB series, a TMDb
/// episode group — is a later step; it would land in the same draft.
@MainActor
struct AddContainerSheet: View {
    @Environment(ContainerLibrary.self) private var library
    /// Called with the new container's id.
    let added: (ContainerID) -> Void

    @State private var draft = ContainerDraft()

    var body: some View {
        AddSheet(title: "New container at the top level", canAdd: draft.isComplete, height: 420) {
            added(try await library.add(draft, inside: nil))
        } content: {
            ContainerFields(draft: $draft)
        }
    }
}

/// The fields a container draft has, shared by the top-level sheet and the item sheet.
struct ContainerFields: View {
    @Binding var draft: ContainerDraft

    var body: some View {
        Picker("Type", selection: $draft.type) {
            ForEach(ContainerType.allCases, id: \.self) { type in
                Text(type.title).tag(type)
            }
        }
        TextField("Title", text: $draft.title)
        if draft.type.hasYear {
            YearFields(year: $draft.year, inTitle: $draft.yearInTitle)
        }
        LabeledContent {
            TextField("", text: $draft.typeLabel, prompt: Text("Optional"))
                .labelsHidden()
        } label: {
            HStack(spacing: 4) {
                Text("Type label")
                HelpButton("The word this show uses for a \(draft.type.title.lowercased()), shown in place of it: Doctor Who calls a serial a Story, an anime release calls one a Volume, a British season is a Series. Leave it empty to show the type's own name.")
            }
        }
        OutlineField(text: $draft.outline)
        Section("External references") {
            ExternalRefsEditor(refs: $draft.externalRefs)
        }
    }
}

/// The year and whether it is part of the name, for the types that have one.
struct YearFields: View {
    @Binding var year: String
    @Binding var inTitle: Bool

    static let help = "The year a series began, a season aired or a film was released. Show in title names it that way wherever the title is shown — Doctor Who (1963) — which is how the 1963 programme is told from the 2005 one. The title itself stays the bare name."

    private var value: Int? {
        Int(year.trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        LabeledContent {
            HStack {
                TextField("", text: $year, prompt: Text("Optional"))
                    .labelsHidden()
                    .frame(width: 72)
                Toggle("Show in title", isOn: $inTitle)
                    .disabled(value == nil)
                if value == nil, !year.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Not a year")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("Year")
                HelpButton(Self.help)
            }
        }
    }
}

/// The outline field, with the one explanation of what goes in it.
struct OutlineField: View {
    @Binding var text: String

    static let help = "Why someone would choose this, in a sentence: the hook of a story, what an extra has in it, what a cut offers that the default does not. Leave it empty where a provider already answers that, as one does for most seasons and episodes. It must be your own words: the database is public domain, so a line copied from a disc insert, a provider or Wikipedia cannot go in, and neither can a generated one."

    var body: some View {
        LabeledContent {
            TextField("", text: $text, prompt: Text("Optional"), axis: .vertical)
                .labelsHidden()
                .lineLimit(1...3)
        } label: {
            HStack(spacing: 4) {
                Text("Outline")
                HelpButton(Self.help)
            }
        }
    }
}

/// A list of external references, a provider and its id each, with a row added at the end and
/// any row removed. A row with no id is dropped when saved, so an empty one costs nothing.
struct ExternalRefsEditor: View {
    @Binding var refs: [ExternalRef]

    var body: some View {
        if refs.isEmpty {
            Text("None")
                .foregroundStyle(.secondary)
        }
        ForEach(refs.indices, id: \.self) { index in
            let ref = binding(index)
            HStack {
                Picker("", selection: ref.provider) {
                    ForEach(providers(including: ref.wrappedValue.provider), id: \.self) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
                TextField("Id", text: ref.value, prompt: Text("Id"))
                    .labelsHidden()
                Button {
                    if refs.indices.contains(index) { refs.remove(at: index) }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove this reference")
                .accessibilityLabel("Remove reference")
            }
        }
        Button {
            refs.append(ExternalRef(provider: nextProvider, value: ""))
        } label: {
            Label("Add reference", systemImage: "plus.circle")
        }
        .buttonStyle(.borderless)
    }

    /// The row's binding, guarded: a row that has just been removed reads as empty and writes
    /// nowhere, rather than indexing past the end while the list catches up.
    private func binding(_ index: Int) -> Binding<ExternalRef> {
        Binding(
            get: { refs.indices.contains(index) ? refs[index] : ExternalRef(provider: .tvdb, value: "") },
            set: { if refs.indices.contains(index) { refs[index] = $0 } }
        )
    }

    private func providers(including current: Provider) -> [Provider] {
        Provider.known.contains(current) ? Provider.known : Provider.known + [current]
    }

    /// The first provider not already referenced, so adding a row does not start on a duplicate.
    private var nextProvider: Provider {
        let used = Set(refs.map(\.provider))
        return Provider.known.first { !used.contains($0) } ?? .tvdb
    }
}

/// A feature's type: one of the two the proposals name, or any other slug.
struct FeatureTypeField: View {
    @Binding var type: FeatureType

    private enum Kind: String, CaseIterable {
        case commentary = "Commentary"
        case isolatedMusic = "Isolated music"
        case other = "Other"
    }

    private var kind: Binding<Kind> {
        Binding(
            get: {
                switch type {
                case .commentary: .commentary
                case .isolatedMusic: .isolatedMusic
                default: .other
                }
            },
            set: { kind in
                switch kind {
                case .commentary: type = .commentary
                case .isolatedMusic: type = .isolatedMusic
                case .other: type = FeatureType(rawValue: "")
                }
            }
        )
    }

    var body: some View {
        Picker("Type", selection: kind) {
            ForEach(Kind.allCases, id: \.self) { kind in
                Text(kind.rawValue).tag(kind)
            }
        }
        if kind.wrappedValue == .other {
            TextField("Type id", text: Binding(get: { type.rawValue }, set: { type = FeatureType(rawValue: $0) }), prompt: Text("lowercase-with-hyphens"))
        }
    }
}

/// The shape every Add sheet has: a heading, a grouped form, and Cancel and Add beneath. Add runs
/// the save, shows why it failed if it did, and closes the sheet if it did not.
struct AddSheet<Content: View>: View {
    let title: String
    let canAdd: Bool
    var height: CGFloat = 400
    let add: @MainActor () async throws -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    content()
                } header: {
                    Text(title)
                        .font(.headline)
                }
                if let failure {
                    Text(failure)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdd || saving)
            }
            .padding()
        }
        .frame(width: 480, height: height)
    }

    private func submit() {
        saving = true
        failure = nil
        Task {
            do {
                try await add()
                dismiss()
            } catch {
                failure = error.localizedDescription
                saving = false
            }
        }
    }
}

/// The standard round help button, opening a short explanation in a popover rather than putting
/// the explanation in the field as placeholder text, where it would vanish on the first keystroke.
struct HelpButton: View {
    let text: String
    @State private var shown = false

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Button {
            shown.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Help")
        .popover(isPresented: $shown, arrowEdge: .trailing) {
            Text(text)
                .frame(width: 280, alignment: .leading)
                .padding()
        }
    }
}
