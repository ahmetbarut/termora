import Foundation
import Sparkle

/// Sparkle'ın `SPUUpdater`'ını `UpdaterDriving` arkasına alan ince bağlama.
///
/// Buradaki her satır Sparkle'a bir şey SÖYLER; hiçbir karar burada verilmez. Kararlar
/// `UpdateController`da ve orası Sparkle'ı hiç tanımadığı için testte casusla sınanabilir.
@MainActor
final class SparkleUpdater: UpdaterDriving {
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    var updateCheckInterval: TimeInterval {
        get { updater.updateCheckInterval }
        set { updater.updateCheckInterval = newValue }
    }

    var sendsSystemProfile: Bool {
        get { updater.sendsSystemProfile }
        set { updater.sendsSystemProfile = newValue }
    }

    func checkForUpdates() { updater.checkForUpdates() }
}

/// Uygulamanın güncelleyicisi.
///
/// briefs/2 "Güncelleme Sistemi". Sparkle YALNIZ yapı hazırsa başlatılır: appcast adresi
/// ve EdDSA açık anahtarı Info.plist'te olmalı. Tek başına feed, imzası doğrulanamayan
/// bir paketi indirmek demektir — brief'in *İmzası doğrulanamayan paket kurulmuyor*
/// kriteri tam olarak bunu yasaklıyor, o yüzden ikisi birlikte aranır.
///
/// `startingUpdater: false` ile kurulup sonra elle başlatılıyor: yapı hazır değilse
/// Sparkle hiç çalışmaz ve kullanıcıya "güncelleme aranıyor" diye yanlış bir izlenim
/// verilmez.
@MainActor
final class AppUpdater {

    static let shared = AppUpdater()

    /// Yapı güncellemeye hazır değilse `nil`; sayfa buna bakıp ne yazacağına karar verir.
    private(set) var driver: (any UpdaterDriving)?

    private let controller: SPUStandardUpdaterController?

    private init() {
        guard UpdateController.isConfigured() else {
            controller = nil
            driver = nil
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false,
                                                      updaterDelegate: nil,
                                                      userDriverDelegate: nil)
        self.controller = controller
        driver = SparkleUpdater(updater: controller.updater)
    }

    /// Ayarları uygular ve güncelleyiciyi başlatır. Uygulama açılışında bir kez çağrılır.
    func start(with settings: AppSettings) {
        guard let driver, let controller else { return }
        UpdateController.apply(settings, to: driver)
        do {
            try controller.updater.start()
        } catch {
            // Başlatılamayan güncelleyici uygulamayı DURDURMAZ: kullanıcının terminali,
            // güncelleme altyapısından önce gelir. Sayfa "hazır değil" durumunu zaten
            // anlatıyor.
            self.driver = nil
        }
    }

    /// Ayar değiştiğinde Sparkle'a taşı.
    func apply(_ settings: AppSettings) {
        guard let driver else { return }
        UpdateController.apply(settings, to: driver)
    }

    /// Kullanıcının elle başlattığı kontrol; otomatik kontrol ayarına bağlı değildir.
    func checkForUpdates() { driver?.checkForUpdates() }

    var isReady: Bool { driver != nil }
}
