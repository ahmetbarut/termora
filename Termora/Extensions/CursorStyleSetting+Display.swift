import Foundation

extension CursorStyleSetting {
    /// Ayarlar penceresindeki imleç şekli seçicisinde görünen ad.
    var displayName: String {
        switch self {
        case .blinkBlock: return "Blok (yanıp sönen)"
        case .steadyBlock: return "Blok (sabit)"
        case .blinkUnderline: return "Alt çizgi (yanıp sönen)"
        case .steadyUnderline: return "Alt çizgi (sabit)"
        case .blinkBar: return "Çubuk (yanıp sönen)"
        case .steadyBar: return "Çubuk (sabit)"
        }
    }
}
