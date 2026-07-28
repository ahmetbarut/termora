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
    ///   - docker: çalışan container'lar ve compose servisleri (briefs/2 "Docker
    ///     Entegrasyonu"). `nil` ise Docker kategorisi hiç çizilmez. Aynı kural: liste
    ///     BURADA yüklenmez — `ensureLoaded()` bir süreç başlatıyor ve ekranın
    ///     `onAppear`'ına aittir.
    static func items(workspace: WorkspaceViewModel,
                      settings: SettingsStore,
                      themes: ThemeStore,
                      ssh: SSHHostStore? = nil,
                      folders: RecentFoldersStore? = nil,
                      docker: DockerStore? = nil,
                      currentDirectory: String? = nil,
                      home: String = NSHomeDirectory(),
                      now: @escaping @MainActor () -> Date = Date.init,
                      openSettings: @escaping @MainActor () -> Void) -> [CommandPaletteItem] {
        actions(workspace: workspace)
            + favoriteCommands(folders: folders, currentDirectory: currentDirectory, now: now)
            + workspaceCommands(workspace: workspace)
            + sshCommands(workspace: workspace, ssh: ssh, now: now)
            + folderCommands(workspace: workspace, folders: folders, home: home, now: now)
            + dockerCommands(workspace: workspace, docker: docker)
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

    // MARK: - Docker (briefs/2 "Docker Entegrasyonu")

    /// Çalışan container'lar ve compose servisleri. Shell açma ve log gösterme YENİ
    /// SEKMEDE `docker` çalıştırır; yeniden başlatma önce ONAY ister.
    ///
    /// Komutlar her zaman container KİMLİĞİYLE kurulur (onaltılık): kullanıcının
    /// container adına yazdığı hiçbir şey argüman sınırını geçemez.
    private static func dockerCommands(workspace: WorkspaceViewModel,
                                       docker: DockerStore?) -> [CommandPaletteItem] {
        guard let docker else { return [] }

        // Brief: docker kurulu değilse özellik DÜRÜSTÇE söylesin, çökmesin. Ölü bir satır
        // bırakmamak için Enter yeniden kontrol eder — kullanıcı bu arada kurmuş olabilir.
        if docker.availability == .notFound {
            return [
                // Başlık `DockerStore.notFoundMessage`'ten TÜRETİLMEZ: o bir durum cümlesi
                // ("Docker not found"), bu ise bir komut satırı ve palet başlıkları
                // başlık düzenindedir ("Open Settings", "Close Tab").
                CommandPaletteItem(id: "docker.unavailable",
                                   title: "Docker Not Found — Check Again",
                                   category: .docker,
                                   symbolName: "exclamationmark.triangle",
                                   accessibilityLabel: """
                                       Docker was not found on this Mac. \
                                       Runs the check again.
                                       """) {
                    Task { await docker.refresh() }
                },
            ]
        }

        guard let executablePath = docker.executablePath else { return [] }
        let running = docker.containers.filter(\.isRunning)

        return running.flatMap { container in
            containerCommands(container,
                              workspace: workspace,
                              docker: docker,
                              executablePath: executablePath)
        } + DockerComposeService.services(in: running).map { service in
            CommandPaletteItem(id: "docker.compose.shell.\(service.id)",
                               title: "Open Shell in Service “\(service.displayName)”",
                               category: .docker,
                               symbolName: "square.stack.3d.up",
                               accessibilityLabel: """
                                   Open a shell in the Compose service \
                                   \(service.service) of project \(service.project)
                                   """) {
                workspace.newTab(profile: DockerLaunch.profile(
                    name: service.service,
                    executablePath: executablePath,
                    arguments: DockerCommand.composeOpenShell(configFiles: service.configFiles,
                                                              project: service.project,
                                                              service: service.service)))
            }
        }
    }

    private static func containerCommands(_ container: DockerContainer,
                                          workspace: WorkspaceViewModel,
                                          docker: DockerStore,
                                          executablePath: String) -> [CommandPaletteItem] {
        let name = container.displayName
        return [
            CommandPaletteItem(id: "docker.shell.\(container.id)",
                               title: "Open Shell in “\(name)”",
                               category: .docker,
                               symbolName: "terminal",
                               accessibilityLabel: "Open a shell in the container \(name)") {
                workspace.newTab(profile: DockerLaunch.profile(
                    name: name,
                    executablePath: executablePath,
                    arguments: DockerCommand.openShell(containerID: container.id)))
            },

            CommandPaletteItem(id: "docker.logs.\(container.id)",
                               title: "Show Logs for “\(name)”",
                               category: .docker,
                               symbolName: "text.alignleft",
                               accessibilityLabel: "Follow the logs of the container \(name)") {
                workspace.newTab(profile: DockerLaunch.profile(
                    name: "\(name) logs",
                    executablePath: executablePath,
                    arguments: DockerCommand.logs(containerID: container.id)))
            },

            // Başlıktaki "…" bu satırın ÖNCE soracağını söyler (macOS konvansiyonu).
            CommandPaletteItem(id: "docker.restart.\(container.id)",
                               title: "Restart “\(name)”…",
                               category: .docker,
                               symbolName: "arrow.clockwise",
                               accessibilityLabel: """
                                   Restart the container \(name). Asks for confirmation first.
                                   """) {
                // briefs/2: etkili işlem — onay alınmadan hiçbir komut çalışmaz.
                workspace.requestDockerRestart(containerName: name) {
                    Task { await docker.restart(containerID: container.id) }
                }
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
