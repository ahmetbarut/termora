import AppKit
import SwiftUI

/// brief 3 "Marka Kimliği → Ana Renkler" ve "Tipografi" bloklarının tek doğruluk kaynağı.
///
/// Arayüzde marka rengi gerektiğinde buradan okunur; hex değerleri koda ikinci kez
/// yazılmaz. Renkler `NSColor(hexString:)` ile sRGB'ye çözülür — terminal temaları da
/// (bkz. `Theme`) aynı ayrıştırıcıyı kullandığı için tema ve arayüz renkleri birebir eşleşir.
///
/// Not: bu tokenler MARKA paletidir, sistem semantiği değildir. Pencere/kontrol
/// renklerinde macOS'un kendi dinamik renkleri kullanılmaya devam eder (brief 3
/// "Native macOS Deneyimi"); tokenler yalnızca markaya ait vurgu noktalarında kullanılır.
enum DesignTokens {

    struct ColorToken: Equatable, Identifiable {
        let name: String
        /// "#RRGGBB" biçimi.
        let hex: String

        var id: String { name }

        /// Ayrıştırma başarısız olamaz: `DesignTokensTests.everyTokenHasAUniqueNameAndParsableHex`
        /// tüm tokenleri doğrular. Yine de force unwrap yok (brief 2 geliştirme kuralları).
        var nsColor: NSColor { NSColor(hexString: hex) ?? .textColor }

        var color: Color { Color(nsColor: nsColor) }
    }

    // MARK: - Ana renkler (brief 3)

    static let backgroundPrimary = ColorToken(name: "Background Primary", hex: "#080B18")
    static let backgroundSecondary = ColorToken(name: "Background Secondary", hex: "#0E1326")
    static let backgroundElevated = ColorToken(name: "Background Elevated", hex: "#151B32")
    static let border = ColorToken(name: "Border", hex: "#252C45")

    static let textPrimary = ColorToken(name: "Text Primary", hex: "#F4F6FF")
    static let textSecondary = ColorToken(name: "Text Secondary", hex: "#9CA5BE")
    static let textMuted = ColorToken(name: "Text Muted", hex: "#68718B")

    static let accentBlue = ColorToken(name: "Accent Blue", hex: "#169CFF")
    static let accentViolet = ColorToken(name: "Accent Violet", hex: "#7A3CFF")

    static let success = ColorToken(name: "Success", hex: "#32D583")
    static let warning = ColorToken(name: "Warning", hex: "#F5B942")
    static let danger = ColorToken(name: "Danger", hex: "#FF5D67")

    /// Brief'teki sırayla tüm palet (doğrulama ve olası bir palet önizlemesi için).
    static let all: [ColorToken] = [
        backgroundPrimary, backgroundSecondary, backgroundElevated, border,
        textPrimary, textSecondary, textMuted,
        accentBlue, accentViolet,
        success, warning, danger,
    ]

    // MARK: - Tipografi (brief 3)

    /// Terminal tipografisi varsayılanları. `AppSettings` bu değerlerle başlar.
    enum Typography {
        /// brief: "SF Mono — 13 pt". macOS bu aileyi `NSFontManager` üzerinden vermez;
        /// `FontCatalog.resolvedFont` sistem monospace API'siyle aynı yazı tipini üretir.
        static let terminalFontFamily = "SF Mono"
        static let terminalFontSize: Double = 13
        /// brief: "Line Height — 1.25".
        static let terminalLineHeight: Double = 1.25
    }
}
