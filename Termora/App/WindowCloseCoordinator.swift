import AppKit
import Foundation

/// Pencerenin kapat düğmesini (ve ⌘Q akışını) "çalışan işlem var mı?" onayına bağlar.
///
/// `NSWindow.delegate` zayıf tutulur; bu nesneyi `MainWindowView` bir `@State` içinde canlı
/// tutar. SwiftUI'nin kurduğu özgün delege korunur ve BURADA GERÇEKLENMEYEN tüm delege
/// mesajları ObjC iletimiyle ona aktarılır — aksi hâlde çerçevenin kendi pencere davranışları
/// (kapanış temizliği, geri yükleme) sessizce ölür.
@MainActor
final class WindowCloseCoordinator: NSObject, NSWindowDelegate {

    /// Canlı koordinatörler (zayıf tutulur). Uygulama kapanışında hangi pencerede iş
    /// çalıştığını bulmak için gerekir: `@FocusedValue` uygulama delegesinden okunamaz.
    private static let liveTable = NSHashTable<WindowCloseCoordinator>.weakObjects()

    static var live: [WindowCloseCoordinator] { liveTable.allObjects }

    static var firstBusy: WindowCloseCoordinator? {
        live.first { $0.hasRunningProcess }
    }

    private weak var window: NSWindow?
    private weak var workspace: WorkspaceViewModel?

    /// SwiftUI'nin kurduğu delege; işlemediğimiz mesajlar buna iletilir.
    private weak var previousDelegate: (any NSObjectProtocol)?

    /// Onay alındıktan sonraki `close()` çağrısında tekrar sormamak için bayrak.
    private var isClosingAfterApproval = false

    /// Pencere kapanırken oturum kaydını yazan dikiş; `MainWindowView` bağlar.
    /// Bağlanmazsa kapanış hiçbir şey kaydetmez (eski testler ve önizlemeler).
    var recordSession: ((SessionWindowSnapshot) -> Void)?

    /// Pencere hâlâ ekranda mı? Kapanmış bir pencerenin koordinatörü, SwiftUI `@State`'i
    /// bırakana kadar zayıf tabloda kalabilir; uygulama kapanışında onu da kaydetmek
    /// kullanıcının BİLEREK kapattığı pencereyi geri getirirdi.
    private(set) var isOpen = true

    /// Tam ekrana girmeden ÖNCEKİ çerçeve. Tam ekranda `window.frame` ekranın tamamıdır;
    /// onu kaydetmek pencereyi bir daha asla eski boyutuna döndüremezdi.
    private var frameBeforeFullScreen: CGRect?

    /// Kapatma akışına girmeden önce alınan son anlık görüntü. Onay akışı oturumları
    /// kapattıktan sonra yakalanacak düzen KALMAZ, bu yüzden son iyi hâl saklanır.
    private var lastSnapshot: SessionWindowSnapshot?

    private var windowObservers: [any NSObjectProtocol] = []

    override init() {
        super.init()
        Self.liveTable.add(self)
    }

    deinit {
        // `windowObservers` yalnız burada okunur ve NotificationCenter kaldırma çağrısı
        // iş parçacığından bağımsızdır.
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Pencereyi bağlar. `WindowAccessor` her yerleşim turunda çağırabilir: idempotenttir.
    /// SwiftUI delegeyi sonradan geri alırsa bir sonraki çağrıda yeniden devralınır.
    func attach(window: NSWindow, workspace: WorkspaceViewModel) {
        self.workspace = workspace
        let isNewWindow = self.window !== window
        self.window = window
        if isNewWindow { observeWindowNotifications(window) }
        guard window.delegate !== self else { return }
        if let existing = window.delegate {
            previousDelegate = existing
        }
        window.delegate = self
    }

    func owns(_ candidate: NSWindow) -> Bool { window === candidate }

    /// Tam ekran ve kapanış BİLDİRİM üzerinden izlenir, delege metoduyla değil: bu iki mesajı
    /// gerçeklemek onları SwiftUI'nin kendi delegesinden çalardı (`forwardingTarget` yalnız
    /// GERÇEKLENMEYEN seçiciler için devreye girer).
    private func observeWindowNotifications(_ window: NSWindow) {
        let center = NotificationCenter.default
        windowObservers.append(center.addObserver(
            forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main
        ) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let window else { return }
                self?.frameBeforeFullScreen = window.frame
            }
        })
        windowObservers.append(center.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isOpen = false }
        })
    }

    // MARK: - Oturum anlık görüntüsü

    /// Pencerenin kaydedilebilir hâli. Sekmeler ZATEN kapatılmışsa (onaylı kapanış) son
    /// bilinen anlık görüntü dönülür; boş bir pencere kaydetmek kullanıcının sekmelerini
    /// sessizce silerdi.
    func captureSnapshot() -> SessionWindowSnapshot? {
        guard let workspace, !workspace.tabs.isEmpty else { return lastSnapshot }
        let placement = currentPlacement()
        let snapshot = workspace.captureSessionWindow(frame: placement.frame,
                                                      isFullScreen: placement.isFullScreen)
        lastSnapshot = snapshot
        return snapshot
    }

    private func currentPlacement() -> (frame: SessionWindowFrame?, isFullScreen: Bool) {
        guard let window else { return (nil, false) }
        let isFullScreen = window.styleMask.contains(.fullScreen)
        // Tam ekranda tam ekran ÖNCESİ çerçeve yazılır; o da bilinmiyorsa (uygulama tam
        // ekran açıldı) çerçeve hiç kaydedilmez ve varsayılan yerleşim korunur.
        let rect = isFullScreen ? frameBeforeFullScreen : window.frame
        return (rect.map(SessionWindowFrame.init), isFullScreen)
    }

    var hasRunningProcess: Bool {
        workspace?.hasAnyRunningProcess() ?? false
    }

    func bringWindowForward() {
        window?.makeKeyAndOrderFront(nil)
    }

    /// Uygulama kapanışı için onay ister; `true` dönerse beklemeden kapanılabilir.
    func requestTermination(onApproved: @escaping @MainActor () -> Void) -> Bool {
        guard let workspace else { return true }
        // Onay akışı sekmeleri kapatır: kayıt ONDAN ÖNCE tazelenmeli.
        _ = captureSnapshot()
        return workspace.requestCloseWindow(onApproved: onApproved)
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isClosingAfterApproval { return true }
        guard let workspace else { return true }

        // Çökme sigortası: pencerenin son hâli, oturumlar kapanmadan ÖNCE diske yazılır.
        // Kullanıcı bu pencereyi bilerek kapatıyorsa uygulama kapanışındaki kesin yazma
        // (`AppServices.persistSessionSnapshot`) kaydı zaten listeden düşürecek.
        if let snapshot = captureSnapshot() { recordSession?(snapshot) }

        let canCloseNow = workspace.requestCloseWindow { [weak self] in
            self?.closeAfterApproval()
        }
        guard canCloseNow else { return false }

        // Çalışan işlem yok: onay gerekmiyor, ama oturumlar yine de burada kapatılmalı.
        // SessionManager view cache'i uygulama ömürlüdür; kapatmazsak pencere gitse de
        // boştaki shell süreçleri yaşamaya devam eder.
        workspace.closeAllTabs()
        return true
    }

    private func closeAfterApproval() {
        isClosingAfterApproval = true
        // Diyalog kapanışıyla aynı run-loop turunda close() çağırmak sheet'i yarım bırakır.
        DispatchQueue.main.async { [weak self] in
            self?.window?.close()
        }
    }

    // MARK: - Delege iletimi

    // AppKit bu iki mesajı her zaman ana iş parçacığında gönderir; `assumeIsolated`
    // Task 8'de SwiftTerm delegeleri için kullanılan kalıbın aynısıdır.
    nonisolated override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return MainActor.assumeIsolated {
            previousDelegate?.responds(to: aSelector) ?? false
        }
    }

    nonisolated override func forwardingTarget(for aSelector: Selector!) -> Any? {
        MainActor.assumeIsolated { () -> (any NSObjectProtocol)? in
            guard previousDelegate?.responds(to: aSelector) == true else { return nil }
            return previousDelegate
        }
    }
}
