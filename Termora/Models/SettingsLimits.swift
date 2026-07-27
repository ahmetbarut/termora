import Foundation

/// Kullanıcı ayarları için tek doğruluk kaynağı olan sayısal sınırlar.
/// Hem Ayarlar UI'ı hem de terminale uygulama yolu buradan geçer.
enum SettingsLimits {

    static let scrollbackRange: ClosedRange<Int> = 100...100_000
    static let fontSizeRange: ClosedRange<Double> = 8...32
    static let lineSpacingRange: ClosedRange<Double> = 1.0...1.6
    static let opacityRange: ClosedRange<Double> = 0.5...1.0

    static let defaultFontSize: Double = 13

    static func clampScrollback(_ value: Int) -> Int {
        min(max(value, scrollbackRange.lowerBound), scrollbackRange.upperBound)
    }

    static func clampFontSize(_ value: Double) -> Double {
        guard !value.isNaN else { return defaultFontSize }
        return min(max(value, fontSizeRange.lowerBound), fontSizeRange.upperBound)
    }

    static func clampLineSpacing(_ value: Double) -> Double {
        guard !value.isNaN else { return lineSpacingRange.lowerBound }
        return min(max(value, lineSpacingRange.lowerBound), lineSpacingRange.upperBound)
    }

    static func clampOpacity(_ value: Double) -> Double {
        guard !value.isNaN else { return opacityRange.upperBound }
        return min(max(value, opacityRange.lowerBound), opacityRange.upperBound)
    }

    /// Scrollback metin alanı için: ayrıştırılamayan girdi `fallback`'e düşer,
    /// her iki durumda da sonuç `scrollbackRange` içine sıkıştırılır.
    static func scrollback(fromText text: String, fallback: Int) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Int(trimmed) else { return clampScrollback(fallback) }
        return clampScrollback(parsed)
    }
}
