import AppKit

/// brief 3 "Erişilebilirlik → Kontrast oranı korunmalı".
///
/// WCAG 2.1'in kontrast oranı hesabı (SC 1.4.3 / 1.4.11). Saf fonksiyon: girdi iki renk,
/// çıktı `1.0 ... 21.0` arası bir sayı. Renk seçmez, renk düzeltmez — yalnız ölçer.
/// `ContrastRatioTests` hem hesabın kendisini bilinen referanslarla hem de marka paletinin
/// eşikleri geçtiğini doğrular, böylece bir hex karartıldığında test kırılır.
enum ContrastRatio {

    // MARK: - WCAG eşikleri

    /// Gövde metni için AA sınırı (WCAG 2.1 SC 1.4.3).
    static let normalText: Double = 4.5
    /// Büyük metin ve arayüz bileşenleri için AA sınırı (SC 1.4.3 / 1.4.11).
    /// Durum noktası, aktif panel border'ı ve aktif sekme çizgisi bu sınıfa girer.
    static let largeTextOrUIComponent: Double = 3.0
    /// Gövde metni için AAA sınırı (SC 1.4.6).
    static let enhancedText: Double = 7.0

    // MARK: - Hesap

    /// Bir sRGB kanalının doğrusallaştırılması (WCAG'ın gama düzeltmesi).
    /// Bu adım atlanırsa oranlar sistematik olarak yanlış çıkar — `#767676`/beyaz
    /// referansı (4.54 : 1) hatayı yakalar.
    static func linearized(channel value: Double) -> Double {
        value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    /// WCAG bağıl parlaklığı: `0` (siyah) … `1` (beyaz).
    ///
    /// Renk sRGB'ye çevrilir; katalog renkleri (`NSColor.textColor` gibi) bileşen
    /// okumadan önce dönüştürülmezse `redComponent` çağrısı çöker.
    static func relativeLuminance(_ color: NSColor) -> Double {
        guard let srgb = color.usingColorSpace(.sRGB) else { return 0 }
        let red = linearized(channel: Double(srgb.redComponent))
        let green = linearized(channel: Double(srgb.greenComponent))
        let blue = linearized(channel: Double(srgb.blueComponent))
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    /// İki rengin kontrast oranı. Simetriktir (sıra önemsizdir) ve `1.0 ... 21.0` aralığındadır.
    ///
    /// Not: alfa kanalı YOK SAYILIR. WCAG oranı yalnız iki opak renk için tanımlıdır;
    /// yarı saydam bir katman ölçülecekse önce zeminiyle harmanlanmalıdır.
    static func ratio(_ first: NSColor, _ second: NSColor) -> Double {
        let a = relativeLuminance(first)
        let b = relativeLuminance(second)
        let lighter = max(a, b)
        let darker = min(a, b)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// `ratio` verilen eşiği geçiyor mu?
    static func passes(_ ratio: Double, threshold: Double) -> Bool {
        ratio >= threshold
    }
}
