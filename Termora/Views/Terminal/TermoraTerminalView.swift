//
//  TermoraTerminalView.swift
//  Termora
//

import AppKit
import Foundation
import SwiftTerm

// MARK: - Context menu model

/// One entry of the terminal right-click menu. Pure data so the ordering and the
/// enabled/disabled rules can be tested without an NSMenu or a live PTY.
struct TerminalContextMenuItem: Equatable {
    enum Command: Equatable {
        case copy, paste, selectAll, clearScreen, splitRight, splitDown
    }

    let command: Command
    let title: String
    let isEnabled: Bool
}

/// Brief 3 "Sağ Tık Menüleri". Unavailable entries stay visible but disabled, so the
/// menu never changes shape under the cursor.
enum TerminalContextMenu {

    /// Ctrl-L. It goes to the PTY, not to the emulator: the shell's line editor clears the
    /// screen *and redraws its prompt*. Feeding `ESC[2J ESC[H` to the emulator instead would
    /// wipe the prompt off the screen and leave the user staring at an empty pane.
    static let clearScreenInput = "\u{0C}"

    /// Menu entries grouped into sections; the caller draws a separator between sections.
    static func sections(hasSelection: Bool,
                         canPaste: Bool,
                         canSplit: Bool) -> [[TerminalContextMenuItem]] {
        [
            [
                TerminalContextMenuItem(command: .copy, title: "Copy", isEnabled: hasSelection),
                TerminalContextMenuItem(command: .paste, title: "Paste", isEnabled: canPaste),
                TerminalContextMenuItem(command: .selectAll, title: "Select All", isEnabled: true),
            ],
            [
                TerminalContextMenuItem(command: .clearScreen, title: "Clear Screen", isEnabled: true),
            ],
            [
                TerminalContextMenuItem(command: .splitRight, title: "Split Right", isEnabled: canSplit),
                TerminalContextMenuItem(command: .splitDown, title: "Split Down", isEnabled: canSplit),
            ],
        ]
    }
}

// MARK: - View

/// `LocalProcessTerminalView` subclass with the four things Termora needs on top of SwiftTerm:
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
/// 4. The right-click menu (brief 3). The pane-level entries are closures the SwiftUI host
///    installs, because an AppKit view has no way back into the view model on its own.
final class TermoraTerminalView: LocalProcessTerminalView {
    let sessionID: UUID

    /// Installed by `TerminalHostView`. Nil means the pane cannot split (the menu entries
    /// are then shown disabled rather than hidden).
    var onSplitRight: (() -> Void)?
    var onSplitDown: (() -> Void)?

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

    // MARK: Right-click menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let canPaste = NSPasteboard.general.string(forType: .string)?.isEmpty == false
        let sections = TerminalContextMenu.sections(hasSelection: selectionActive,
                                                    canPaste: canPaste,
                                                    canSplit: onSplitRight != nil && onSplitDown != nil)

        let menu = NSMenu()
        // Items are enabled from the model above; letting AppKit auto-validate would send
        // these selectors up the responder chain and re-enable Copy without a selection.
        menu.autoenablesItems = false

        for (index, section) in sections.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for item in section {
                let menuItem = NSMenuItem(title: item.title,
                                          action: Self.selector(for: item.command),
                                          keyEquivalent: "")
                menuItem.target = self
                menuItem.isEnabled = item.isEnabled
                menu.addItem(menuItem)
            }
        }
        return menu
    }

    private static func selector(for command: TerminalContextMenuItem.Command) -> Selector {
        switch command {
        case .copy: return #selector(copy(_:))
        case .paste: return #selector(paste(_:))
        case .selectAll: return #selector(selectAll(_:))
        case .clearScreen: return #selector(clearScreen(_:))
        case .splitRight: return #selector(splitRight(_:))
        case .splitDown: return #selector(splitDown(_:))
        }
    }

    @objc private func clearScreen(_ sender: Any?) {
        send(txt: TerminalContextMenu.clearScreenInput)
    }

    @objc private func splitRight(_ sender: Any?) {
        onSplitRight?()
    }

    @objc private func splitDown(_ sender: Any?) {
        onSplitDown?()
    }
}
