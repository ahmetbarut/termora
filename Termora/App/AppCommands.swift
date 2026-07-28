import SwiftUI

/// Menü komutları key window'un WorkspaceViewModel'ine @FocusedValue ile ulaşır.
struct WorkspaceFocusedKey: FocusedValueKey {
    typealias Value = WorkspaceViewModel
}

/// Komut paleti de key window'a aittir; menü öğesi ona @FocusedValue ile ulaşır.
struct CommandPaletteFocusedKey: FocusedValueKey {
    typealias Value = CommandPaletteModel
}

/// AI paneli de pencere başınadır; menü onu @FocusedValue ile bulur.
struct AIPanelFocusedKey: FocusedValueKey {
    typealias Value = AIPanelModel
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

    var aiPanel: AIPanelModel? {
        get { self[AIPanelFocusedKey.self] }
        set { self[AIPanelFocusedKey.self] = newValue }
    }
}

struct AppCommands: Commands {
    @FocusedValue(\.workspace) private var workspace
    @FocusedValue(\.commandPalette) private var commandPalette
    @FocusedValue(\.aiPanel) private var aiPanel

    var body: some Commands {
        // briefs/2 "Menü Çubuğu": AI için ayrı bir üst menü AÇILMAZ, liste sabittir.
        // Panel bir görünüm anahtarıdır, yeri View menüsüdür.
        // DİKKAT: `CommandGroup { … }.disabled(…)` menüde çalışmaz; etkinlik Button'a verilir.
        CommandGroup(after: .sidebar) {
            Button(aiPanel?.isPresented == true ? "Hide AI Assistant" : "Show AI Assistant") {
                aiPanel?.isPresented.toggle()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(aiPanel == nil)

            Button("Explain Selection with AI") {
                guard let aiPanel else { return }
                Task { await aiPanel.openAndExplainSelection() }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            // Seçim yokken sorulacak bir şey yok; öğe gizlenmez, devre dışı görünür
            // (briefs/3 "Sağ Tık Menüleri" ile aynı kural).
            .disabled(aiPanel == nil)

            Divider()
        }

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
