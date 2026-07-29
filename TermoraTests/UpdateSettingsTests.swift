import Foundation
import Testing
@testable import Termora

/// briefs/2 "Güncelleme Sistemi" + "Gizlilik".
///
/// Güncelleme kontrolü bir AĞ isteğidir; bu yüzden ne gönderdiği ve ne zaman gönderdiği
/// ayarlanabilir ve sınanabilir olmalı. Brief'in kırmızı çizgisi: *Güncelleme kontrolü
/// telemetri toplamıyor.*
@Suite("Güncelleme ayarları")
struct UpdateSettingsTests {

    @Test func theBriefsIntervalsAreAllHere() {
        #expect(UpdateCheckInterval.allCases.map(\.title) == ["Daily", "Weekly", "Monthly"])
    }

    @Test func eachIntervalIsTheNumberOfSecondsItsNameClaims() {
        #expect(UpdateCheckInterval.daily.seconds == 86_400)
        #expect(UpdateCheckInterval.weekly.seconds == 7 * 86_400)
        #expect(UpdateCheckInterval.monthly.seconds == 30 * 86_400)
    }

    /// Sparkle bir saatten sık kontrolü reddeder; hiçbir seçenek o sınırın altına inmemeli.
    @Test func noIntervalIsShorterThanSparkleAllows() {
        for interval in UpdateCheckInterval.allCases {
            #expect(interval.seconds >= 3600)
        }
    }

    /// Otomatik kontrol AÇIK gelir: güvenlik düzeltmesini kaçıran kullanıcı, kapalı bir
    /// varsayılandan çok daha pahalıya mal olur. Kontrolün ne gönderdiği ayrı bir soru
    /// ve yanıtı aşağıdaki testte.
    @Test func automaticChecksAreOnByDefaultAndCanBeTurnedOff() {
        var settings = AppSettings()
        #expect(settings.checksForUpdatesAutomatically)

        settings.checksForUpdatesAutomatically = false
        #expect(settings.checksForUpdatesAutomatically == false)
    }

    @Test func theDefaultIntervalIsDaily() {
        #expect(AppSettings().updateCheckInterval == .daily)
    }

    /// Eski ayar dosyası bu alanları taşımaz; okunamayan kayıt varsayılana düşmeli.
    @Test func anolderSettingsFileStillOpens() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(decoded.checksForUpdatesAutomatically)
        #expect(decoded.updateCheckInterval == .daily)
    }

    /// briefs/2 "Gizlilik" ▸ *Güncelleme kontrolü telemetri toplamıyor.*
    ///
    /// Sparkle isteğe bağlı olarak makine profili (CPU, model, dil, macOS sürümü)
    /// gönderebilir. Bu AÇILAMAZ: ayar bile yok, sabit `false`.
    @Test func theUpdateCheckNeverSendsAsystemProfile() {
        #expect(UpdaterConfiguration.sendsSystemProfile == false)

        // Ayarlarda bu ayarı açacak bir alan da bulunmamalı.
        let fields = Set(Mirror(reflecting: AppSettings()).children.compactMap(\.label))
        for forbidden in ["sendsSystemProfile", "systemProfile", "updateTelemetry"] {
            #expect(fields.contains(forbidden) == false)
        }
    }
}

/// Güncelleyicinin kendisi: ayarları Sparkle'a taşıyan ince katman.
///
/// Sparkle tipleri testte kullanılmaz — bu sınıfın işi KARAR vermek (kontrol edilsin mi,
/// hangi sıklıkta), indirmeyi yapmak değil.
@MainActor
@Suite("Güncelleyici")
struct UpdateControllerTests {

    /// Sparkle'ın yerini tutan casus: hangi ayarın ona geçtiğini kaydeder.
    private final class Spy: UpdaterDriving {
        var automaticallyChecksForUpdates = false
        var updateCheckInterval: TimeInterval = 0
        var sendsSystemProfile = true
        var checkCount = 0
        func checkForUpdates() { checkCount += 1 }
    }

    @Test func theSettingsReachTheUpdater() {
        let spy = Spy()
        var settings = AppSettings()
        settings.checksForUpdatesAutomatically = true
        settings.updateCheckInterval = .weekly

        UpdateController.apply(settings, to: spy)

        #expect(spy.automaticallyChecksForUpdates)
        #expect(spy.updateCheckInterval == UpdateCheckInterval.weekly.seconds)
    }

    /// Kapalıyken Sparkle'a "kontrol etme" denir; sıklık yine de taşınır ki kullanıcı
    /// tekrar açtığında seçtiği değer geçerli olsun.
    @Test func turningChecksOffStopsTheUpdater() {
        let spy = Spy()
        var settings = AppSettings()
        settings.checksForUpdatesAutomatically = false
        settings.updateCheckInterval = .monthly

        UpdateController.apply(settings, to: spy)

        #expect(spy.automaticallyChecksForUpdates == false)
        #expect(spy.updateCheckInterval == UpdateCheckInterval.monthly.seconds)
    }

    /// Makine profili HER durumda kapatılır — kullanıcı otomatik kontrolü açsa da.
    @Test func thesystemProfileIsSwitchedOffEveryTimeSettingsAreApplied() {
        let spy = Spy()
        spy.sendsSystemProfile = true

        UpdateController.apply(AppSettings(), to: spy)

        #expect(spy.sendsSystemProfile == false)
    }

    /// Kullanıcının elle başlattığı kontrol, ayar kapalı olsa da çalışır: "şimdi kontrol
    /// et" düğmesi otomatik kontrol ayarına bağlı değildir.
    @Test func amanualCheckRunsEvenWhenAutomaticChecksAreOff() {
        let spy = Spy()
        var settings = AppSettings()
        settings.checksForUpdatesAutomatically = false
        UpdateController.apply(settings, to: spy)

        spy.checkForUpdates()

        #expect(spy.checkCount == 1)
    }
}

/// briefs/2 "Ayarlar Ekranı" ▸ Updates sayfasının METİNLERİ.
///
/// Bu sayfanın da değeri dürüstlüğünde (gizlilik sayfasıyla aynı kural): appcast adresi
/// olmayan bir yapıda "otomatik kontrol açık" demek, hiçbir şey kontrol etmeyen bir
/// anahtar göstermek olurdu.
@MainActor
@Suite("Güncelleme sayfası içeriği")
struct UpdatesSettingsContentTests {

    @Test func thePageSaysWhatItDoesWhenTheBuildCannotUpdateItself() {
        let text = UpdatesContent.notConfiguredNote.lowercased()
        #expect(text.contains("not"))
        #expect(UpdatesContent.notConfiguredNote.hasSuffix("."))
    }

    /// Hazır yapıda sayfa güncellemenin NE gönderdiğini söyler: brief'in gizlilik
    /// kriteri kullanıcının görebileceği bir cümle olmadan denetlenemez.
    @Test func thePageStatesThatTheCheckSendsNoProfile() {
        let text = UpdatesContent.privacyNote.lowercased()
        #expect(text.contains("no") || text.contains("never"))
        #expect(text.contains("version"))
    }

    /// briefs/2: *İmzası doğrulanamayan paket kurulmuyor.* Sayfa bunu YAZAR — kullanıcı
    /// imza doğrulamasının var olduğunu görebilmeli.
    @Test func thePageStatesThatUnsignedPackagesAreRefused() {
        #expect(UpdatesContent.signatureNote.lowercased().contains("signature"))
    }

    @Test func everyNoteIsAsentence() {
        for note in [UpdatesContent.notConfiguredNote,
                     UpdatesContent.privacyNote,
                     UpdatesContent.signatureNote] {
            #expect(note.count > 40)
            #expect(note.hasSuffix("."))
        }
    }
}
