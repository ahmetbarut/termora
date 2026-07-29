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
    /// Sidebar görünürlüğü pencere başına değil uygulama genelinde saklanır (briefs/3
    /// "Sidebar" onu bir tercih olarak tanımlar), bu yüzden @FocusedValue değil doğrudan
    /// depo verilir.
    let settings: SettingsStore

    @FocusedValue(\.workspace) private var workspace
    @FocusedValue(\.commandPalette) private var commandPalette
    @FocusedValue(\.aiPanel) private var aiPanel

    var body: some Commands {
        // briefs/2 "Menü Çubuğu": AI için ayrı bir üst menü AÇILMAZ, liste sabittir.
        // Panel bir görünüm anahtarıdır, yeri View menüsüdür.
        // DİKKAT: `CommandGroup { … }.disabled(…)` menüde çalışmaz; etkinlik Button'a verilir.
        CommandGroup(after: .sidebar) {
            // briefs/3 "Sidebar": tamamen açılıp kapanır, ikon şeridi bırakmaz.
            Button(settings.settings.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                settings.settings.isSidebarVisible.toggle()
            }
            .shortcut(AppShortcuts.toggleSidebar, custom: settings.settings.customShortcutStrokes)

            // briefs/2 "Komut Blokları": panel terminalin YANINDA durur, yerine geçmez —
            // kapalıyken görünüm tam olarak klasik terminaldir.
            Button(settings.settings.isCommandBlockPanelVisible
                   ? "Hide Command Blocks" : "Show Command Blocks") {
                settings.settings.isCommandBlockPanelVisible.toggle()
            }
            .shortcut(AppShortcuts.toggleCommandBlocks, custom: settings.settings.customShortcutStrokes)

            Button(aiPanel?.isPresented == true ? "Hide AI Assistant" : "Show AI Assistant") {
                aiPanel?.isPresented.toggle()
            }
            .shortcut(AppShortcuts.toggleAIPanel, custom: settings.settings.customShortcutStrokes)
            .disabled(aiPanel == nil)

            Button("Explain Selection with AI") {
                guard let aiPanel else { return }
                Task { await aiPanel.openAndExplainSelection() }
            }
            .shortcut(AppShortcuts.explainSelection, custom: settings.settings.customShortcutStrokes)
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
            .shortcut(AppShortcuts.commandPalette, custom: settings.settings.customShortcutStrokes)
            .disabled(commandPalette == nil)
        }

        CommandGroup(after: .newItem) {
            Button("New Tab") {
                workspace?.newTab()
            }
            .shortcut(AppShortcuts.newTab, custom: settings.settings.customShortcutStrokes)
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
            .shortcut(AppShortcuts.closeTabOrWindow, custom: settings.settings.customShortcutStrokes)
        }

        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find…") {
                workspace?.toggleSearchBar()
            }
            .shortcut(AppShortcuts.find, custom: settings.settings.customShortcutStrokes)
            .disabled(workspace == nil)

            Button("Find Next") {
                workspace?.findNextMatch()
            }
            .shortcut(AppShortcuts.findNext, custom: settings.settings.customShortcutStrokes)
            .disabled(workspace == nil)

            Button("Find Previous") {
                workspace?.findPreviousMatch()
            }
            .shortcut(AppShortcuts.findPrevious, custom: settings.settings.customShortcutStrokes)
            .disabled(workspace == nil)
        }

        // DİKKAT: `Commands` protokolünde `disabled` YOKTUR (yalnız `View` üzerinde vardır);
        // `CommandMenu { … }.disabled(…)` derlenmez. Etkinlik her Button'a tek tek verilir.
        CommandMenu("Pane") {
            Button("Split Vertically") {
                workspace?.splitActivePane(axis: .vertical)
            }
            .shortcut(AppShortcuts.splitVertically, custom: settings.settings.customShortcutStrokes)
            .disabled(workspace == nil)

            Button("Split Horizontally") {
                workspace?.splitActivePane(axis: .horizontal)
            }
            .shortcut(AppShortcuts.splitHorizontally, custom: settings.settings.customShortcutStrokes)
            .disabled(workspace == nil)

            Divider()

            Button("Close Pane") {
                workspace?.requestCloseActivePane()
            }
            .shortcut(AppShortcuts.closePane, custom: settings.settings.customShortcutStrokes)
            .disabled(workspace == nil)

            Divider()

            Button("Focus Pane Left") { workspace?.focusPane(.left) }
                .shortcut(AppShortcuts.focusPaneLeft, custom: settings.settings.customShortcutStrokes)
                .disabled(workspace == nil)
            Button("Focus Pane Right") { workspace?.focusPane(.right) }
                .shortcut(AppShortcuts.focusPaneRight, custom: settings.settings.customShortcutStrokes)
                .disabled(workspace == nil)
            Button("Focus Pane Up") { workspace?.focusPane(.up) }
                .shortcut(AppShortcuts.focusPaneUp, custom: settings.settings.customShortcutStrokes)
                .disabled(workspace == nil)
            Button("Focus Pane Down") { workspace?.focusPane(.down) }
                .shortcut(AppShortcuts.focusPaneDown, custom: settings.settings.customShortcutStrokes)
                .disabled(workspace == nil)
        }

        // briefs/2 "Menü Çubuğu": Termora / File / Edit / View / **Shell** / Window / Help.
        // Shell menüsü oturumun kendisine dokunan işlemleri toplar; panel ve sekme düzeni
        // kendi menülerinde kalır.
        CommandMenu("Shell") {
            Button(AppShortcuts.clearScreen.title) {
                workspace?.clearActivePane()
            }
            .shortcut(AppShortcuts.clearScreen, custom: settings.settings.customShortcutStrokes)
            .disabled(workspace == nil)

            Divider()

            Button(AppShortcuts.restartSession.title) {
                workspace?.restartActivePaneSession()
            }
            .shortcut(AppShortcuts.restartSession, custom: settings.settings.customShortcutStrokes)
            .disabled(workspace == nil)

            // briefs/3 "Error State" örneğindeki kurtarma yolu: yapılandırılmış shell
            // çalıştırılamadığında kullanıcı login shell'e dönebilmeli.
            Button(AppShortcuts.restartWithDefaultShell.title) {
                workspace?.restartActivePaneSession(forceDefaultShell: true)
            }
            .shortcut(AppShortcuts.restartWithDefaultShell, custom: settings.settings.customShortcutStrokes)
            .disabled(workspace == nil)
        }

        CommandMenu("Tab") {
            Button("Next Tab") { workspace?.nextTab() }
                .shortcut(AppShortcuts.nextTab, custom: settings.settings.customShortcutStrokes)
                .disabled(workspace == nil)
            Button("Previous Tab") { workspace?.previousTab() }
                .shortcut(AppShortcuts.previousTab, custom: settings.settings.customShortcutStrokes)
                .disabled(workspace == nil)

            Divider()

            ForEach(Array(AppShortcuts.tabSelection.enumerated()), id: \.element.id) { index, shortcut in
                Button(shortcut.title) {
                    workspace?.selectTab(at: index)
                }
                .shortcut(shortcut, custom: settings.settings.customShortcutStrokes)
                .disabled(workspace == nil)
            }
        }

        // briefs/2 "Menü Çubuğu" Help menüsünü sayıyor. Ürünün henüz dokümantasyon sitesi
        // yok (briefs/2 "Faz 6"), o yüzden burada yalnız gerçekten çalışan bir öğe var:
        // varsayılan "Termora Help" öğesi olmayan bir kitapçığı açmaya çalışıp hata
        // penceresi gösterirdi.
        CommandGroup(replacing: .help) {
            Button("Report an Issue…") {
                NSWorkspace.shared.open(TermoraLinks.newIssue)
            }
        }
    }
}

/// Uygulamanın dışarı açtığı adresler. Tek yerde durur ki menü, About ve hata raporlama
/// aynı hedefi göstersin.
enum TermoraLinks {
    static let repository = URL(string: "https://github.com/ahmetbarut/termora")!
    static let newIssue = URL(string: "https://github.com/ahmetbarut/termora/issues/new")!
    static let releases = URL(string: "https://github.com/ahmetbarut/termora/releases")!
}
