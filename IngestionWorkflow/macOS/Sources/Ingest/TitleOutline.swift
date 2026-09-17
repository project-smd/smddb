// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import MakeMKV
import MakeMKVRobot
import SwiftUI

/// The left pane: titles, each opening to show its tracks, with a checkbox on each title as MakeMKV
/// has. The disc itself is not a row — there is only ever one, so it is the window title instead.
/// Tracks have no checkbox because `makemkvcon` selects them through a profile, not per title;
/// that is a later step.
///
/// A track MakeMKV derived from another — the lossy core inside a lossless track, a forced-only
/// subtitle stream — is nested under the track it came from, as the MakeMKV GUI nests it, so the
/// eight audio rows a Collection disc lists read as the four tracks they are.
@MainActor
struct TitleOutline: View {
    @Environment(IngestModel.self) private var model
    @Binding var selection: Node?
    /// Titles start closed; this holds the ones the user has opened.
    @State private var expanded: Set<Int> = []
    /// Likewise for tracks with something nested under them, keyed by title and track.
    @State private var expandedTracks: Set<Node> = []

    var body: some View {
        if model.scan == nil {
            ContentUnavailableView(
                model.phase == .scanning ? "Scanning…" : "No disc scanned",
                systemImage: "opticaldisc",
                description: Text(model.phase == .scanning ? "" : "Pick a source and press Scan.")
            )
        } else {
            VStack(spacing: 0) {
                header
                Divider()
                titleList
            }
        }
    }

    /// One checkbox over all the titles, showing the third state when the selection is partial.
    private var header: some View {
        HStack(spacing: 6) {
            MixedCheckbox(state: model.selectionState, isEnabled: !model.availableTitles.isEmpty) {
                model.toggleAllTitles()
            }
            .fixedSize()
            Text("All titles")
                .fontWeight(.medium)
            Spacer()
            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// "3 of 65 selected", and how many have been sent once any have.
    private var summary: String {
        let available = model.availableTitles
        let selected = available.filter { model.selectedTitles.contains($0.index) }.count
        let sent = model.importStatus.count
        return sent == 0
            ? "\(selected) of \(available.count) selected"
            : "\(selected) of \(available.count) selected · \(sent) sent to Import"
    }

    private var titleList: some View {
        @Bindable var model = model
        return List(selection: $selection) {
                ForEach(model.scan?.titles ?? [], id: \.index) { title in
                    DisclosureGroup(isExpanded: expansion(of: title.index)) {
                        ForEach(title.primaryTracks, id: \.index) { track in
                            let node = Node.stream(title: title.index, stream: track.index)
                            let derived = title.derivedTracks(of: track)
                            if derived.isEmpty {
                                trackRow(track, derived: [])
                                    .tag(node)
                            } else {
                                DisclosureGroup(isExpanded: trackExpansion(of: node)) {
                                    ForEach(derived, id: \.index) { child in
                                        trackRow(child, derived: [])
                                            .tag(Node.stream(title: title.index, stream: child.index))
                                    }
                                } label: {
                                    trackRow(track, derived: derived)
                                }
                                .tag(node)
                            }
                        }
                    } label: {
                        titleRow(title)
                    }
                    .tag(Node.title(title.index))
                }
            }
            .listStyle(.inset)
    }

    private func expansion(of index: Int) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(index) },
            set: { open in
                if open { expanded.insert(index) } else { expanded.remove(index) }
            }
        )
    }

    private func trackExpansion(of node: Node) -> Binding<Bool> {
        Binding(
            get: { expandedTracks.contains(node) },
            set: { open in
                if open { expandedTracks.insert(node) } else { expandedTracks.remove(node) }
            }
        )
    }

    /// A title sent to Import keeps its tick, loses its checkbox, and shows where it has got to;
    /// the rest stay tickable while a batch runs, so more can be sent to join it.
    private func titleRow(_ title: Title) -> some View {
        @Bindable var model = model
        let status = model.importStatus[title.index]
        return HStack {
            Toggle("", isOn: Binding(
                get: { model.selectedTitles.contains(title.index) },
                set: { on in
                    if on { model.selectedTitles.insert(title.index) } else { model.selectedTitles.remove(title.index) }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(status != nil)
            Text(titleName(title, status: status))
                .fontWeight(.medium)
                .lineLimit(1)
            Text(title.sourceIdentifier ?? "")
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
            Spacer()
            if let status {
                statusView(status)
            } else {
                Text([
                    title.durationText,
                    title.chapterCount.map { "\($0) ch" },
                    title.diskSizeText,
                ].compactMap { $0 }.joined(separator: " · "))
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(status == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .contextMenu {
            if case .rejected? = status {
                Button("Clear Rejection") { model.clearRejection(of: title) }
            }
        }
    }

    /// "Title 9", or "Title 9 (FBI warning)" once it has been rejected with a description.
    private func titleName(_ title: Title, status: ImportStatus?) -> String {
        if case .rejected(let rejection)? = status, let description = rejection.description {
            return "Title \(title.index) (\(description))"
        }
        return "Title \(title.index)"
    }

    @ViewBuilder
    private func statusView(_ status: ImportStatus) -> some View {
        HStack(spacing: 6) {
            switch status {
            case .queued:
                Image(systemName: "clock")
                Text("Queued")
            case .importing:
                ProgressView().controlSize(.mini)
                Text("Importing…")
            // A title imported this session and one imported before look the same: a green tick
            // and the date, so the disc reads consistently however long ago each was taken.
            case .imported(let date), .previouslyImported(let date):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Imported \(date, format: .dateTime.day().month().year())")
            case .failed:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                Text("Failed")
            // A disc logo carries no date: on a disc it was recognised on rather than rejected
            // from, there is no date that is this disc's.
            case .rejected(let rejection):
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                switch rejection.kind {
                case .rejected: Text("Rejected \(rejection.rejectedAt, format: .dateTime.day().month().year())")
                case .discLogo: Text("Rejected Disc Logo/Warning")
                }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    /// `derived` is what sits nested under this track, named on the row so the relationship is
    /// visible while the group is closed: "DTS-HD MA … + DTS core".
    private func trackRow(_ track: Track, derived: [Track]) -> some View {
        HStack {
            Image(systemName: icon(for: track.kind))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(track.codecShort ?? track.codecId ?? "?")
            Text([
                track.languageName,
                track.audioChannelLayoutName ?? track.name,
                track.videoSize,
                track.mkvFlagsText,
                track.isCore ? "core" : nil,
                track.isForcedOnly ? "forced only" : nil,
            ].compactMap { $0 }.joined(separator: " · "))
            .foregroundStyle(.secondary)
            if !derived.isEmpty {
                Text("+ " + derived.map { ($0.codecShort ?? "?") + ($0.isCore ? " core" : $0.isForcedOnly ? " forced" : "") }.joined(separator: ", "))
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text("#\(track.index)")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
        }
    }

    private func icon(for kind: TrackKind) -> String {
        switch kind {
        case .video: "video"
        case .audio: "speaker.wave.2"
        case .subtitles: "captions.bubble"
        case .unknown: "questionmark.circle"
        }
    }
}
