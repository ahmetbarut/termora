//
//  AppServices.swift
//  Termora
//

import AppKit
import Foundation
import Observation

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

    /// Settings is a separate scene, so it cannot reach a window's `WorkspaceViewModel`.
    /// It parks the request here; the key window picks it up and clears it. Per-window view
    /// models stay per-window, and a workspace never opens in a window nobody is looking at.
    var workspaceOpenRequest: Workspace?

    /// Ayarlar ▸ SSH'tan gelen bağlanma isteği; anahtar pencere alır ve yeni sekmede açar.
    var sshConnectRequest: SSHTarget?

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
        self.sessionManager = SessionManager(settings: settings, themes: themes, profiles: profiles)

        let sessionRestore = SessionRestoreStore(defaults: defaults)
        self.sessionRestore = sessionRestore
        // Kuyruk İLK pencere görünmeden hazırlanır: `MainWindowView.onAppear` payını buradan
        // alır. Ayar kapalıysa kuyruk boş kalır ve diskteki kayıt hiç okunmaz.
        sessionRestore.prepareRestore(isEnabled: settings.settings.restoresPreviousSession)

        observeApplicationTermination()
        observeRestoreSettingBeingTurnedOff()
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
