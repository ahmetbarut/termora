import Foundation

/// Komut paletinin içeriği: BUGÜN uygulamada karşılığı olan her komut.
///
/// Brief 3 ayrıca AI Actions kategorisini sayar; o yetenek henüz yok, bu yüzden palet onu
/// hiç çizmez (boş kategori göstermek yerine). İlgili özellik geldiğinde komutları buraya
/// eklenir.
@MainActor
enum CommandPaletteCatalog {

    /// - Parameters:
    ///   - ssh: kayıtlı SSH profilleri + `~/.ssh/config` hostları. `nil` ise SSH
    ///     kategorisi hiç çizilmez. Depo BURADA yüklenmez: `items` her çizimde çağrılır ve
    ///     çizim sırasında dosya okuyup durum yazmak SwiftUI güncelleme döngüsü doğurur;
    ///     `ensureConfigHostsLoaded()` çağrısı ekranın `onAppear`'ına aittir.
    ///   - folders: son kullanılan + favori klasörler (briefs/2 "Hızlı Açma"). `nil` ise
    ///     Folders kategorisi hiç çizilmez. Aynı kural: `refreshAvailability()` diske
    ///     bakar ve ekranın `onAppear`'ına aittir, buraya değil.
    ///   - currentDirectory: aktif panelin çalışma dizini; favoriye alma komutu buna
    ///     dayanır. Bilinmiyorsa komut hiç görünmez. Kapanış DEĞİL düz değerdir: dizin
    ///     palet açılırken bir kez okunur — palet açıkken kullanıcı zaten `cd` yapamaz ve
    ///     kapanış her tuş vuruşunda bir süreç sorgusu doğururdu.
    static func items(workspace: WorkspaceViewModel,
                      settings: SettingsStore,
                      themes: ThemeStore,
                      ssh: SSHHostStore? = nil,
                      folders: RecentFoldersStore? = nil,
                      currentDirectory: String? = nil,
                      home: String = NSHomeDirectory(),
                      now: @escaping @MainActor () -> Date = Date.init,
                      openSettings: @escaping @MainActor () -> Void) -> [CommandPaletteItem] {
        actions(workspace: workspace)
            + favoriteCommands(folders: folders, currentDirectory: currentDirectory, now: now)
            + workspaceCommands(workspace: workspace)
            + sshCommands(workspace: workspace, ssh: ssh, now: now)
            + folderCommands(workspace: workspace, folders: folders, home: home, now: now)
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

    // MARK: - SSH

    /// Kayıtlı SSH profilleri ve `~/.ssh/config` hostları (brief 3, "Sonuç kategorileri → SSH").
    /// Enter, hedefi YENİ BİR SEKMEDE `/usr/bin/ssh` ile açar; açık sekmelere dokunulmaz.
    private static func sshCommands(workspace: WorkspaceViewModel,
                                    ssh: SSHHostStore?,
                                    now: @escaping @MainActor () -> Date) -> [CommandPaletteItem] {
        guard let ssh else { return [] }
        return ssh.targets.map { target in
            CommandPaletteItem(id: target.id,
                               title: target.displayName,
                               category: .ssh,
                               symbolName: CommandPaletteCategory.ssh.symbolName) {
                connect(to: target, workspace: workspace, ssh: ssh, at: now())
            }
        }
    }

    /// Bağlantı = kullanıcının kabuğunda `/usr/bin/ssh` çalıştırmak (briefs/2: yeni bir SSH
    /// protokolü uygulanmaz). Komut satırı `SSHCommand` tarafından argüman argüman
    /// alıntılanarak üretilir; burada string birleştirme YOKTUR.
    static func connect(to target: SSHTarget,
                        workspace: WorkspaceViewModel,
                        ssh: SSHHostStore?,
                        at date: Date) {
        workspace.newTab(profile: SSHLaunch.profile(for: target))
        ssh?.recordLaunch(of: target, at: date)
    }

    // MARK: - Folders (briefs/2 "Hızlı Açma")

    /// Favori ve son kullanılan klasörler. Enter, klasörü YENİ BİR SEKMEDE açar; açık
    /// sekmelere dokunulmaz.
    ///
    /// Satır başlığı kısaltılmış YOLDUR (yalnız klasör adı değil): aynı adlı iki proje
    /// klasörü ayırt edilebilsin ve fuzzy arama yol parçalarıyla da eşleşsin diye.
    private static func folderCommands(workspace: WorkspaceViewModel,
                                       folders: RecentFoldersStore?,
                                       home: String,
                                       now: @escaping @MainActor () -> Date) -> [CommandPaletteItem] {
        guard let folders else { return [] }
        return folders.targets.map { target in
            CommandPaletteItem(id: target.id,
                               title: target.title(home: home),
                               category: .folders,
                               symbolName: target.symbolName,
                               accessibilityLabel: target.accessibilityLabel(home: home)) {
                openFolder(at: target.path, workspace: workspace, folders: folders, at: now())
            }
        }
    }

    /// Klasörü yeni sekmede açar ve geçmişe yazar.
    ///
    /// GÜVENLİK: açılış KOMUT ÇALIŞTIRMAZ — profil yalnız `startupDirectory` taşır ve
    /// dizin `startProcess(currentDirectory:)`e verilir, bir kabuk satırına gömülmez.
    /// URL şeması ve Finder servisi de bu tek kapıdan geçer.
    static func openFolder(at path: String,
                           workspace: WorkspaceViewModel,
                           folders: RecentFoldersStore?,
                           at date: Date) {
        workspace.newTab(profile: QuickOpenLaunch.profile(forFolder: path))
        folders?.recordOpen(path, at: date)
    }

    /// Aktif panelin klasörünü favorilere alma / favorilerden çıkarma.
    /// İki karşıt komut aynı anda listelenmez: hangisi anlamlıysa o çizilir.
    private static func favoriteCommands(folders: RecentFoldersStore?,
                                         currentDirectory: String?,
                                         now: @escaping @MainActor () -> Date) -> [CommandPaletteItem] {
        guard let folders, let directory = currentDirectory else { return [] }
        let name = QuickOpenPath.displayName(directory)

        if folders.isFavorite(directory) {
            return [
                CommandPaletteItem(id: "action.removeFolderFromFavorites",
                                   title: "Remove “\(name)” from Favorites",
                                   category: .actions,
                                   symbolName: "star.slash") {
                    folders.removeFavorite(directory)
                },
            ]
        }
        return [
            CommandPaletteItem(id: "action.addFolderToFavorites",
                               title: "Add “\(name)” to Favorites",
                               category: .actions,
                               symbolName: "star") {
                // Favoriye almak bir AÇMA değildir: son kullanılanlar listesine yazmaz.
                folders.addFavorite(directory, at: now())
            },
        ]
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
