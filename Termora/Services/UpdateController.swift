import Foundation

/// Ayarları güncelleyiciye taşıyan katman.
///
/// briefs/2 "Güncelleme Sistemi". Sparkle'ın kendisi burada YOK: bu tipin işi karar
/// vermek (kontrol edilsin mi, hangi sıklıkta, ne gönderilsin), indirmeyi yapmak değil.
/// Sparkle bağlaması `SparkleUpdater`da ve o dosya yalnız Sparkle varsa derlenir.
@MainActor
enum UpdateController {

    static func apply(_ settings: AppSettings, to updater: any UpdaterDriving) {
        updater.automaticallyChecksForUpdates = settings.checksForUpdatesAutomatically
        // Sıklık ayar kapalıyken de taşınır: kullanıcı tekrar açtığında seçtiği değer
        // geçerli olsun, varsayılana dönmesin.
        updater.updateCheckInterval = settings.updateCheckInterval.seconds
        // HER uygulamada yeniden kapatılır — bir kez kurmak, araya giren başka bir kodun
        // açtığı ihtimali kapatmaz.
        updater.sendsSystemProfile = UpdaterConfiguration.sendsSystemProfile
    }

    /// Bu yapı güncellemeye hazır mı? Appcast adresi VE açık anahtar birlikte gerekir.
    ///
    /// İkisi birlikte aranır çünkü tek başına feed, imzası doğrulanamayan bir paketi
    /// indirip kurmak demektir — briefs/2'nin *İmzası doğrulanamayan paket kurulmuyor*
    /// kabul kriteri tam olarak bunu yasaklıyor.
    static func isConfigured(bundle: Bundle = .main) -> Bool {
        let feed = bundle.object(forInfoDictionaryKey: UpdaterConfiguration.feedURLKey) as? String
        let key = bundle.object(forInfoDictionaryKey: UpdaterConfiguration.publicKeyKey) as? String
        return !(feed ?? "").isEmpty && !(key ?? "").isEmpty
    }
}
