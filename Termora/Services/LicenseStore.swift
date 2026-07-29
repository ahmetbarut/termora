import Foundation
import Observation

/// Kurulu lisansın tek sahibi.
///
/// briefs/1 "Güvenlik" ve briefs/2 "Lisanslama": anahtar Keychain'de durur. `AppSettings`
/// diske düz JSON yazılır; oraya düşen bir lisans anahtarı, dosyayı okuyan herkese
/// kopyalanabilir bir anahtar vermek demektir. Bu yüzden `AppSettings`'te lisans için
/// alan YOK ve `LicenseTests` bunu alan alan doğruluyor.
@Observable
final class LicenseStore {

    enum Failure: Error, Equatable {
        /// Metin imzayı geçmedi ya da süresi dolmuş. Kullanıcıya tek cümleyle söylenir;
        /// hangisi olduğunu ayırmak, anahtar deneyen birine bilgi vermekten başka işe yaramaz.
        case invalidKey
    }

    /// Doğrulanmış lisans; yoksa `nil`.
    private(set) var license: License?

    var state: LicenseState { LicenseState(license: license) }

    /// Bu YAPIDA lisans denetimi var mı?
    ///
    /// Açık anahtar Info.plist'ten gelir; yoksa hiçbir anahtar doğrulanamaz. O durumda
    /// denetim uygulanmaz — kurulmamış bir kural yüzünden özellik kapatmak, kullanıcının
    /// karşılığını ödediği bir şeyi değil, hiç var olmamış bir sınırı dayatmak olurdu.
    /// Lisans sayfası da bunu açıkça yazar; "Free" deyip her şeyi açık bırakan bir ekran
    /// kullanıcıyı yanıltırdı.
    var isLicensingConfigured: Bool { verifier.isConfigured }

    /// Uygulamanın tek lisans deposu. Ayarlar penceresi ve terminal penceresi aynı
    /// örneği görür; iki ayrı depo, birinde etkinleştirilen lisansın diğerinde
    /// görünmemesi demek olurdu.
    static let shared = LicenseStore()

    private let keychain: KeychainService
    private let verifier: LicenseVerifier

    init(keychain: KeychainService = KeychainService(),
         verifier: LicenseVerifier = .production) {
        self.keychain = keychain
        self.verifier = verifier
        // Açılışta Keychain'den okunur ve YERİNDE doğrulanır: ağ yoksa da uygulama
        // Pro olarak açılır (briefs/2 "Çevrimdışı kullanılabilirlik").
        //
        // Keychain okuması başarısız olursa (kilitli zincir, izin reddi) uygulama yine
        // açılır, yalnız Free olur — lisans yüzünden açılmayan bir terminal, lisansın
        // korumaya çalıştığı her şeyden daha büyük bir sorundur.
        if let stored = try? keychain.secret(account: LicenseState.keychainAccount) {
            license = verifier.license(from: stored, now: Date())
        }
    }

    /// Anahtarı doğrular ve GEÇERLİYSE saklar.
    ///
    /// Sıra bilerek böyle: geçersiz bir metin Keychain'e hiç girmez, dolayısıyla yanlış
    /// yapıştırılmış bir anahtar her açılışta sessizce yeniden denenmez.
    func activate(_ key: String) throws {
        guard let license = verifier.license(from: key, now: Date()) else {
            throw Failure.invalidKey
        }
        try keychain.setSecret(key.trimmingCharacters(in: .whitespacesAndNewlines),
                               account: LicenseState.keychainAccount)
        self.license = license
    }

    func deactivate() throws {
        try keychain.removeSecret(account: LicenseState.keychainAccount)
        license = nil
    }

    func allows(_ feature: ProFeature) -> Bool { state.allows(feature) }
}
