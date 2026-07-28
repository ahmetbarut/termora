import AppKit
import Testing
@testable import Termora

/// brief 3 "Erişilebilirlik → Kontrast oranı korunmalı".
///
/// İki katman: önce WCAG 2.1 hesabının kendisi bilinen referans değerlerle doğrulanır,
/// sonra marka paletinin okunabilirlik sözleşmesi kilitlenir. İkinci grup bir REGRESYON
/// KORUMASIDIR: birisi `DesignTokens`'taki bir hex'i karartırsa test kırılır.
@MainActor
@Suite("Kontrast oranı")
struct ContrastRatioTests {

    private func color(_ hex: String) throws -> NSColor {
        try #require(NSColor(hexString: hex), "Ayrıştırılamayan hex: \(hex)")
    }

    // MARK: - WCAG hesabı

    @Test func blackAgainstWhiteIsTheMaximumRatio() throws {
        let ratio = ContrastRatio.ratio(try color("#000000"), try color("#FFFFFF"))
        #expect(abs(ratio - 21.0) < 0.01)
    }

    @Test func aColourAgainstItselfHasNoContrast() throws {
        let accent = try color("#169CFF")
        #expect(abs(ContrastRatio.ratio(accent, accent) - 1.0) < 0.0001)
    }

    @Test func theRatioIsSymmetric() throws {
        let dark = try color("#080B18")
        let light = try color("#F4F6FF")
        #expect(abs(ContrastRatio.ratio(dark, light) - ContrastRatio.ratio(light, dark)) < 0.0001)
    }

    /// WCAG'ın kendi referans örneği: `#767676` beyaz üstünde 4.54 : 1 — AA sınırını
    /// kıl payı geçer. Gama düzeltmesi yanlış uygulanırsa bu değer tutmaz.
    @Test func theWcagReferenceGreyMatches() throws {
        let ratio = ContrastRatio.ratio(try color("#767676"), try color("#FFFFFF"))
        #expect(abs(ratio - 4.54) < 0.02)
    }

    @Test func thresholdsMatchWcagTwoPointOne() {
        #expect(ContrastRatio.normalText == 4.5)
        #expect(ContrastRatio.largeTextOrUIComponent == 3.0)
        #expect(ContrastRatio.enhancedText == 7.0)
    }

    // MARK: - Marka paletinin sözleşmesi

    private static let brandBackgrounds = [
        DesignTokens.backgroundPrimary,
        DesignTokens.backgroundSecondary,
        DesignTokens.backgroundElevated,
    ]

    @Test func primaryTextClearsTheEnhancedThresholdOnEveryBrandBackground() {
        for background in Self.brandBackgrounds {
            let ratio = ContrastRatio.ratio(DesignTokens.textPrimary.nsColor, background.nsColor)
            #expect(ratio >= ContrastRatio.enhancedText,
                    "Text Primary / \(background.name) = \(ratio)")
        }
    }

    @Test func secondaryTextClearsTheNormalTextThresholdOnEveryBrandBackground() {
        for background in Self.brandBackgrounds {
            let ratio = ContrastRatio.ratio(DesignTokens.textSecondary.nsColor, background.nsColor)
            #expect(ratio >= ContrastRatio.normalText,
                    "Text Secondary / \(background.name) = \(ratio)")
        }
    }

    /// Muted metin brief'te yalnız yardımcı/ikincil bilgi içindir; gövde metni eşiğini
    /// tutturmaz ama arayüz bileşeni eşiğini (3 : 1) her zeminde geçmelidir.
    @Test func mutedTextClearsTheUiComponentThresholdOnEveryBrandBackground() {
        for background in Self.brandBackgrounds {
            let ratio = ContrastRatio.ratio(DesignTokens.textMuted.nsColor, background.nsColor)
            #expect(ratio >= ContrastRatio.largeTextOrUIComponent,
                    "Text Muted / \(background.name) = \(ratio)")
        }
    }

    /// Vurgu ve durum renkleri metin değil, işaret taşır (aktif sekme çizgisi, aktif panel
    /// border'ı, durum noktası). WCAG bunları "arayüz bileşeni" sayar: en az 3 : 1.
    @Test func accentAndStateColoursClearTheUiComponentThreshold() {
        let background = DesignTokens.backgroundPrimary.nsColor
        let signals = [
            DesignTokens.accentBlue, DesignTokens.accentViolet,
            DesignTokens.success, DesignTokens.warning, DesignTokens.danger,
        ]
        for token in signals {
            let ratio = ContrastRatio.ratio(token.nsColor, background)
            #expect(ratio >= ContrastRatio.largeTextOrUIComponent,
                    "\(token.name) / Background Primary = \(ratio)")
        }
    }

    /// Terminal metni gövde metnidir: hiçbir tema AA sınırının altına düşmemeli.
    /// `ThemeStore.fallback` uygulama hedefine gömülüdür, her koşuda okunur.
    @Test func theFallbackThemeKeepsForegroundReadable() {
        let ratio = ContrastRatio.ratio(ThemeStore.fallback.foregroundNSColor,
                                        ThemeStore.fallback.backgroundNSColor)
        #expect(ratio >= ContrastRatio.normalText, "\(ThemeStore.fallback.name) = \(ratio)")
    }

    /// Paketten yüklenen temalar (test koşucusu uygulamayı barındırmıyorsa yalnız fallback).
    @Test func everyBundledThemeKeepsForegroundReadable() {
        for theme in ThemeStore(bundle: .main).themes {
            let ratio = ContrastRatio.ratio(theme.foregroundNSColor, theme.backgroundNSColor)
            #expect(ratio >= ContrastRatio.normalText, "\(theme.name) = \(ratio)")
        }
    }
}
