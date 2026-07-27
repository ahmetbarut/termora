import Foundation

extension CursorStyleSetting {
    /// Ayarlar penceresindeki imleç şekli seçicisinde görünen ad.
    /// brief 3 "Uygulama Metin Dili": arayüz metinleri İngilizce, kısa ve teknik.
    var displayName: String {
        switch self {
        case .blinkBlock: return "Block (blinking)"
        case .steadyBlock: return "Block (steady)"
        case .blinkUnderline: return "Underline (blinking)"
        case .steadyUnderline: return "Underline (steady)"
        case .blinkBar: return "Bar (blinking)"
        case .steadyBar: return "Bar (steady)"
        }
    }
}
