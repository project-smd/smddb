// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import AppKit
import SmdKit
import SwiftUI

/// A row in the Containers outline. Every row belongs to a container: the container itself, one
/// of its four groups, or a thing in a group. A child container is a row of its own kind, so the
/// same enum serves for selection and for which rows are open.
enum OutlineRow: Hashable {
    case container(ContainerID)
    case group(ContainerID, OutlineSection)
    case alternative(ContainerID, String)
    case feature(ContainerID, String)
    /// A sequence, which is also the group of its items.
    case sequence(ContainerID, Int)
    case entry(ContainerID, EntryPlace, Int)

    var container: ContainerID {
        switch self {
        case .container(let id), .group(let id, _), .alternative(let id, _), .feature(let id, _), .sequence(let id, _), .entry(let id, _, _): id
        }
    }
}

/// Which sheet is open.
enum Adding: Hashable, Identifiable {
    case root
    case alternative(ContainerID)
    case feature(ContainerID)
    case sequence(ContainerID)
    case item(ContainerID, EntryPlace)

    var id: Self { self }
}

/// The Containers window: an outline of the repository's containers, series at the top, and under
/// each what it holds — its alternatives, features, sequences and extras, each a group of its own
/// with a + in its header that adds to the end of it, and each re-ordered by dragging. A child
/// container appears as an item of the sequence or the extras that hold it, and opens the same
/// way. The selected row's own facts are beside. Authoring happens here; the same outline is what
/// Assign will offer when a file needs a home.
@MainActor
struct ContainersView: View {
    @Environment(ContainerLibrary.self) private var library
    @State private var selection: OutlineRow?
    /// The rows whose children are shown. Kept here rather than left to the list so that a group
    /// which has just gained something opens to show it, instead of coming back closed.
    @State private var expanded: Set<OutlineRow> = []
    @State private var adding: Adding?
    @State private var failure: String?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 280, ideal: 360)
        } detail: {
            detail
        }
        .navigationTitle("Containers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    adding = .root
                } label: {
                    Label("Add Container…", systemImage: "plus")
                }
                .help(library.repository == nil ? "Choose a repository folder in Settings first" : "Add a container at the top level; the + beside a group adds inside one")
                .disabled(library.repository == nil)
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(item: $adding) { adding in
            sheet(for: adding)
        }
        .alert("Could not save", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") {}
        } message: {
            Text(failure ?? "")
        }
        .task { await library.reload() }
        // The folder is a git clone: what is in it changes whenever the window was not in front.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await library.reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            Task { await library.reload() }
        }
        .onChange(of: library.roots.map(\.id)) {
            if let selection, library.containers[selection.container] == nil { self.selection = nil }
        }
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheet(for adding: Adding) -> some View {
        switch adding {
        case .root:
            AddContainerSheet { id in
                selection = .container(id)
            }
        case .alternative(let id):
            if let container = library.containers[id] {
                AddAlternativeSheet(container: container) { alternativeID in
                    open(.container(id), .group(id, .alternatives))
                    selection = .alternative(id, alternativeID)
                }
            }
        case .feature(let id):
            if let container = library.containers[id] {
                AddFeatureSheet(container: container) { featureID in
                    open(.container(id), .group(id, .features))
                    selection = .feature(id, featureID)
                }
            }
        case .sequence(let id):
            if let container = library.containers[id] {
                AddSequenceSheet(container: container) { index in
                    open(.container(id), .group(id, .sequences))
                    selection = .sequence(id, index)
                }
            }
        case .item(let id, let place):
            if let container = library.containers[id] {
                AddItemSheet(container: container, place: place) { added in
                    switch place {
                    case .sequence(let index): open(.container(id), .group(id, .sequences), .sequence(id, index))
                    case .extras: open(.container(id), .group(id, .items(.extras)))
                    }
                    selection = added.container.map { .container($0) } ?? .entry(id, place, added.index)
                }
            }
        }
    }

    private func open(_ rows: OutlineRow...) {
        expanded.formUnion(rows)
    }

    private func move(_ section: OutlineSection, in id: ContainerID, from source: IndexSet, to destination: Int) {
        Task {
            do {
                try await library.move(section, in: id, from: source, to: destination)
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    // MARK: Sidebar

    @ViewBuilder
    private var sidebar: some View {
        if library.repository == nil {
            ContentUnavailableView {
                Label("No repository", systemImage: "folder.badge.questionmark")
            } description: {
                Text("Containers live in a local clone of the smddb data repository.")
            } actions: {
                SettingsLink {
                    Text("Choose a folder in Settings…")
                }
            }
        } else if let error = library.loadError {
            ContentUnavailableView {
                Label("Repository not readable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
                    .font(.callout.monospaced())
            } actions: {
                Button("Look again") {
                    Task { await library.reload() }
                }
            }
        } else if library.roots.isEmpty {
            ContentUnavailableView {
                Label("No containers", systemImage: "square.stack.3d.up")
            } description: {
                Text(library.isLoading ? "" : "A series, a film or a collection starts a tree. Everything else goes inside one.")
            } actions: {
                Button("Add Container…") { adding = .root }
            }
        } else {
            List(selection: $selection) {
                ForEach(library.roots) { root in
                    containerRows(root.id, ancestors: [])
                }
            }
        }
    }

    private func expansion(of row: OutlineRow) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(row) },
            set: { open in if open { expanded.insert(row) } else { expanded.remove(row) } }
        )
    }

    /// The container's row and, beneath it, its four groups. Wrapped in `AnyView` because a child
    /// container's rows are these rows again.
    private func containerRows(_ id: ContainerID, ancestors: Set<ContainerID>) -> AnyView {
        guard let container = library.containers[id] else {
            return AnyView(
                Label("Missing container \(id.rawValue)", systemImage: "questionmark.square.dashed")
                    .foregroundStyle(.red)
            )
        }
        let ancestors = ancestors.union([id])
        return AnyView(
            DisclosureGroup(isExpanded: expansion(of: .container(id))) {
                alternativesGroup(container)
                featuresGroup(container)
                sequencesGroup(container, ancestors: ancestors)
                extrasGroup(container, ancestors: ancestors)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: container.type.systemImage)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(container.displayTitle)
                        .lineLimit(1)
                    if !container.listed {
                        Image(systemName: "eye.slash")
                            .foregroundStyle(.tertiary)
                            .help("Unlisted: reachable only through a relation or a ref")
                    }
                }
            }
            .tag(OutlineRow.container(id))
        )
    }

    private func alternativesGroup(_ container: Container) -> some View {
        let id = container.id
        return DisclosureGroup(isExpanded: expansion(of: .group(id, .alternatives))) {
            if container.alternatives.isEmpty {
                emptyRow("None")
            }
            ForEach(container.alternatives) { alternative in
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(alternative.title ?? alternative.id)
                        .lineLimit(1)
                    if alternative.id == container.defaultAlternative {
                        Text("default")
                            .foregroundStyle(.tertiary)
                    }
                }
                .tag(OutlineRow.alternative(id, alternative.id))
            }
            .onMove { source, destination in
                move(.alternatives, in: id, from: source, to: destination)
            }
        } label: {
            groupLabel("Alternatives", count: container.alternatives.count, help: "Add an alternative: a cut of this container, playing one of its sequences") {
                adding = .alternative(id)
            }
        }
        .tag(OutlineRow.group(id, .alternatives))
    }

    private func featuresGroup(_ container: Container) -> some View {
        let id = container.id
        return DisclosureGroup(isExpanded: expansion(of: .group(id, .features))) {
            if container.features.isEmpty {
                emptyRow("None")
            }
            ForEach(container.features) { feature in
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(feature.title ?? feature.id)
                        .lineLimit(1)
                    Text(feature.type.rawValue)
                        .foregroundStyle(.tertiary)
                }
                .tag(OutlineRow.feature(id, feature.id))
            }
            .onMove { source, destination in
                move(.features, in: id, from: source, to: destination)
            }
        } label: {
            groupLabel("Features", count: container.features.count, help: "Add a feature: a commentary or an isolated score that items of this container carry a track of") {
                adding = .feature(id)
            }
        }
        .tag(OutlineRow.group(id, .features))
    }

    private func sequencesGroup(_ container: Container, ancestors: Set<ContainerID>) -> some View {
        let id = container.id
        return DisclosureGroup(isExpanded: expansion(of: .group(id, .sequences))) {
            if container.sequences.isEmpty {
                emptyRow("None")
            }
            ForEach(Array(container.sequences.enumerated()), id: \.offset) { index, sequence in
                DisclosureGroup(isExpanded: expansion(of: .sequence(id, index))) {
                    itemRows(container, place: .sequence(index), items: sequence.items, ancestors: ancestors)
                } label: {
                    groupLabel(sequenceTitle(sequence, index: index, of: container), count: sequence.items.count, systemImage: "list.number", help: "Add an item at the end of this sequence") {
                        adding = .item(id, .sequence(index))
                    }
                }
                .tag(OutlineRow.sequence(id, index))
            }
            .onMove { source, destination in
                move(.sequences, in: id, from: source, to: destination)
            }
        } label: {
            groupLabel("Sequences", count: container.sequences.count, help: "Add a sequence: an ordered run of items, such as the broadcast parts or the omnibus") {
                adding = .sequence(id)
            }
        }
        .tag(OutlineRow.group(id, .sequences))
    }

    private func extrasGroup(_ container: Container, ancestors: Set<ContainerID>) -> some View {
        let id = container.id
        let title = container.extrasAnchor.map { "Extras · anchored at \($0)" } ?? "Extras"
        return DisclosureGroup(isExpanded: expansion(of: .group(id, .items(.extras)))) {
            itemRows(container, place: .extras, items: container.extras, ancestors: ancestors)
        } label: {
            groupLabel(title, count: container.extras.count, help: "Add an extra at the end: a featurette, a documentary, a container of them") {
                adding = .item(id, .extras)
            }
        }
        .tag(OutlineRow.group(id, .items(.extras)))
    }

    @ViewBuilder
    private func itemRows(_ container: Container, place: EntryPlace, items: [Entry], ancestors: Set<ContainerID>) -> some View {
        if items.isEmpty {
            emptyRow("Empty")
        }
        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
            if let child = item.container, !ancestors.contains(child) {
                containerRows(child, ancestors: ancestors)
            } else {
                entryLabel(item, ancestors: ancestors)
                    .tag(OutlineRow.entry(container.id, place, index))
            }
        }
        .onMove { source, destination in
            move(.items(place), in: container.id, from: source, to: destination)
        }
    }

    private func entryLabel(_ item: Entry, ancestors: Set<ContainerID>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: item.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            if let child = item.container {
                // Only reached for a cycle: the child is an ancestor, so it is named and not opened.
                Text(library.containers[child]?.title ?? child.rawValue)
                    .lineLimit(1)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.tertiary)
                    .help("Holds one of its own ancestors; not opened again here")
            } else if let ref = item.ref {
                Text(ref.container.map { id in "\(library.containers[id]?.title ?? id.rawValue) › \(ref.item)" } ?? ref.item)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            } else {
                Text(item.title ?? item.id ?? "")
                    .lineLimit(1)
            }
            if item.optional {
                Text("optional")
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func groupLabel(_ title: String, count: Int, systemImage: String? = nil, help: String, add: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
            Text(title)
                .foregroundStyle(systemImage == nil ? .secondary : .primary)
                .lineLimit(1)
            if count > 0 {
                Text("\(count)")
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Spacer()
            Button(action: add) {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .help(help)
            .accessibilityLabel("Add to \(title)")
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.tertiary)
            .padding(.leading, 22)
    }

    private func sequenceTitle(_ sequence: Sequence, index: Int, of container: Container) -> String {
        var title = sequence.id ?? (container.sequences.count == 1 ? "Sequence" : "Sequence \(index + 1)")
        if sequence.exploded != .never { title += " · exploded \(sequence.exploded.rawValue)" }
        return title
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let selection, let container = library.containers[selection.container] {
            if case .group(_, let section) = selection {
                GroupDetail(container: container, section: section)
            } else {
                ContainerEditor(container: container, row: selection)
                    .id(selection)
            }
        } else {
            ContentUnavailableView("Nothing selected", systemImage: "square.stack.3d.up", description: Text(library.roots.isEmpty ? "" : "Select a container, or something it holds, to see and edit its facts."))
        }
    }

}

extension ContainerType {
    var systemImage: String {
        switch self {
        case .series: "tv"
        case .season: "square.stack"
        case .serial: "book"
        case .arc: "point.topleft.down.to.point.bottomright.curvepath"
        case .volume: "books.vertical"
        case .collection: "square.grid.2x2"
        case .episode: "play.rectangle"
        case .movie: "film"
        }
    }
}

extension Entry {
    var systemImage: String {
        if ref != nil { return "arrow.turn.down.right" }
        switch type {
        case .episode?: return "play.rectangle"
        case .movie?: return "film"
        case .featurette?: return "sparkles.rectangle.stack"
        case .container?: return "square.stack.3d.up"
        default: return "doc"
        }
    }
}

/// A group row: what the group is for, so the + beside it is not a guess.
struct GroupDetail: View {
    let container: Container
    let section: OutlineSection

    var body: some View {
        let (title, count, text) = facts
        Form {
            Section {
                Text(text)
                    .foregroundStyle(.secondary)
                LabeledContent("Count", value: "\(count)")
            } header: {
                Text("\(title) of \(container.displayTitle)")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
        }
        .formStyle(.grouped)
    }

    private var facts: (String, Int, String) {
        switch section {
        case .alternatives:
            ("Alternatives", container.alternatives.count, "The cuts of this container. Each plays one of its sequences, and one of them is what a client plays when it has not been asked. Drag to change the order a client offers them in.")
        case .features:
            ("Features", container.features.count, "What an item here can carry a track of: a commentary, an isolated score. Declared once, on the container, and named by the bindings that carry it.")
        case .sequences:
            ("Sequences", container.sequences.count, "The ordered runs of items: the broadcast parts, the omnibus, a DVD order. A container with one order of things has one sequence.")
        case .items(.extras):
            ("Extras", container.extras.count, "What comes with the container without being part of any sequence: featurettes, documentaries, a container of them. Anchored at an item when they belong after one.")
        case .items(.sequence(let index)):
            ("Sequence \(index + 1)", container[.sequence(index)].count, "The items of this sequence, in order.")
        }
    }
}

