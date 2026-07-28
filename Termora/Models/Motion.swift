import SwiftUI

/// brief 3 "Animasyonlar" bölümünün tek doğruluk kaynağı.
///
/// İki kural burada kilitlenir ve görünümlerde bir daha tartışılmaz:
///
/// 1. **Süre penceresi.** Brief `120–180 ms` der. Görünümlerde çıplak `0.2` yazılamaz;
///    her geçiş bir `Speed` seçer, `MotionTests` de her `Speed`'in pencerede kaldığını
///    doğrular. Yeni bir hız eklenirse test onu da otomatik denetler (`allCases`).
///
/// 2. **Reduce Motion.** Sistem tercihi açıkken `animation(_:reduceMotion:)` `nil` döner.
///    `nil` bilinçli bir seçimdir: `.animation(nil, value:)` SwiftUI'a "bu değişim için
///    hiç geçiş kurma" der; `0 sn`'lik bir animasyon kurmaktan farklıdır (o hâlâ bir
///    geçiş nesnesi üretir ve bazı sarmalayıcılar onu görünür bir kareye yayar).
///
/// Brief ayrıca terminal metnine, imlece ve çıktısına DEKORATİF animasyon uygulanmasını
/// yasaklar: bu tip yalnız çevre arayüzde (sekme değişimi, hover, panel göstergeleri)
/// kullanılır, `TermoraTerminalView` yüzeyinde kullanılmaz.
enum Motion {

    /// Brief'in izin verdiği kapalı aralık, saniye cinsinden.
    static let durationRange: ClosedRange<Double> = 0.120...0.180

    /// Brief'in animasyona izin verdiği yüzeyler üç hız sınıfına düşer. İsimler kullanım
    /// yerini anlatır (süreyi değil), böylece bir hız ayarlandığında çağrı yerleri değişmez.
    enum Speed: CaseIterable {
        /// İmleç bir öğenin üstüne geldiğinde: en kısa geçiş, gecikme hissi olmamalı.
        case hover
        /// Seçim değişimi (aktif sekme, aktif panel göstergesi).
        case selection
        /// Panel/çubuk açılıp kapanması (sidebar, AI paneli, komut paleti).
        case panel

        /// Saniye cinsinden süre. Hepsi `durationRange` içindedir.
        var duration: Double {
            switch self {
            case .hover: return 0.120
            case .selection: return 0.150
            case .panel: return 0.180
            }
        }
    }

    /// Reduce Motion açıkken süre YOKTUR — çağıran taraf bunu "tek karede uygula" diye okur.
    static func duration(_ speed: Speed, reduceMotion: Bool) -> Double? {
        reduceMotion ? nil : speed.duration
    }

    /// Doğrudan `.animation(_:value:)`'a verilebilecek geçiş; Reduce Motion açıkken `nil`.
    ///
    /// Eğri `easeOut`: değişim hemen görünür hâle gelir ve sonunda yavaşlar — arayüz
    /// değişimlerinde `easeInOut`'tan daha çabuk tepki veriyormuş gibi hissettirir.
    static func animation(_ speed: Speed, reduceMotion: Bool) -> Animation? {
        guard let duration = duration(speed, reduceMotion: reduceMotion) else { return nil }
        return .easeOut(duration: duration)
    }
}

// MARK: - Görünüm bağlaması

/// `Motion`'ı sistem tercihine bağlayan tek yer. Görünümler `@Environment` okumasını
/// tekrarlamaz; `.motionAnimation(.selection, value: isActive)` yazar.
private struct MotionAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let speed: Motion.Speed
    let value: Value

    func body(content: Content) -> some View {
        content.animation(Motion.animation(speed, reduceMotion: reduceMotion), value: value)
    }
}

extension View {
    /// `value` değiştiğinde brief penceresindeki bir geçiş uygular; sistemin "Reduce Motion"
    /// tercihi açıkken hiç geçiş kurmaz.
    func motionAnimation(_ speed: Motion.Speed, value: some Equatable) -> some View {
        modifier(MotionAnimationModifier(speed: speed, value: value))
    }
}
