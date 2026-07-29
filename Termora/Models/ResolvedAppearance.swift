import Foundation

/// Bir oturuma uygulanacak nihai görünüm: profil override'ları + genel ayarlar birleştirilmiş hâli.
struct ResolvedAppearance: Equatable {
    let fontName: String?
    let fontSize: Double
    let themeID: String
    /// Profilde karşılığı yoktur (briefs/1 profil alanları font, tema, shell, dizin, komut,
    /// ortam değişkenleri); satır yüksekliği ve imleç gibi genel kalır. Yine de burada
    /// taşınır ki fontu kuran taraf her şeyi tek yerden okusun.
    let usesLigatures: Bool
}

enum AppearanceResolver {

    /// Alan bazında çözümleme: profilde dolu olan her alan genel ayarı geçersiz kılar,
    /// nil olan alanlar genel ayardan gelir. Font boyutu her hâlde sınırlara kırpılır.
    static func resolve(settings: AppSettings, profile: TerminalProfile?) -> ResolvedAppearance {
        ResolvedAppearance(
            fontName: profile?.fontName ?? settings.fontName,
            fontSize: SettingsLimits.clampFontSize(profile?.fontSize ?? settings.fontSize),
            themeID: profile?.themeID ?? settings.themeID,
            usesLigatures: settings.usesLigatures
        )
    }
}
