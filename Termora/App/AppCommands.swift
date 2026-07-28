import SwiftUI

/// Menü komutları key window'un WorkspaceViewModel'ine @FocusedValue ile ulaşır.
struct WorkspaceFocusedKey: FocusedValueKey {
    typealias Value = WorkspaceViewModel
}

/// Komut paleti de key window'a aittir; menü öğesi ona @FocusedValue ile ulaşır.
struct CommandPaletteFocusedKey: FocusedValueKey {
    typealias Value = CommandPaletteModel
}

extension FocusedValues {
    var workspace: WorkspaceViewModel? {
        get { self[WorkspaceFocusedKey.self] }
        set { self[WorkspaceFocusedKey.self] = newValue }
    }

    var commandPalette: CommandPaletteModel? {
        get { self[CommandPaletteFocusedKey.self] }
        set { self[CommandPaletteFocusedKey.self] = newValue }
    }
}

struct AppCommands: Commands {
    @FocusedValue(\.workspace) private var workspace
    @FocusedValue(\.commandPalette) private var commandPalette

    var body: some Commands {
        // Paletin ikinci kısayolu (⌘⇧P) menüye ikinci bir öğe eklemez; pencere düzeyinde
        // `CommandPaletteHotkeyMonitor` karşılar (menü öğesi tek kısayol taşıyabilir).
        CommandGroup(after: .toolbar) {
            Button("Command Palette…") {
                commandPalette?.toggle()
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(commandPalette == nil)
        }

        CommandGroup(after: .newItem) {
            Button("New Tab") {
                workspace?.newTab()
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(workspace == nil)
        }

        // ⌘W standart "Close Window" öğesinin yerine geçer: önce sekme kapanır.
        CommandGroup(replacing: .saveItem) {
            Button(workspace?.activeTabID == nil ? "Close Window" : "Close Tab") {
                if let workspace, let activeTabID = workspace.activeTabID {
                    workspace.requestCloseTab(id: activeTabID)
                } else {
                    // Bu grup standart "Close Window" öğesinin yerine geçtiği için, terminal
                    // penceresi dışındaki pencerelerde (Ayarlar) ⌘W'nin karşılığı kalmaz.
                    // Devre dışı bırakılırsa Ayarlar penceresi klavyeyle HİÇ kapatılamaz.
                    NSApp.keyWindow?.performClose(nil)
                }
            }
            .keyboardShortcut("w", modifiers: .command)
        }

        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find…") {
                workspace?.toggleSearchBar()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(workspace == nil)

            Button("Find Next") {
                workspace?.findNextMatch()
            }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(workspace == nil)

            Button("Find Previous") {
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

        CommandMenu("Tab") {
            Button("Next Tab") { workspace?.nextTab() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(workspace == nil)
            Button("Previous Tab") { workspace?.previousTab() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(workspace == nil)

            Divider()

            ForEach(1...9, id: \.self) { number in
                Button("Tab \(number)") {
                    workspace?.selectTab(at: number - 1)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                .disabled(workspace == nil)
            }
        }
    }
}
