import AppKit
import Combine
import SwiftUI

/// Pencere kabuğunun ölçüleri (brief 3, "Küçük Pencere Davranışı").
enum WindowLayout {
    /// Brief'teki alt sınır: bu boyutta sekme çubuğu ve terminal birlikte kullanılabilir kalır.
    static let minWidth: CGFloat = 720
    static let minHeight: CGFloat = 480

    static var minimumSize: CGSize { CGSize(width: minWidth, height: minHeight) }

    /// AI paneli açıkken pencere, panelin genişliği KADAR büyür.
    ///
    /// briefs/3 iki şey ister: "Terminal alanı korunmalı" ve "AI paneli terminal
    /// kullanımını engellememeli". Alt sınır sabit kalsaydı 720 pt'lik bir pencerede
    /// panel terminalin yarısını yerdi; bu yüzden panel açılırken pencere büyür ve
    /// terminal tanıdık alt sınırını korur.
    /// Sidebar de aynı kuralı izler (briefs/3 "Küçük Pencere Davranışı": *Terminal alanı
    /// korunmalı*): açıldığında pencerenin alt sınırı sidebar'ın asgari genişliği kadar
    /// büyür, böylece terminal 720 pt'lik tanıdık alanını kaybetmez.
    static func minWidth(withAIPanel isPresented: Bool, withSidebar isSidebarVisible: Bool = false) -> CGFloat {
        var width = minWidth
        if isPresented { width += AIPanelLayout.minWidth }
        if isSidebarVisible { width += CGFloat(SettingsLimits.sidebarWidthRange.lowerBound) }
        return width
    }

    /// briefs/3 "Pencere Yönetimi": boyut ve konum, oturum geri yükleme KAPALIYKEN de
    /// hatırlanmalı. AppKit'in kendi mekanizması kullanılır — kayıt yeri `NSUserDefaults`'tur,
    /// ikinci bir pencere açıldığında AppKit onu kaydedilen çerçevenin üzerine basmak yerine
    /// kademelendirir.
    static let frameAutosaveName = "TermoraMainWindow"
}

/// Ana pencere sahnesi. Kimliği geri yüklemede gerekir: ilk pencere, kayıttaki DİĞER
/// pencereleri `openWindow(id:)` ile açar.
enum MainWindowScene {
    static let groupID = "termora.main"
}

struct MainWindowView: View {
    private let services: AppServices
    @State private var workspace: WorkspaceViewModel

    /// Pencere kapatma delegesi. `@State` tutulur çünkü `NSWindow.delegate` zayıftır;
    /// başka bir sahibi olmazsa ilk yerleşimden hemen sonra yok olur.
    @State private var closeCoordinator = WindowCloseCoordinator()

    /// Komut paleti pencere başına bir tanedir; ⌘K menüden, ⌘⇧P dinleyiciden gelir.
    /// Onay diyaloğundaki "Always trust this workspace" seçimi.
    @State private var trustLaunchedWorkspace = false
    @State private var palette = CommandPaletteModel()
    @State private var paletteHotkey = CommandPaletteHotkeyMonitor()

    /// AI paneli pencere başınadır: konuşma bu pencerenin terminaline aittir ve başka
    /// bir pencerede görünmemelidir (briefs/2 "Gizlilik" — konuşma diske de yazılmaz).
    @State private var ai: AIPanelModel
    /// Köprü `AIPanelModel` tarafından ZAYIF tutulur; sahibi burasıdır.
    @State private var terminalBridge: WorkspaceTerminalBridge

    /// Sekme başlığı artık çalışan komutu da gösteriyor; komutun başlaması/bitmesi ne OSC
    /// başlığını ne de cwd'yi değiştirdiği için `sessionTitleDigest` değişmez. Başlığın
    /// gerçeği yansıtması için saniyede bir tazelenir (durum çubuğuyla aynı bütçe).
    /// `@State`: `Timer.publish(...)` her `body` değerlendirmesinde yeni bir publisher üretir.
    @State private var titleTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Bu pencerenin açılışta kuyruktan aldığı kayıt; yoksa nil (taze pencere).
    @State private var restoredWindow: SessionWindowSnapshot?
    /// Açılış hazırlığı (kayıt alma, ilk sekme, ek pencereler) pencere başına BİR kez çalışır.
    @State private var hasPreparedWindow = false
    /// Kayıtlı çerçeve bir kez uygulanır; sonrasında pencerenin boyutu kullanıcınındır.
    @State private var hasPlacedWindow = false

    @Environment(\.openWindow) private var openWindow
    /// Sidebar'daki Settings satırları paletle aynı yolu kullanır.
    @Environment(\.openSettings) private var openSettings

    @MainActor
    init(services: AppServices) {
        self.services = services
        let workspace = WorkspaceViewModel(
            sessionManager: services.sessionManager,
            settings: services.settings,
            profiles: services.profiles,
            // Depo BAĞLANMAZSA `workspace.workspaces` nil kalır ve buna bağlı üç davranış
            // sessizce ölür: paletin Workspaces kategorisi hiç çizilmez, `lastOpenedAt`
            // damgalanmaz ve "Always trust this workspace" seçimi diske yazılmaz.
            workspaces: services.workspaces
        )
        _workspace = State(initialValue: workspace)

        let bridge = WorkspaceTerminalBridge(workspace: workspace,
                                             sessionManager: services.sessionManager)
        let panel = AIPanelModel(provider: services.aiProvider,
                                 settings: services.settings,
                                 catalog: services.aiCatalog)
        panel.bridge = bridge
        _terminalBridge = State(initialValue: bridge)
        _ai = State(initialValue: panel)
    }

    var body: some View {
        // Panel terminalin ÜZERİNE binmez, YANINDA durur (briefs/3: "AI paneli terminal
        // kullanımını engellememeli"). Kardeş görünüm olduğu için oturumlar okumaya ve
        // çalışmaya devam eder; klavye odağı panele girmedikçe terminaldedir.
        HStack(spacing: 0) {
            // briefs/3 "Sidebar": kapalıyken ikon şeridi BIRAKMAZ, tamamen kaybolur.
            if services.settings.settings.isSidebarVisible {
                SidebarView(sections: SidebarCatalog.sections(from: paletteItems()),
                            onDismiss: { services.settings.settings.isSidebarVisible = false })
                    .frame(width: services.settings.settings.sidebarWidth)
                    .transition(.move(edge: .leading))
                SidebarResizeHandle(width: Binding(
                    get: { services.settings.settings.sidebarWidth },
                    set: { services.settings.settings.sidebarWidth = $0 }
                ))
            }
            terminalColumn
            if ai.isPresented {
                Divider()
                AIPanelView(model: ai)
                    .frame(minWidth: AIPanelLayout.minWidth,
                           idealWidth: AIPanelLayout.defaultWidth,
                           maxWidth: AIPanelLayout.maxWidth)
                    .transition(.move(edge: .trailing))
            }
        }
        .frame(minWidth: WindowLayout.minWidth(withAIPanel: ai.isPresented,
                                               withSidebar: services.settings.settings.isSidebarVisible),
               minHeight: WindowLayout.minHeight)
        .motionAnimation(.panel, value: ai.isPresented)
        .motionAnimation(.panel, value: services.settings.settings.isSidebarVisible)
        .focusedSceneValue(\.aiPanel, ai)
        .onChange(of: ai.isPresented) { _, isPresented in
            // Panel açıldığında gönderilecek bağlam TAZE olmalı; kapanırken klavye
            // terminale geri döner.
            if isPresented { ai.refreshContext() } else { focusActiveTerminal() }
        }
        // Aktif sekme/panel değişince bağlam da değişti: gösterge eskisini göstermemeli.
        .onChange(of: workspace.activeTabID) { _, _ in
            if ai.isPresented { ai.refreshContext() }
        }
        // Terminal sağ tık menüsündeki "Explain with AI" (briefs/3). Menü yalnız bir jeton
        // bırakır; paneli açan ve soruyu soran yer burasıdır — View ▸ Explain Selection
        // (⌘⇧E) ile TAM AYNI yol, böylece iki giriş noktası ayrışamaz.
        .onChange(of: workspace.explainSelectionRequest) { _, request in
            guard request != nil else { return }
            Task { await ai.openAndExplainSelection() }
        }
        // Palet terminalin ÜZERİNDE bir katmandır: oturumlar okumaya/çalışmaya devam eder
        // (brief 3: "Komut paleti açıldığında terminal oturumu durmamalıdır").
        .overlay(alignment: .top) {
            if palette.isPresented {
                CommandPaletteView(model: palette,
                                   workspace: workspace,
                                   settings: services.settings,
                                   themes: services.themes,
                                   ssh: services.sshHosts,
                                   folders: services.recentFolders,
                                   docker: DockerStore.shared,
                                   ai: ai,
                                   currentDirectory: currentWorkingDirectory())
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: palette.isPresented)
        .focusedSceneValue(\.commandPalette, palette)
        .onChange(of: palette.isPresented) { _, isPresented in
            // Palet kapanınca klavye terminale geri döner; yoksa tuşlar hiçbir yere gitmez.
            if !isPresented { focusActiveTerminal() }
        }
        .onDisappear { paletteHotkey.detach() }
        .onAppear {
            // Sistemin otomatik pencere sekmelerini kapat: kendi sekme çubuğumuzu çiziyoruz,
            // aksi hâlde macOS "Show Tab Bar" öğesini ekler ve ⌘T ile çakışır.
            NSWindow.allowsAutomaticWindowTabbing = false
            prepareWindow()
            // Uygulama bir `termora://` bağlantısıyla ya da Finder servisiyle AÇILDIYSA
            // istek, bu pencere görünmeden park edilmiş olabilir; `onChange` o değişimi
            // kaçırır. Kuyruk açılışta da boşaltılır.
            drainFolderOpenRequest()
        }
        .onChange(of: workspace.sessionTitleDigest, initial: true) { _, _ in
            workspace.syncAutomaticTitles()
        }
        .onReceive(titleTicker) { _ in
            workspace.syncAutomaticTitles()
        }
        .focusedSceneValue(\.workspace, workspace)
        .background(
            WindowAccessor { window in
                closeCoordinator.attach(window: window, workspace: workspace)
                // Ayar kapalıyken pencere kapanışı hiçbir şey YAZMAZ: kapalı bir özellik
                // kullanıcının çalışma dizinlerini diske bırakmamalı (briefs/2 "Gizlilik").
                closeCoordinator.recordSession = { snapshot in
                    guard services.settings.settings.restoresPreviousSession else { return }
                    services.sessionRestore.record(snapshot)
                }
                paletteHotkey.attach(window: window) { palette.toggle() }
                // "Use Current Layout" bu PENCERENİN düzenini okusun: kayıt pencereye
                // bağlıdır, böylece Ayarlar key iken ön plandaki terminal seçilebilir.
                services.registerLayoutProvider(for: window) {
                    workspace.captureWorkspace(name: "", directory: "").tabs
                }
                placeWindowIfNeeded(window)
            }
        )
        .confirmationDialog(
            workspace.pendingCloseTitle,
            isPresented: pendingCloseBinding,
            titleVisibility: .visible
        ) {
            // Belirsiz "OK"/"Yes" yerine eylemin adı (brief 3, "Uygulama Metin Dili").
            Button(workspace.pendingCloseConfirmLabel, role: .destructive) {
                workspace.confirmPendingClose()
            }
            Button("Cancel", role: .cancel) { workspace.cancelPendingClose() }
        } message: {
            Text(workspace.pendingCloseMessage)
        }
        // Ayarlar penceresi kendi terminal penceresine sahip olmadığı için açılış isteğini
        // servis katmanına park eder; onu buradan alıp bu pencerede açıyoruz.
        .onChange(of: services.workspaceOpenRequest?.id) { _, _ in
            guard let request = services.workspaceOpenRequest else { return }
            services.workspaceOpenRequest = nil
            workspace.openWorkspace(request)
        }
        // Ayarlar ▸ SSH'tan gelen bağlanma isteği: açık sekmelere DOKUNMAZ, yeni sekme açar.
        .onChange(of: services.sshConnectRequest?.id) { _, _ in
            guard let target = services.sshConnectRequest else { return }
            services.sshConnectRequest = nil
            CommandPaletteCatalog.connect(to: target,
                                          workspace: workspace,
                                          ssh: services.sshHosts,
                                          at: Date())
        }
        // `termora://open` / Finder ▸ Services isteği (briefs/2 "Hızlı Açma").
        .onChange(of: services.folderOpenRequest?.id) { _, _ in
            drainFolderOpenRequest()
        }
        // Son kullanılan klasörler kullanıcının AÇTIĞI klasörleri saklar. Workspace açılışı
        // İSTEK anında değil, GERÇEKTEN açıldığında yazılır: başlangıç komutu onayını iptal
        // eden bir kullanıcı hiçbir klasör açmamıştır.
        .onChange(of: workspace.openWorkspaceID) { _, openedID in
            guard let openedID,
                  let opened = services.workspaces.workspaces.first(where: { $0.id == openedID })
            else { return }
            services.recentFolders.recordOpen(opened.directory, at: Date())
        }
        .confirmationDialog(
            WorkspaceLaunchPrompt.title(workspaceName: workspace.pendingWorkspaceLaunch?.workspace.name ?? ""),
            isPresented: pendingLaunchBinding,
            titleVisibility: .visible
        ) {
            Button(WorkspaceLaunchPrompt.runTitle) {
                workspace.confirmWorkspaceLaunch(trustFromNowOn: trustLaunchedWorkspace)
            }
            Button(WorkspaceLaunchPrompt.skipTitle) {
                workspace.openWorkspaceWithoutStartupCommands()
            }
            Button(WorkspaceLaunchPrompt.cancelTitle, role: .cancel) {
                workspace.cancelWorkspaceLaunch()
            }
        } message: {
            Text(pendingLaunchMessage)
        }
        // Docker yeniden başlatma onayı (briefs/2: "Silme, durdurma veya yeniden başlatma
        // gibi etkili işlemlerde kullanıcıdan onay alınmalıdır"). Komut YALNIZ buradan
        // onaylandığında çalışır; `requestDockerRestart` tek başına hiçbir şey çalıştırmaz.
        .confirmationDialog(
            workspace.pendingDockerActionTitle,
            isPresented: pendingDockerBinding,
            titleVisibility: .visible
        ) {
            Button(workspace.pendingDockerActionConfirmLabel, role: .destructive) {
                workspace.confirmPendingDockerAction()
            }
            Button(DockerActionPrompt.cancelLabel, role: .cancel) {
                workspace.cancelPendingDockerAction()
            }
        } message: {
            Text(workspace.pendingDockerActionMessage)
        }
    }

    /// Pencerenin terminal sütunu: sekme çubuğu, arama, terminal ve durum çubuğu.
    /// AI paneli bunun YANINA eklenir, üstüne değil.
    private var terminalColumn: some View {
        VStack(spacing: 0) {
            TabBarView(workspace: workspace)
            Divider()
            if let tab = workspace.activeTab, tab.isSearchVisible {
                SearchBarView(tab: tab, workspace: workspace)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            terminalContent
            if workspace.isStatusBarVisible {
                StatusBarView(workspace: workspace)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// İki diyalog aynı anda açılmamalı: kapatma onayı önceliklidir (kullanıcı zaten
    /// bir şeyi kapatmaya çalışıyordu), workspace açılışı onun arkasında bekler.
    private var pendingLaunchBinding: Binding<Bool> {
        Binding(
            get: {
                WorkspaceDialogPresentation.current(
                    hasPendingClose: workspace.pendingClose != nil,
                    hasPendingLaunch: workspace.pendingWorkspaceLaunch != nil
                ) == .startupCommands
            },
            set: { isPresented in
                if !isPresented { workspace.cancelWorkspaceLaunch() }
            }
        )
    }

    private var pendingLaunchMessage: String {
        guard let launch = workspace.pendingWorkspaceLaunch else { return "" }
        return WorkspaceLaunchPrompt.messageBody(commands: launch.commands)
    }

    // MARK: - Açılış

    /// Pencerenin açılış hazırlığı (briefs/2 "Oturum Geri Yükleme").
    ///
    /// Kuyruk `AppServices` tarafından ilk pencere görünmeden hazırlanır ve ayar kapalıysa
    /// BOŞTUR — burada ayrıca bir kontrol yoktur, tek karar noktası odur.
    private func prepareWindow() {
        guard !hasPreparedWindow else { return }
        hasPreparedWindow = true

        if let saved = services.sessionRestore.claimWindow() {
            restoredWindow = saved
            workspace.restoreSession(from: saved)
        }
        // Geri yükleme yoksa ya da kayıttaki her sekme düştüyse pencere boş kalmaz.
        if workspace.tabs.isEmpty { workspace.newTab() }

        // Kayıtta birden fazla pencere varsa kalanları İLK pencere açar; sayı bir kez
        // verilir, yoksa geri yükleme için açılan her pencere yeniden pencere isterdi.
        // Sayı ŞİMDİ alınır (hak bir kez verilir), pencereler bir sonraki tura bırakılır:
        // görünüm güncellenirken kardeş pencere açmak bu turu gereksiz uzatır.
        let additional = services.sessionRestore.claimAdditionalWindowCount()
        guard additional > 0 else { return }
        DispatchQueue.main.async {
            for _ in 0..<additional { openWindow(id: MainWindowScene.groupID) }
        }
    }

    /// Pencereyi yerleştirir. Sıra önemli: önce AppKit'in hatırladığı çerçeve (ayar kapalıyken
    /// de çalışan briefs/3 davranışı), sonra —varsa— bu pencerenin kayıtlı çerçevesi.
    ///
    /// Tam ekran durumu geri yüklenmez (bkz. `SessionWindowPlacement.shouldEnterFullScreen`);
    /// tam ekran ÖNCESİ çerçeve uygulanır, böylece pencere tanıdık boyutunda gelir.
    private func placeWindowIfNeeded(_ window: NSWindow) {
        // Hatırlanan çerçeveyi tek bir pencere sahiplenir. Aynı autosave adını her pencereye
        // vermek hepsini üst üste bindirirdi; ikinci ve sonraki pencereler SwiftUI'nin
        // kademelendirmesiyle açılır.
        let alreadyClaimed = NSApp.windows.contains {
            $0 !== window && $0.isVisible && $0.frameAutosaveName == WindowLayout.frameAutosaveName
        }
        if !alreadyClaimed, window.frameAutosaveName != WindowLayout.frameAutosaveName {
            window.setFrameAutosaveName(WindowLayout.frameAutosaveName)
        }

        // Kayıtlı çerçeve ancak açılış hazırlığı bittiğinde bilinir; `WindowAccessor` bu
        // kancayı `onAppear`'dan ÖNCE de çağırabildiği için hazırlık beklenir.
        guard hasPreparedWindow, !hasPlacedWindow else { return }
        hasPlacedWindow = true
        guard let restored = restoredWindow else { return }

        if let frame = SessionWindowPlacement.frame(for: restored.frame,
                                                    visibleScreenFrames: NSScreen.screens.map(\.visibleFrame),
                                                    minimumSize: WindowLayout.minimumSize) {
            window.setFrame(frame, display: true)
        }
        if SessionWindowPlacement.shouldEnterFullScreen(restoring: restored) {
            window.toggleFullScreen(nil)
        }
    }

    // MARK: - Hızlı açma (briefs/2)

    /// Park edilmiş klasör açma isteğini alır ve her klasör için YENİ BİR SEKME açar.
    ///
    /// İstek ÖNCE temizlenir: birden fazla pencere aynı turda uyanabilir ve temizlenmemiş
    /// bir istek her pencerede bir sekme açardı. Açık sekmelere dokunulmaz.
    private func drainFolderOpenRequest() {
        guard let request = services.folderOpenRequest else { return }
        services.folderOpenRequest = nil
        let now = Date()
        for path in request.paths {
            CommandPaletteCatalog.openFolder(at: path,
                                             workspace: workspace,
                                             folders: services.recentFolders,
                                             at: now)
        }
    }

    /// Aktif panelin çalışma dizini. Önce süreç sorulur (kullanıcı `cd` yapmış olabilir),
    /// okunamazsa oturumun bilinen dizinine düşülür.
    ///
    /// Yalnız palet çizilirken çağrılır; palet kapalıyken hiçbir süreç sorgusu olmaz.
    private func currentWorkingDirectory() -> String? {
        guard let tab = workspace.activeTab,
              let sessionID = tab.root.sessionID(ofPane: tab.activePaneID) else { return nil }
        let probed = services.sessionManager.shellPID(sessionID: sessionID)
            .flatMap { ProcessProbe.currentWorkingDirectory(pid: $0) }
        return probed ?? services.sessionManager.session(id: sessionID)?.workingDirectory
    }

    /// Sidebar'ın gösterdiği komutlar. Palet ile TAM AYNI kaynaktan üretilir; sidebar
    /// yalnızca `SidebarCatalog` ile kendi kategorilerini ayıklar. İki yüzeyin ayrışması
    /// (paletten açılan bir workspace'in sidebar'da görünmemesi) böylece mümkün değil.
    ///
    /// Yalnız sidebar çiziliyken çağrılır; kapalıyken hiçbir liste kurulmaz.
    private func paletteItems() -> [CommandPaletteItem] {
        CommandPaletteCatalog.items(workspace: workspace,
                                    settings: services.settings,
                                    themes: services.themes,
                                    ssh: services.sshHosts,
                                    folders: services.recentFolders,
                                    docker: DockerStore.shared,
                                    ai: ai,
                                    currentDirectory: currentWorkingDirectory(),
                                    openSettings: { openSettings() })
    }

    /// Klavye odağını aktif panelin terminaline geri verir.
    private func focusActiveTerminal() {
        guard let tab = workspace.activeTab,
              let sessionID = tab.root.sessionID(ofPane: tab.activePaneID) else { return }
        services.sessionManager.focusTerminal(sessionID: sessionID)
    }

    private var pendingCloseBinding: Binding<Bool> {
        Binding(
            get: { workspace.pendingClose != nil },
            set: { isPresented in
                if !isPresented { workspace.cancelPendingClose() }
            }
        )
    }

    /// Diyalog dışarıdan kapatılırsa (Esc, pencere değişimi) bekleyen komut SİLİNİR —
    /// aksi hâlde kapanmış bir onay penceresi arkada canlı kalırdı.
    private var pendingDockerBinding: Binding<Bool> {
        Binding(
            get: { workspace.pendingDockerAction != nil },
            set: { isPresented in
                if !isPresented { workspace.cancelPendingDockerAction() }
            }
        )
    }

    @ViewBuilder
    private var terminalContent: some View {
        if let tab = workspace.activeTab {
            GeometryReader { root in
                PaneTreeView(node: tab.root,
                             tabID: tab.id,
                             activePaneID: tab.activePaneID,
                             viewModel: workspace,
                             sessionManager: services.sessionManager)
                    .coordinateSpace(.named(PaneTreeView.coordinateSpaceName))
                    .onPreferenceChange(PaneFramesPreferenceKey.self) { frames in
                        let converted = PaneFrameConverter.appKitFrames(
                            frames, containerHeight: root.size.height)
                        Task { @MainActor in
                            workspace.paneFrames = converted
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear
        }
    }
}
