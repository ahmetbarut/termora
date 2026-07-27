//
//  TermoraTerminalView.swift
//  Termora
//

import AppKit
import Foundation
import SwiftTerm

/// `LocalProcessTerminalView` subclass with the three things Termora needs on top of SwiftTerm:
///
/// 1. It knows which session it renders, so `SessionManager` can route delegate callbacks
///    back to a `TerminalSession` from the `source` argument alone.
/// 2. It ignores zero and negative layout passes. SwiftUI hands an `NSViewRepresentable`
///    a 0x0 frame during transient layout; SwiftTerm would recompute a 0-column terminal
///    and push that size onto the PTY with `TIOCSWINSZ`, wrecking the running program.
/// 3. Spec §7 key handling: AppKit offers a ⌘ key equivalent to the key window's view
///    hierarchy *before* the main menu, so a terminal that handles ⌘ itself would swallow
///    ⌘T / ⌘W / ⌘D / ⌘F. Declining every ⌘ combination here hands them to the menu;
///    ⌘C / ⌘V keep working through the standard Edit menu and SwiftTerm's `copy(_:)`/`paste(_:)`.
final class TermoraTerminalView: LocalProcessTerminalView {
    let sessionID: UUID

    init(sessionID: UUID, frame: CGRect) {
        self.sessionID = sessionID
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("TermoraTerminalView is created in code only")
    }

    override func setFrameSize(_ newSize: NSSize) {
        guard newSize.width > 0, newSize.height > 0 else { return }
        super.setFrameSize(newSize)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) { return false }
        return super.performKeyEquivalent(with: event)
    }
}
