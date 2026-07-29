import Testing
@testable import Termora

@Suite("Profil görünüm çözümlemesi")
struct AppearanceResolverTests {

    private func baseSettings() -> AppSettings {
        var settings = AppSettings()
        settings.fontName = "Menlo"
        settings.fontSize = 13
        settings.themeID = "termora-dark"
        return settings
    }

    @Test func noProfileUsesGlobalSettings() {
        let resolved = AppearanceResolver.resolve(settings: baseSettings(), profile: nil)
        #expect(resolved == ResolvedAppearance(
            fontName: "Menlo", fontSize: 13, themeID: "termora-dark", usesLigatures: false
        ))
    }

    /// Ligature'ın profilde karşılığı yok (briefs/1 profil alanları): satır yüksekliği ve
    /// imleç gibi genel kalır. Yine de çözümlemeden geçer ki fontu kuran taraf tek bir
    /// yerden okusun.
    @Test func ligatureSettingFlowsThroughEvenThoughProfilesCannotOverrideIt() {
        var settings = baseSettings()
        settings.usesLigatures = true
        let profile = TerminalProfile(name: "Ops", fontName: "SF Mono")
        #expect(AppearanceResolver.resolve(settings: settings, profile: profile).usesLigatures)
        #expect(AppearanceResolver.resolve(settings: settings, profile: nil).usesLigatures)
    }

    @Test func profileOverridesWinOverGlobalSettings() {
        let profile = TerminalProfile(
            name: "Ops",
            fontName: "SF Mono",
            fontSize: 15,
            themeID: "nord"
        )
        let resolved = AppearanceResolver.resolve(settings: baseSettings(), profile: profile)
        #expect(resolved.fontName == "SF Mono")
        #expect(resolved.fontSize == 15)
        #expect(resolved.themeID == "nord")
    }

    @Test func nilProfileFieldsFallBackToSettingsIndividually() {
        let profile = TerminalProfile(name: "Sadece tema", themeID: "dracula")
        let resolved = AppearanceResolver.resolve(settings: baseSettings(), profile: profile)
        #expect(resolved.fontName == "Menlo")
        #expect(resolved.fontSize == 13)
        #expect(resolved.themeID == "dracula")
    }

    @Test func resolvedFontSizeIsClamped() {
        let profile = TerminalProfile(name: "Devasa", fontSize: 400)
        let resolved = AppearanceResolver.resolve(settings: baseSettings(), profile: profile)
        #expect(resolved.fontSize == SettingsLimits.fontSizeRange.upperBound)

        var tiny = baseSettings()
        tiny.fontSize = 1
        #expect(AppearanceResolver.resolve(settings: tiny, profile: nil).fontSize == SettingsLimits.fontSizeRange.lowerBound)
    }
}
