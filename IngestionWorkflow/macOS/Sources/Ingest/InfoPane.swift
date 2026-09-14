// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import MakeMKV
import MakeMKVRobot
import SwiftUI

/// The right pane: every attribute MakeMKV reported for the selected node, by upstream name, in id
/// order, and for the disc when nothing is selected. The same information as the GUI's info panel,
/// minus its prose rendering, plus the raw message codes — which is the form the database wants.
@MainActor
struct InfoPane: View {
    @Environment(IngestModel.self) private var model
    var selection: Node?

    private struct AttributeRow: Identifiable {
        var id: Int
        var name: String
        var value: String
        var messageCode: Int
    }

    var body: some View {
        if let (heading, attributes) = content {
            VStack(alignment: .leading, spacing: 0) {
                Text(heading)
                    .font(.headline)
                    .padding(12)
                Divider()
                Table(rows(attributes)) {
                    TableColumn("Attribute") { row in
                        Text(row.name).font(.callout)
                    }
                    .width(min: 120, ideal: 170)
                    TableColumn("Value") { row in
                        Text(row.value)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                    TableColumn("Code") { row in
                        Text(row.messageCode == 0 ? "" : String(row.messageCode))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .width(48)
                }
            }
        } else {
            ContentUnavailableView("No disc", systemImage: "info.circle", description: Text("Scan a disc to see its titles."))
        }
    }

    private var content: (String, [AttributeID: Attribute])? {
        guard let disc = model.scan?.disc else { return nil }
        switch selection {
        case nil:
            return (disc.name ?? "Disc", disc.attributes)
        case .title(let index):
            guard let title = disc.title(index: index) else { return nil }
            return ("Title \(index)" + (title.sourceIdentifier.map { " — \($0)" } ?? ""), title.attributes)
        case .stream(let titleIndex, let streamIndex):
            guard let stream = disc.title(index: titleIndex)?.tracks.first(where: { $0.index == streamIndex }) else { return nil }
            return ("Title \(titleIndex), stream \(streamIndex)", stream.attributes)
        }
    }

    private func rows(_ attributes: [AttributeID: Attribute]) -> [AttributeRow] {
        attributes.values
            .sorted { $0.id.rawValue < $1.id.rawValue }
            .map { AttributeRow(id: $0.id.rawValue, name: $0.id.name ?? "#\($0.id.rawValue)", value: $0.value, messageCode: $0.messageCode) }
    }
}
