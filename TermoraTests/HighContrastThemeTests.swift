import AppKit
import Foundation
import Testing
@testable import Termora

/// brief 3 "Erişilebilirlik → Terminal renkleri için yüksek kontrast seçeneği bulunmalı".
///
/// Seçenek, paketle gelen `termora-high-contrast` temasıdır. Sözleşme ÖLÇÜLÜR, iddia
/// edilmez: metin/arka plan AAA (7 : 1), 16 ANSI renginin HEPSİ gövde metni sınırını
/// (4.5 : 1) geçer. Bir hex karartılırsa bu suite kırılır.
@MainActor
@Suite("Yüksek kontrast teması")
struct HighContrastThemeTests {

    /// Kullanıcı klasörü kasten BOŞ: ölçülen şey paketle gelen dosyanın kendisidir,
    /// geliştiricinin makinesinde duran temalar sonucu değiştirmemeli.
    private var theme: Theme {
        ThemeStoreTests.store(bundle: .main).theme(id: Theme.highContrastID)
    }

    @Test func theHighContrastThemeShipsWithTheApp() {
        let store = ThemeStoreTests.store(bundle: .main)
        #expect(store.themes.contains { $0.id == Theme.highContrastID })
        #expect(store.isBuiltIn(id: Theme.highContrastID))
        #expect(theme.name == "Termora High Contrast")
        #expect(theme.ansi.count == 16)
    }

    @Test func textClearsTheEnhancedThreshold() {
        let ratio = ContrastRatio.ratio(theme.foregroundNSColor, theme.backgroundNSColor)
        #expect(ratio >= ContrastRatio.enhancedText, "foreground / background = \(ratio)")
    }

    @Test func everyAnsiColourStaysReadableOnTheBackground() {
        let background = theme.backgroundNSColor
        for (index, hex) in theme.ansi.enumerated() {
            guard let color = NSColor(hexString: hex) else {
                Issue.record("ansi[\(index)] ayrıştırılamadı: \(hex)")
                continue
            }
            let ratio = ContrastRatio.ratio(color, background)
            #expect(ratio >= ContrastRatio.normalText, "ansi[\(index)] \(hex) = \(ratio)")
        }
    }

    /// İmleç bir arayüz göstergesidir (WCAG 1.4.11): en az 3 : 1.
    @Test func theCursorIsVisibleAgainstTheBackground() {
        let ratio = ContrastRatio.ratio(theme.cursorNSColor, theme.backgroundNSColor)
        #expect(ratio >= ContrastRatio.largeTextOrUIComponent, "cursor = \(ratio)")
    }

    /// Seçim rengi metnin ARKA PLANI olur: seçili metin okunur kalmalı, ama seçimin
    /// kendisi de normal arka plandan ayırt edilmeli.
    @Test func selectedTextStaysReadableAndTheSelectionIsVisible() {
        let selectionAgainstText = ContrastRatio.ratio(theme.foregroundNSColor, theme.selectionNSColor)
        #expect(selectionAgainstText >= ContrastRatio.normalText, "foreground / selection = \(selectionAgainstText)")

        let selectionAgainstBackground = ContrastRatio.ratio(theme.selectionNSColor, theme.backgroundNSColor)
        #expect(selectionAgainstBackground >= ContrastRatio.largeTextOrUIComponent,
                "selection / background = \(selectionAgainstBackground)")
    }

    /// 16 rengin hepsi okunur olmalı ama birbirinden de ayırt edilmeli: normal ve parlak
    /// çiftler projedeki tek türetme kuralını izler.
    @Test func brightColoursFollowTheProjectsDerivationRule() {
        let theme = theme
        for index in 0..<8 where theme.ansi.indices.contains(index + 8) {
            #expect(ThemeColorDerivation.brightened(theme.ansi[index]) == theme.ansi[index + 8],
                    "ansi[\(index + 8)] türetme kuralına uymuyor")
        }
    }

    @Test func noTwoAnsiSlotsShareTheSameColour() {
        let theme = theme
        #expect(Set(theme.ansi.map { $0.uppercased() }).count == theme.ansi.count)
    }

    // MARK: - Kontrast raporu (önizlemede gösterilen sayı)

    @Test func theReportMeasuresTheThemeItIsGiven() throws {
        let report = theme.contrastReport
        #expect(abs(report.textRatio - ContrastRatio.ratio(theme.foregroundNSColor,
                                                           theme.backgroundNSColor)) < 0.0001)
        #expect(report.meetsEnhancedText)
        #expect(report.everyAnsiColorMeetsNormalText)
        #expect(report.level == "AAA")
        #expect(report.summary.contains("AAA"))
        #expect(report.summary.contains(":1"))
    }

    @Test func theReportFlagsAThemeThatFailsTheBodyTextThreshold() throws {
        var dim = ThemeStore.fallback
        dim.background = "#3A3A3A"
        dim.foreground = "#4A4A4A"
        let report = dim.contrastReport
        #expect(!report.meetsNormalText)
        #expect(!report.meetsEnhancedText)
        #expect(report.level == "Below AA")
        #expect(!report.everyAnsiColorMeetsNormalText)
        #expect(report.summary.contains("Below AA"))
    }

    @Test func theReportNamesTheWeakestAnsiSlot() throws {
        var theme = ThemeStore.fallback
        theme.background = "#000000"
        theme.foreground = "#FFFFFF"
        theme.ansi = Array(repeating: "#FFFFFF", count: 16)
        theme.ansi[5] = "#101010"
        let report = theme.contrastReport
        #expect(report.lowestAnsiIndex == 5)
        #expect(report.lowestAnsiRatio < ContrastRatio.normalText)
        #expect(!report.everyAnsiColorMeetsNormalText)
    }

    /// AA ile AAA arasındaki tema "AA" raporlar.
    @Test func theReportSeparatesAaFromAaa() {
        var theme = ThemeStore.fallback
        theme.background = "#000000"
        theme.foreground = "#767676"
        #expect(theme.contrastReport.level == "AA")
    }
}
