import Foundation

/// Komut paletinin içeriği: BUGÜN uygulamada karşılığı olan her komut.
///
/// Brief 3 ayrıca Folders, SSH ve AI Actions kategorilerini sayar; bu yetenekler henüz yok,
/// bu yüzden palet onları hiç çizmez (boş kategori göstermek yerine). İlgili özellikler
/// geldiğinde komutları buraya eklenir.
@MainActor
enum CommandPaletteCatalog {

    static func items(workspace: WorkspaceViewModel,
                      settings: SettingsStore,
                      themes: ThemeStore,
                      openSettings: @escaping @MainActor () -> Void) -> [CommandPaletteItem] {
        actions(workspace: workspace)
            + workspaceCommands(workspace: workspace)
            + settingsCommands(openSettings: openSettings)
            + themeCommands(settings: settings, themes: themes)
    }

    // MARK: - Actions

    private static func actions(workspace: WorkspaceViewModel) -> [CommandPaletteItem] {
        [
            CommandPaletteItem(id: "action.newTab",
                               title: "New Tab",
                               category: .actions,
                               symbolName: "plus.square",
                               shortcut: "⌘T") { workspace.newTab() },

            CommandPaletteItem(id: "action.closeTab",
                               title: "Close Tab",
                               category: .actions,
                               symbolName: "xmark.square",
                               shortcut: "⌘W") {
                guard let activeTabID = workspace.activeTabID else { return }
                workspace.requestCloseTab(id: activeTabID)
            },

            CommandPaletteItem(id: "action.splitVertically",
                               title: "Split Vertically",
                               category: .actions,
                               symbolName: "rectangle.split.2x1",
                               shortcut: "⌘D") { workspace.splitActivePane(axis: .vertical) },

            CommandPaletteItem(id: "action.splitHorizontally",
                               title: "Split Horizontally",
                               category: .actions,
                               symbolName: "rectangle.split.1x2",
                               shortcut: "⇧⌘D") { workspace.splitActivePane(axis: .horizontal) },

            CommandPaletteItem(id: "action.closePane",
                               title: "Close Pane",
                               category: .actions,
                               symbolName: "xmark.rectangle",
                               shortcut: "⇧⌘W") { workspace.requestCloseActivePane() },

            CommandPaletteItem(id: "action.nextTab",
                               title: "Next Tab",
                               category: .actions,
                               symbolName: "arrow.right",
                               shortcut: "⇧⌘]") { workspace.nextTab() },

            CommandPaletteItem(id: "action.previousTab",
                               title: "Previous Tab",
                               category: .actions,
                               symbolName: "arrow.left",
                               shortcut: "⇧⌘[") { workspace.previousTab() },

            CommandPaletteItem(id: "action.find",
                               title: "Find…",
                               category: .actions,
                               symbolName: "magnifyingglass",
                               shortcut: "⌘F") { workspace.toggleSearchBar() },

            CommandPaletteItem(id: "action.findNext",
                               title: "Find Next",
                               category: .actions,
                               symbolName: "chevron.down",
                               shortcut: "⌘G") { workspace.findNextMatch() },

            CommandPaletteItem(id: "action.findPrevious",
                               title: "Find Previous",
                               category: .actions,
                               symbolName: "chevron.up",
                               shortcut: "⇧⌘G") { workspace.findPreviousMatch() },

            CommandPaletteItem(id: "action.focusPaneLeft",
                               title: "Focus Pane Left",
                               category: .actions,
                               symbolName: "arrow.left.square",
                               shortcut: "⌥⌘←") { workspace.focusPane(.left) },

            CommandPaletteItem(id: "action.focusPaneRight",
                               title: "Focus Pane Right",
                               category: .actions,
                               symbolName: "arrow.right.square",
                               shortcut: "⌥⌘→") { workspace.focusPane(.right) },

            CommandPaletteItem(id: "action.focusPaneUp",
                               title: "Focus Pane Up",
                               category: .actions,
                               symbolName: "arrow.up.square",
                               shortcut: "⌥⌘↑") { workspace.focusPane(.up) },

            CommandPaletteItem(id: "action.focusPaneDown",
                               title: "Focus Pane Down",
                               category: .actions,
                               symbolName: "arrow.down.square",
                               shortcut: "⌥⌘↓") { workspace.focusPane(.down) },
        ]
    }

    // MARK: - Workspaces

    /// Kayıtlı workspace'ler (brief 3, "Sonuç kategorileri → Workspaces"). Enter kaydı açar.
    ///
    /// Depo `WorkspaceViewModel` üzerinden okunur: pencere hangi listeyi açıyorsa palet de
    /// onu gösterir. Depo bağlı değilse (workspace ekranı olmayan bağlamlar) kategori hiç
    /// çizilmez — boş bir "Workspaces" başlığı göstermek yerine.
    ///
    /// Komut, ONAY akışını atlamaz: `openWorkspace` başlangıç komutu olan güvenilmez bir
    /// kaydı çalıştırmaz, önce onay diyaloğunu kurar (briefs/2 güvenlik kuralı).
    private static func workspaceCommands(workspace: WorkspaceViewModel) -> [CommandPaletteItem] {
        (workspace.workspaces?.workspaces ?? []).map { saved in
            CommandPaletteItem(id: "workspace.\(saved.id.uuidString)",
                               title: WorkspaceCardModel.displayName(saved.name),
                               category: .workspaces,
                               symbolName: CommandPaletteCategory.workspaces.symbolName) {
                workspace.openWorkspace(saved)
            }
        }
    }

    // MARK: - Settings

    private static func settingsCommands(
        openSettings: @escaping @MainActor () -> Void) -> [CommandPaletteItem] {
        [
            CommandPaletteItem(id: "settings.open",
                               title: "Open Settings",
                               category: .settings,
                               symbolName: "gearshape",
                               shortcut: "⌘,") { openSettings() },
        ]
    }

    // MARK: - Themes

    private static func themeCommands(settings: SettingsStore,
                                      themes: ThemeStore) -> [CommandPaletteItem] {
        themes.themes.map { theme in
            CommandPaletteItem(id: "theme.\(theme.id)",
                               title: theme.name,
                               category: .themes,
                               symbolName: "paintpalette") {
                settings.settings.themeID = theme.id
            }
        }
    }
}
