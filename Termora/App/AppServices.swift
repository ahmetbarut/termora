//
//  AppServices.swift
//  Termora
//

import AppKit
import Foundation
import Observation
import os

/// Object graph for one running Termora instance, built once by `TermoraApp`.
/// Stores are shared by every window, and so is `SessionManager` — it owns the terminal view
/// cache, so a per-window copy would lose live shells. `WorkspaceViewModel` (M2) is per-window.
@MainActor
@Observable
final class AppServices {
    let settings: SettingsStore
    let themes: ThemeStore
    let profiles: ProfileStore
    /// Saved workspaces. Shared like every other store: the Workspaces settings tab edits the
    /// same list a window reads when it opens one.
    let workspaces: WorkspaceStore
    /// Kayıtlı SSH profilleri + ~/.ssh/config hostları. Ayarlar ekranı ve komut paleti
    /// AYNI listeyi görmeli, bu yüzden depo burada yaşar (paylaşılan tekil değil).
    let sshHosts: SSHHostStore
    let sessionManager: SessionManager
    /// Önceki oturumun kaydı ve açılış kuyruğu (briefs/2 "Oturum Geri Yükleme").
    let sessionRestore: SessionRestoreStore
    /// Son kullanılan ve favori klasörler (briefs/2 "Hızlı Açma"). Diğer depolar gibi
    /// paylaşılır: hangi pencere klasör açarsa açsın geçmiş TEKTİR.
    let recentFolders: RecentFoldersStore

    /// AI sağlayıcısı (briefs/2 "AI Asistanı"). Durumsuzdur ve uç noktayı her istekte
    /// ayarlardan okur, bu yüzden pencereler arasında paylaşılabilir. Konuşma paylaşılmaz:
    /// her pencerenin kendi `AIPanelModel`'i vardır.
    let aiProvider: any AIProviding

    /// Kurulu model listesi. Panel ve Ayarlar ▸ AI aynı listeye bakar.
    let aiCatalog: AIModelCatalog

    /// Settings is a separate scene, so it cannot reach a window's `WorkspaceViewModel`.
    /// It parks the request here; the key window picks it up and clears it. Per-window view
    /// models stay per-window, and a workspace never opens in a window nobody is looking at.
    var workspaceOpenRequest: Workspace?

    /// Ayarlar ▸ SSH'tan gelen bağlanma isteği; anahtar pencere alır ve yeni sekmede açar.
    var sshConnectRequest: SSHTarget?

    /// `termora://open` ya da Finder ▸ Services ▸ Open in Termora'dan gelen klasör açma
    /// isteği. Uygulama düzeyindeki bu kapılar bir pencerenin `WorkspaceViewModel`'ine
    /// erişemez; isteği buraya park ederler, ilk pencere alıp temizler
    /// (`workspaceOpenRequest` ile aynı kalıp — böylece çok pencerede TEK sekme açılır).
    var folderOpenRequest: FolderOpenRequest?

    /// "Use Current Layout" için pencere başına düzen sağlayıcı.
    ///
    /// Tek bir closure YETMEZ: her pencerenin kendi `WorkspaceViewModel`'i var ve tek alan
    /// son AÇILAN pencereyi tutup onu uygulama ömrü boyunca canlı bırakırdı. Ayarlar penceresi
    /// key iken kullanıcının baktığı terminal `NSApp.mainWindow`'dur; düzen ondan okunur.
    @ObservationIgnored private var layoutProviders: [ObjectIdentifier: (window: NSWindow, provide: () -> [WorkspaceTab])] = [:]

    func registerLayoutProvider(for window: NSWindow, provide: @escaping () -> [WorkspaceTab]) {
        layoutProviders[ObjectIdentifier(window)] = (window, provide)
    }

    func unregisterLayoutProvider(for window: NSWindow) {
        layoutProviders.removeValue(forKey: ObjectIdentifier(window))
    }

    /// Ön plandaki terminal penceresinin düzeni; hiçbiri yoksa boş.
    func capturedLayout() -> [WorkspaceTab] {
        // Kapanmış pencerelerin kaydı sızmasın.
        layoutProviders = layoutProviders.filter { $0.value.window.isVisible }
        let front = NSApp.mainWindow ?? NSApp.keyWindow
        if let front, let entry = layoutProviders[ObjectIdentifier(front)] {
            return entry.provide()
        }
        return layoutProviders.values.first?.provide() ?? []
    }

    @ObservationIgnored private var terminationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var launchObserver: (any NSObjectProtocol)?

    /// Servisler menüsü sağlayıcısı. `NSApplication.servicesProvider` bu nesneyi TUTMAZ
    /// (zayıf gibi davranır), sahibi burasıdır.
    @ObservationIgnored private var servicesProvider: TermoraServicesProvider?

    /// `NSAppleEventManager` işleyicisini SAHİPLENMEZ; kayıtlı nesne serbest bırakılırsa
    /// bir sonraki `termora://` olayı ölü bir işaretçiye giderdi. Üretimde `AppServices`
    /// uygulama ömrü boyunca yaşar, ama testler onu defalarca kurup bırakıyor — bu yüzden
    /// EN SON kaydedilen sağlayıcı burada da tutulur.
    @ObservationIgnored private static var registeredEventProvider: TermoraServicesProvider?

    @ObservationIgnored private static let logger =
        Logger(subsystem: "com.ahmetbarut.Termora", category: "QuickOpen")

    /// `NSUpdateDynamicServices()` süreç başına bir kez yeter; testler `AppServices`'i
    /// defalarca kurduğu için sayaç statiktir.
    @ObservationIgnored private static var hasRefreshedServices = false

    init(defaults: UserDefaults = .standard) {
        // Termora draws its own tab bar (M2); leaving the system tabbing on would add a
        // "Show Tab Bar" menu item and fight ⌘T for the same gesture.
        NSWindow.allowsAutomaticWindowTabbing = false

        let settings = SettingsStore(defaults: defaults)
        let themes = ThemeStore()
        let profiles = ProfileStore(defaults: defaults)
        self.settings = settings
        self.themes = themes
        self.profiles = profiles
        self.workspaces = WorkspaceStore(defaults: defaults)
        self.sshHosts = SSHHostStore(defaults: defaults)
        self.recentFolders = RecentFoldersStore(defaults: defaults)
        self.sessionManager = SessionManager(settings: settings, themes: themes, profiles: profiles)

        // Sağlayıcı ÇALIŞMA ANINDA değişebilir (briefs/2: OpenAI, Anthropic, Ollama,
        // OpenAI uyumlu adres). Panel ve katalog tek bir referans tutar; yönlendirici
        // seçili sağlayıcıya delege eder, böylece seçim değişince hiçbiri yeniden
        // kurulmak zorunda kalmaz.
        let aiProvider = AIProviderRouter(settings: settings,
                                          keychain: KeychainService(),
                                          transport: URLSessionAITransport())
        self.aiProvider = aiProvider
        let aiCatalog = AIModelCatalog(provider: aiProvider, settings: settings)
        self.aiCatalog = aiCatalog
        // Ayarlar penceresini kuran `TermoraApp` bu görevin kapsamı dışında; katalog oraya
        // argüman olarak geçirilemediği için burada kaydedilir (bkz. `AIModelCatalog.current`).
        AIModelCatalog.current = aiCatalog

        let sessionRestore = SessionRestoreStore(defaults: defaults)
        self.sessionRestore = sessionRestore
        // Kuyruk İLK pencere görünmeden hazırlanır: `MainWindowView.onAppear` payını buradan
        // alır. Ayar kapalıysa kuyruk boş kalır ve diskteki kayıt hiç okunmaz.
        sessionRestore.prepareRestore(isEnabled: settings.settings.restoresPreviousSession)

        observeApplicationTermination()
        observeRestoreSettingBeingTurnedOff()
        registerExternalEntryPoints()
    }

    // MARK: - Hızlı açma (briefs/2)

    /// Dışarıdan gelen `termora://…` URL'i.
    ///
    /// GÜVENLİK: karar `TermoraURL.parse` içindedir ve burada YUMUŞATILMAZ. Reddedilen
    /// istek loglanır ama kullanıcıya diyalog GÖSTERİLMEZ: herhangi bir web sayfasının
    /// tetikleyebildiği bir istek, kullanıcının ekranını kesme hakkı kazanmamalı
    /// (aksi hâlde şemanın kendisi bir taciz vektörü olurdu).
    func handleIncomingURL(_ url: URL) {
        switch TermoraURL.parse(url) {
        case let .success(.openFolder(path)):
            requestOpenFolder(paths: [path])
        case let .failure(reason):
            Self.logger.error("Rejected incoming URL: \(reason.logLabel, privacy: .public)")
        }
    }

    /// Klasör açma isteğini park eder; ilk pencere alır. Boş liste hiçbir şey yapmaz.
    func requestOpenFolder(paths: [String]) {
        guard !paths.isEmpty else { return }
        folderOpenRequest = FolderOpenRequest(paths: paths)
    }

    /// Uygulamanın DIŞ kapıları: Servisler menüsü ve `termora://` şeması.
    ///
    /// Servis girdisinin TANIMI Info.plist'teki `NSServices` bloğudur; burada yalnız o
    /// tanımın çağıracağı nesne kaydedilir. Tam bir Finder Sync uzantısı ayrı bir hedef
    /// (ve ayrı bir imza) isterdi; Servisler menüsü aynı işi tek bir yöntemle yapar.
    ///
    /// URL şeması için SwiftUI'nin `.onOpenURL`'ü KULLANILMIYOR: bu uygulamada (özel bir
    /// `NSApplicationDelegate` ile) Apple Event pakete ULAŞIYOR — `log` çıktısında
    /// `RECEIVED:(GURL,GURL)` görünüyor — ama `.onOpenURL` hiç tetiklenmiyor. Bu yüzden
    /// `kAEGetURL` olayı doğrudan dinlenir; tek ve kesin bir giriş noktası kalır.
    private func registerExternalEntryPoints() {
        let provider = TermoraServicesProvider(services: self)
        servicesProvider = provider
        Self.registeredEventProvider = provider
        NSApplication.shared.servicesProvider = provider

        Self.listenForURLEvents(provider)

        // AppKit kendi `GURL` işleyicisini `finishLaunching` sırasında kurar ve daha ÖNCE
        // kurulmuş bir işleyiciyi ezebilir; kayıt açılış bittikten sonra tazelenir.
        // (Sonradan kurulan `AppServices` için init'teki kayıt zaten yeterli.)
        launchObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak provider] _ in
            guard let provider else { return }
            MainActor.assumeIsolated { AppServices.listenForURLEvents(provider) }
        }

        guard !Self.hasRefreshedServices else { return }
        Self.hasRefreshedServices = true
        // Geliştirme sırasında pbs önbelleği eskiyebiliyor; süreç başına bir tazeleme.
        NSUpdateDynamicServices()
    }

    private static func listenForURLEvents(_ provider: TermoraServicesProvider) {
        NSAppleEventManager.shared().setEventHandler(
            provider,
            andSelector: #selector(TermoraServicesProvider.handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: TermoraServicesProvider.internetEventClass,
            andEventID: TermoraServicesProvider.getURLEventID)
    }

    // MARK: - Oturumun kaydedilmesi

    /// Uygulama kapanışındaki KESİN yazma.
    ///
    /// Kural (macOS konvansiyonu): o an AÇIK olan pencereler geri yüklenir. Kullanıcının
    /// bilerek kapattığı pencere listeden düşer; hepsini kapatıp çıkarsa uygulama temiz açılır.
    /// Pencere kapanışındaki `record` yazması yalnız ÇÖKME sigortasıdır.
    ///
    /// - Parameter windows: testler için dikiş; nil ise açık pencerelerden toplanır.
    func persistSessionSnapshot(windows: [SessionWindowSnapshot]? = nil) {
        guard settings.settings.restoresPreviousSession else {
            // Gizlilik (briefs/2): kapalı bir özellik kullanıcının çalışma dizinlerini
            // diskte tutmamalı.
            sessionRestore.clear()
            return
        }
        sessionRestore.replaceAll(with: windows ?? Self.openWindowSnapshots())
    }

    /// Açık terminal pencerelerinin anlık görüntüleri, EKRANDAKİ sırayla.
    /// `WindowCloseCoordinator.live` bir zayıf küme olduğu için sırası belirsizdir; sıra
    /// `NSApp.windows` üzerinden kurulur, yoksa sekmeler her açılışta pencere değiştirirdi.
    private static func openWindowSnapshots() -> [SessionWindowSnapshot] {
        let coordinators = WindowCloseCoordinator.live.filter(\.isOpen)
        return NSApp.windows
            .compactMap { window in coordinators.first { $0.owns(window) } }
            .compactMap { $0.captureSnapshot() }
    }

    // MARK: - Gözlemciler

    /// Kapanış `applicationWillTerminate` bildiriminden yakalanır: ⌘Q, menü, Dock ve
    /// `NSApp.terminate` yollarının HEPSİ buradan geçer.
    private func observeApplicationTermination() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // AppKit bu bildirimi her zaman ana iş parçacığında gönderir.
            MainActor.assumeIsolated { self?.persistSessionSnapshot() }
        }
    }

    /// Ayar kapatıldığı ANDA kayıt silinir; kullanıcı bir sonraki çıkışa kadar beklemek
    /// zorunda kalmamalı (briefs/2 "Gizlilik").
    private func observeRestoreSettingBeingTurnedOff() {
        withObservationTracking {
            _ = settings.settings.restoresPreviousSession
        } onChange: { [weak self] in
            // `onChange` değer YAZILMADAN ÖNCE tetiklenir; yeni değeri okumak için bir sonraki
            // ana-iş-parçacığı turuna geçilir.
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.settings.settings.restoresPreviousSession {
                    self.sessionRestore.clear()
                }
                // Takip tek atımlıktır: her değişimden sonra yeniden kurulur.
                self.observeRestoreSettingBeingTurnedOff()
            }
        }
    }
}

/// Bekleyen bir klasör açma isteği (URL şeması ya da Finder servisi).
///
/// `id` her istekte tazedir: aynı klasör arka arkaya iki kez istendiğinde pencerenin
/// `onChange` kancası ikinci isteği de görmeli.
struct FolderOpenRequest: Identifiable, Equatable {
    let id = UUID()
    /// Açılacak klasörler, seçim sırasıyla. Her biri kanonik mutlak yoldur ve
    /// `FinderService` / `TermoraURL` doğrulamasından geçmiştir.
    let paths: [String]
}

/// macOS Servisler menüsündeki "Open in Termora" girdisinin hedefi.
///
/// Ayrı bir `NSObject`: servis yöntemleri Objective-C çalışma zamanından çağrılır,
/// `AppServices` ise `@Observable` bir Swift sınıfıdır.
///
/// GÜVENLİK: pano da dışarıdan gelen bir girdidir. Seçim `FinderService` süzgecinden
/// geçer — dosyalar ve dosya olmayan URL'ler elenir, yalnız var olan klasörler kalır — ve
/// klasör `termora://` ile AYNI kapıdan açılır. Buradan komut çalıştırılmaz.
@MainActor
final class TermoraServicesProvider: NSObject {

    /// `kInternetEventClass` / `kAEGetURL` / `keyDirectObject`.
    ///
    /// Ham FourCharCode olarak yazıldılar: Carbon başlıklarını yalnız üç sabit için
    /// içeri almak gerekmiyor. Değerler `'GURL'` ve `'----'`.
    static let internetEventClass = AEEventClass(0x4755_524C)
    static let getURLEventID = AEEventID(0x4755_524C)
    private static let directObjectKeyword = AEKeyword(0x2D2D_2D2D)

    private weak var services: AppServices?

    init(services: AppServices) {
        self.services = services
        super.init()
    }

    /// `termora://…` Apple Event'i (bkz. `AppServices.registerExternalEntryPoints`).
    ///
    /// Burada DOĞRULAMA YAPILMAZ: olay yalnız bir URL'e çevrilir ve tek karar noktası olan
    /// `handleIncomingURL` çağrılır. Çözülemeyen bir olay sessizce düşer — dışarıdan gelen
    /// bozuk bir olay kullanıcının ekranını kesmemeli.
    @objc
    func handleGetURLEvent(_ event: NSAppleEventDescriptor,
                           withReplyEvent reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: Self.directObjectKeyword)?.stringValue,
              let url = URL(string: string) else { return }
        services?.handleIncomingURL(url)
    }

    /// Info.plist'teki `NSServices ▸ NSMessage` = `FinderService.messageName`.
    @objc
    func openFolderInTermora(_ pasteboard: NSPasteboard,
                             userData: String?,
                             error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
        let paths = FinderService.folderPaths(from: urls)
        guard !paths.isEmpty else {
            // Servis menüsündeki hata metni; kullanıcı bir dosya seçmiş olabilir.
            error.pointee = "Select a folder to open in Termora." as NSString
            return
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        services?.requestOpenFolder(paths: paths)
    }
}
