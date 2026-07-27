//
//  TerminalHostView.swift
//  Termora
//

import AppKit
import SwiftUI

/// Places the AppKit terminal that `SessionManager` owns into the SwiftUI tree.
///
/// It never creates or destroys terminals. SwiftUI may tear this representable down and
/// rebuild it (tab switch, split rebuild) without the shell process or its scrollback
/// noticing — that is the whole point of the view cache in `SessionManager`.
///
/// The one case where the hosted NSView is replaced is `SessionManager.restartSession`, which
/// puts a new terminal behind the same session id. Callers therefore key this representable on
/// `session.restartGeneration` (M3 panes do) so SwiftUI asks for the new view instead of
/// keeping the dead one on screen.
struct TerminalHostView: NSViewRepresentable {

    let sessionID: UUID
    let sessionManager: SessionManager
    let isActive: Bool
    /// Right-click menu entries that only the SwiftUI side can perform (brief 3). They are
    /// re-installed on every update pass so they always close over the current pane.
    var onSplitRight: (() -> Void)?
    var onSplitDown: (() -> Void)?

    /// Remembers which session this host last handed first-responder status to, so a routine
    /// re-render does not steal focus on every layout pass.
    final class Coordinator {
        private(set) var focusedSessionID: UUID?

        func shouldRequestFocus(sessionID: UUID, isActive: Bool) -> Bool {
            guard isActive else { return false }
            guard focusedSessionID != sessionID else { return false }
            focusedSessionID = sessionID
            return true
        }

        func resignFocusTracking() {
            focusedSessionID = nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TermoraTerminalView {
        guard let view = sessionManager.terminalView(for: sessionID) else {
            // Invariant: a pane is only ever built from a session SessionManager created, and
            // the view is created together with the session. Silently substituting a blank
            // terminal here would hide the bug behind a dead-looking window.
            preconditionFailure("TerminalHostView asked to host session \(sessionID), which SessionManager never created")
        }
        view.onSplitRight = onSplitRight
        view.onSplitDown = onSplitDown
        return view
    }

    func updateNSView(_ nsView: TermoraTerminalView, context: Context) {
        nsView.onSplitRight = onSplitRight
        nsView.onSplitDown = onSplitDown

        guard context.coordinator.shouldRequestFocus(sessionID: sessionID, isActive: isActive) else {
            if !isActive { context.coordinator.resignFocusTracking() }
            return
        }

        // The view is not in a window yet during the first update pass; defer to the next
        // run-loop turn, and if it still has no window, reset so a later update retries.
        DispatchQueue.main.async {
            guard let window = nsView.window else {
                context.coordinator.resignFocusTracking()
                return
            }
            window.makeFirstResponder(nsView)
        }
    }
}