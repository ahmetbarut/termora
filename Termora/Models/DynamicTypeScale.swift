import SwiftUI

/// briefs/1 ve briefs/2 "Erişilebilirlik": sistem yazı boyutu tercihinin arayüze
/// uygulanması.
///
/// Ayrı ve saf bir tip: ölçeğin sınırlı olduğu ve terminal fontuna DOKUNMADIĞI, görünüm
/// çizilmeden sınanabilmeli.
enum DynamicTypeScale {

    /// Üst sınır. Sınırsız ölçek, dar bir pencerede her satırı sarar ve briefs/3'ün
    /// "küçük pencerede bozulmamalı" kuralını çiğnerdi.
    static let maximumFactor = 1.6

    /// Terminal fontu sistem tercihini İZLEMEZ.
    ///
    /// Sebebi erişilebilirlik karşıtı değil, tam tersi: terminalin sütun sayısı font
    /// boyutundan hesaplanıyor. Sistem yazısı büyüdüğünde terminal de büyüseydi, çalışan
    /// programın gördüğü satır genişliği kullanıcıya haber verilmeden değişir ve `vim`
    /// gibi tam ekran uygulamaların çizimi bozulurdu. Terminal boyutu Ayarlar ▸
    /// Appearance'ta, kullanıcının kendi elinde.
    static let appliesToTerminalFont = false

    /// Sistem boyutunu bir puntoya uygular.
    static func scaled(_ size: Double, for category: DynamicTypeSize) -> Double {
        size * factor(for: category)
    }

    /// `DynamicTypeSize` sıralı bir enum; `.large` sistemin varsayılanı ve ölçeği 1.0.
    private static func factor(for category: DynamicTypeSize) -> Double {
        switch category {
        case .xSmall: 0.85
        case .small: 0.92
        case .medium: 0.96
        case .large: 1.0
        case .xLarge: 1.08
        case .xxLarge: 1.16
        case .xxxLarge: 1.24
        // Erişilebilirlik boyutları tavana dayanır: daha da büyümek düzeni bozardı.
        default: maximumFactor
        }
    }
}
