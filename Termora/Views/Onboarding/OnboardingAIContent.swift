import Foundation

/// briefs/2 Onboarding "Adım 3 — İsteğe Bağlı Özellikler" ▸ AI sağlayıcısı bağlantısı.
///
/// Bu bir KURULUM ADIMI değil, bir DURUM satırıdır. briefs/3: "AI kurulumu ilk açılış
/// için zorunlu olmamalıdır." Onboarding hiçbir cevabı beklemez: satır ne bulunduğunu
/// söyler, bulunmadıysa uygulamanın yine de çalıştığını söyler ve akış devam eder.
///
/// Metinler burada, `body` içinde değil: aynı cümleler testle sabitlenir ve panel /
/// Ayarlar ile ayrışmaz (aynı kalıp: `AISettingsContent`).
enum OnboardingAIContent {

    static let title = "AI Assistant"

    /// Satırın altındaki tek cümle. "Optional" kelimesi bilerek geçiyor: bağlanmamış bir
    /// AI satırı, söylenmezse bir engel gibi okunur.
    static let optionalNote = "Optional — Termora works fully without it, and you can set "
        + "this up any time in Settings ▸ AI."

    /// Model listesinin durumunu tek cümleye çevirir.
    ///
    /// `providerName` dışarıdan gelir: sağlayıcı adını burada sabitlemek, ileride ikinci
    /// bir sağlayıcı eklendiğinde sessizce yanlış isim yazdırırdı.
    static func summary(for availability: AIModelAvailability, providerName: String) -> String {
        switch availability {
        case .idle, .loading:
            // Onboarding bu cevabı BEKLEMEZ; bu cümle ekranda görünebilir ve orada kalabilir.
            return "Checking for a local \(providerName) provider…"

        case let .ready(models) where models.isEmpty:
            // Sağlayıcı ayakta ama indirilmiş model yok. "Hazır" demek yalan olurdu:
            // soru sorulacak bir model yok.
            return "\(providerName) is running, but it has no models installed yet."

        case let .ready(models):
            return "\(providerName) is running with \(Pluralize.count(models.count, "model")) installed."

        case let .unavailable(error):
            switch error {
            case .noModelsInstalled:
                // Çözüm KOMUTLA söylenir — panelin ve Ayarlar'ın kullandığı cümlenin aynısı.
                return "\(providerName) has no models to answer with. \(error.recovery)"
            default:
                // Suçlamaz, engel çıkarmaz: uygulamanın çalıştığını söyler.
                return "\(providerName) was not found, and Termora works fully without it. "
                    + error.recovery
            }
        }
    }
}
