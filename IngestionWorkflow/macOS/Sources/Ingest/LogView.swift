// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import SwiftUI

/// MakeMKV's messages and the tool's own notes, newest at the bottom, kept scrolled to the end.
@MainActor
struct LogView: View {
    @Environment(IngestModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            List(model.log) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.time, format: .dateTime.hour().minute().second())
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                    Text(entry.text)
                        .font(.callout)
                        .foregroundStyle(entry.isError ? .red : .primary)
                        .textSelection(.enabled)
                }
                .id(entry.id)
            }
            .listStyle(.plain)
            .onChange(of: model.log.count) {
                if let last = model.log.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}
