// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import AppKit
import SwiftUI

/// A checkbox that can show the third state — some, but not all — which SwiftUI's `Toggle` cannot.
/// The state is owned by the caller: a click reports itself and the caller decides what "some"
/// becomes, rather than letting AppKit cycle through its own three states.
struct MixedCheckbox: NSViewRepresentable {
    enum State {
        case none
        case some
        case all
    }

    var state: State
    var isEnabled = true
    var onClick: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: "", target: context.coordinator, action: #selector(Coordinator.clicked))
        button.allowsMixedState = true
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.onClick = onClick
        button.isEnabled = isEnabled
        button.state = switch state {
        case .none: .off
        case .some: .mixed
        case .all: .on
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onClick: onClick)
    }

    final class Coordinator: NSObject {
        var onClick: () -> Void

        init(onClick: @escaping () -> Void) {
            self.onClick = onClick
        }

        @objc func clicked(_ sender: NSButton) {
            onClick()
        }
    }
}
