import Foundation

/// Bir oturuma uygulanacak nihai görünüm: profil override'ları + genel ayarlar birleştirilmiş hâli.
struct ResolvedAppearance: Equatable {
    let fontName: String?
    let fontSize: Double
    let themeID: String
}

enum AppearanceResolver {

    /// Alan bazında çözümleme: profilde dolu olan her alan genel ayarı geçersiz kılar,
    /// nil olan alanlar genel ayardan gelir. Font boyutu her hâlde sınırlara kırpılır.
    static func resolve(settings: AppSettings, profile: TerminalProfile?) -> ResolvedAppearance {
        ResolvedAppearance(
            fontName: profile?.fontName ?? settings.fontName,
            fontSize: SettingsLimits.clampFontSize(profile?.fontSize ?? settings.fontSize),
            themeID: profile?.themeID ?? settings.themeID
        )
    }
}
