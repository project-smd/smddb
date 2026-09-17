// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import SwiftUI

/// The panel along the bottom of the Assign stage: what can be done with the file in view. Reject
/// is the first thing there is to do with a file, and for a good share of a disc the only thing.
@MainActor
struct AssignActionBar: View {
    let item: ImportedItem
    /// Asked for, not done: the sheet confirms, and the view that owns the player and the
    /// selection carries it out.
    let reject: (Rejection.Kind) -> Void

    var body: some View {
        HStack {
            // Reject sits at the trailing end and in red, apart from whatever constructive actions
            // come to fill the panel from the leading side: it is the one that deletes.
            Spacer()
            // A split button: the face rejects, the arrow refines what it is rejected as.
            Menu {
                Button("Reject as Disc Logo/Warning…") { reject(.discLogo) }
            } label: {
                Text("Reject…")
            } primaryAction: {
                reject(.rejected)
            }
            .menuStyle(.button)
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .fixedSize()
            .help("Delete this file and mark its title as rejected")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// What a press of Reject is waiting on: which file, and as what.
struct RejectRequest: Identifiable {
    let item: ImportedItem
    let kind: Rejection.Kind

    var id: ImportedItem.ID { item.id }
}

/// Confirms a rejection, since it deletes a file that took a disc read to make, and takes the
/// description: optional for a plain reject, required for a disc logo, where it is all a later
/// disc's row will have to say what was recognised.
@MainActor
struct RejectSheet: View {
    let request: RejectRequest
    /// Carries the rejection out; throws when the file could not be deleted.
    let confirm: (String) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var failure: String?

    private var isLogo: Bool { request.kind == .discLogo }

    private var canConfirm: Bool {
        !isLogo || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Description", text: $description, prompt: Text(isLogo ? "Universal logo, FBI warning…" : "Optional"))
                        .onSubmit { if canConfirm { submit() } }
                } header: {
                    Text(isLogo ? "Reject as a disc logo or warning?" : "Reject this file?")
                        .font(.headline)
                } footer: {
                    Text(explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                // Not the default action: Return in the description field submits, but a stray
                // Return elsewhere should not delete a file.
                Button("Delete and Reject", role: .destructive) { submit() }
                    .disabled(!canConfirm)
            }
            .padding()
        }
        .frame(width: 480, height: isLogo ? 300 : 270)
    }

    private var explanation: String {
        let file = "\(request.item.fileName) will be deleted from disk."
        return isLogo
            ? file + " The same clip on any other disc will come up rejected, under this description, without being imported."
            : file
    }

    private func submit() {
        do {
            try confirm(description)
            dismiss()
        } catch {
            failure = "Could not delete the file: \(error.localizedDescription)"
        }
    }
}
