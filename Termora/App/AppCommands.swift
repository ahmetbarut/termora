import SwiftUI

/// Menü komutları key window'un WorkspaceViewModel'ine @FocusedValue ile ulaşır.
struct WorkspaceFocusedKey: FocusedValueKey {
    typealias Value = WorkspaceViewModel
}

extension FocusedValues {
    var workspace: WorkspaceViewModel? {
        get { self[WorkspaceFocusedKey.self] }
        set { self[WorkspaceFocusedKey.self] = newValue }
    }
}

struct AppCommands: Commands {
    @FocusedValue(\.workspace) private var workspace

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Yeni Sekme") {
                workspace?.newTab()
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(workspace == nil)
        }

        // ⌘W standart "Close Window" öğesinin yerine geçer: önce sekme kapanır.
        CommandGroup(replacing: .saveItem) {
            Button("Sekmeyi Kapat") {
                if let workspace, let activeTabID = workspace.activeTabID {
                    workspace.requestCloseTab(id: activeTabID)
                }
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(workspace?.activeTabID == nil)
        }

        CommandGroup(after: .textEditing) {
            Divider()
            Button("Bul…") {
                workspace?.toggleSearchBar()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(workspace == nil)

            Button("Sonrakini Bul") {
                workspace?.findNextMatch()
            }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(workspace == nil)

            Button("Öncekini Bul") {
                workspace?.findPreviousMatch()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(workspace == nil)
        }

        // DİKKAT: `Commands` protokolünde `disabled` YOKTUR (yalnız `View` üzerinde vardır);
        // `CommandMenu { … }.disabled(…)` derlenmez. Etkinlik her Button'a tek tek verilir.
        CommandMenu("Pane") {
            Button("Split Vertically") {
                workspace?.splitActivePane(axis: .vertical)
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(workspace == nil)

            Button("Split Horizontally") {
                workspace?.splitActivePane(axis: .horizontal)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(workspace == nil)

            Divider()

            Button("Close Pane") {
                workspace?.requestCloseActivePane()
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .disabled(workspace == nil)

            Divider()

            Button("Focus Pane Left") { workspace?.focusPane(.left) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(workspace == nil)
            Button("Focus Pane Right") { workspace?.focusPane(.right) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(workspace == nil)
            Button("Focus Pane Up") { workspace?.focusPane(.up) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(workspace == nil)
            Button("Focus Pane Down") { workspace?.focusPane(.down) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(workspace == nil)
        }

        CommandMenu("Sekme") {
            Button("Sonraki Sekme") { workspace?.nextTab() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(workspace == nil)
            Button("Önceki Sekme") { workspace?.previousTab() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(workspace == nil)

            Divider()

            ForEach(1...9, id: \.self) { number in
                Button("Sekme \(number)") {
                    workspace?.selectTab(at: number - 1)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                .disabled(workspace == nil)
            }
        }
    }
}
