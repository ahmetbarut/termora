import Foundation
import SwiftTerm

/// Imlec stilinin kalici (Codable) karsiligi. `rawValue`'lar kalicilik sozlesmesidir,
/// degistirilirse kayitli ayarlar okunamaz.
enum CursorStyleSetting: String, Codable, CaseIterable {
    case blinkBlock
    case steadyBlock
    case blinkUnderline
    case steadyUnderline
    case blinkBar
    case steadyBar

    var swiftTermStyle: SwiftTerm.CursorStyle {
        switch self {
        case .blinkBlock: return .blinkBlock
        case .steadyBlock: return .steadyBlock
        case .blinkUnderline: return .blinkUnderline
        case .steadyUnderline: return .steadyUnderline
        case .blinkBar: return .blinkBar
        case .steadyBar: return .steadyBar
        }
    }
}

/// Uygulama genelindeki kullanici ayarlari. `SettingsStore` tarafindan UserDefaults'a
/// JSON olarak yazilir; yeni alanlar varsayilan degerle eklenmelidir ki eski bloblar
/// cozulmeye devam etsin.
struct AppSettings: Codable, Equatable {
    var fontName: String? = nil
    var fontSize: Double = 13
    var lineSpacing: Double = 1.0
    var cursorStyle: CursorStyleSetting = .blinkBlock
    var themeID: String = "termora-dark"
    var windowOpacity: Double = 1.0
    var scrollbackLines: Int = 10_000
    var defaultShellPath: String? = nil
    var startupDirectory: String? = nil
    var showStatusBar: Bool = true
}
