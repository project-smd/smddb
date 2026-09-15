// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import MakeMKVRobot
import SwiftUI

/// The Assign stage: a queue of imported files in a drawer on the right, and the selected file
/// playing in the detail area, with its chapters and the disc facts beside it. Assigning itself —
/// which container, which entry, which cut — is the next step and lands here.
@MainActor
struct AssignView: View {
    @Environment(IngestModel.self) private var model
    @State private var selected: ImportedItem.ID?
    @State private var queuePresented = true
    @State private var player = FilePlayer()

    private var selectedItem: ImportedItem? {
        model.assignQueue.first(where: { $0.id == selected })
    }

    var body: some View {
        Group {
            if let item = selectedItem {
                FileViewer(item: item, player: player)
            } else if model.assignQueue.isEmpty {
                ContentUnavailableView("Nothing to assign", systemImage: "tag", description: Text("Files arrive here as Import finishes each one."))
            } else {
                ContentUnavailableView("Select a file", systemImage: "tag", description: Text("Pick one from the queue."))
            }
        }
        .navigationTitle("Assign")
        .onChange(of: selectedItem?.fileURL, initial: true) { _, url in
            if let url {
                player.load(url, autoplay: UserDefaults.standard.bool(forKey: Preferences.autoplay))
            } else {
                player.stop()
            }
        }
        .onDisappear { player.stop() }
        .inspector(isPresented: $queuePresented) {
            QueueDrawer(selected: $selected)
                .inspectorColumnWidth(min: 260, ideal: 320, max: 480)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    queuePresented.toggle()
                } label: {
                    Label("Queue", systemImage: queuePresented ? "sidebar.trailing" : "sidebar.trailing")
                }
                .help(queuePresented ? "Hide the queue" : "Show the queue")
            }
        }
    }
}

/// The files waiting to be assigned, oldest first.
@MainActor
struct QueueDrawer: View {
    @Environment(IngestModel.self) private var model
    @Binding var selected: ImportedItem.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Queue")
                    .font(.headline)
                Spacer()
                Text("\(model.assignQueue.count)")
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()
            if model.assignQueue.isEmpty {
                Spacer()
                Text("Empty")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(model.assignQueue, selection: $selected) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.fileName)
                            .lineLimit(2)
                        Text([
                            item.discName,
                            "title \(item.title.index)",
                            item.title.durationText,
                            item.fingerprint.map { String($0.contentHash.prefix(8)) },
                        ].compactMap { $0 }.joined(separator: " · "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        Text(item.importedAt, format: .dateTime.hour().minute())
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }
        }
    }
}
