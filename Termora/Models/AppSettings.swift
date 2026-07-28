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
    /// brief 3 "Tipografi": varsayilan terminal fontu SF Mono 13 pt, satir yuksekligi 1.25.
    /// SF Mono kurulu degilse `FontCatalog.resolvedFont` sistem monospace fontuna,
    /// o da yoksa Menlo'ya duser — geri dusus zinciri korunur.
    var fontName: String? = DesignTokens.Typography.terminalFontFamily
    var fontSize: Double = DesignTokens.Typography.terminalFontSize
    var lineSpacing: Double = DesignTokens.Typography.terminalLineHeight
    var cursorStyle: CursorStyleSetting = .blinkBlock
    var themeID: String = "termora-dark"
    var windowOpacity: Double = 1.0
    var scrollbackLines: Int = 10_000
    var defaultShellPath: String? = nil
    var startupDirectory: String? = nil
    var showStatusBar: Bool = true
    /// brief 3 "İlk Açılış Akışı": ilk açılış akışı yalnızca bir kez gösterilir.
    /// Akış tamamlandığında **ve atlandığında** true olur.
    var hasCompletedOnboarding: Bool = false

    init() {}

    /// Elle yazılmış çözücü: Swift'in ürettiği `init(from:)` eksik anahtarlarda
    /// varsayılan değere DÜŞMEZ, `keyNotFound` fırlatır. Sentezlenmiş hâlde kalsaydı
    /// yeni bir alan eklemek, diskteki eski blobu `SettingsStore` gözünde bozuk yapar
    /// ve kullanıcının tüm ayarları sıfırlanırdı. Her alan `decodeIfPresent` ile okunur.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        fontName = try container.decodeIfPresent(String.self, forKey: .fontName) ?? defaults.fontName
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? defaults.fontSize
        lineSpacing = try container.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? defaults.lineSpacing
        // Ham değer üzerinden okunur: ileride eklenen bir imleç stili (`RawValue` eşleşmez)
        // enum'a doğrudan çözdürülseydi TÜM ayarlar çözülemez, `SettingsStore` blob'u
        // yedeğe atar ve kullanıcının her ayarı sıfırlanırdı. Yalnız bu alan düşer.
        cursorStyle = try container.decodeIfPresent(String.self, forKey: .cursorStyle)
            .flatMap(CursorStyleSetting.init(rawValue:)) ?? defaults.cursorStyle
        themeID = try container.decodeIfPresent(String.self, forKey: .themeID) ?? defaults.themeID
        windowOpacity = try container.decodeIfPresent(Double.self, forKey: .windowOpacity) ?? defaults.windowOpacity
        scrollbackLines = try container.decodeIfPresent(Int.self, forKey: .scrollbackLines) ?? defaults.scrollbackLines
        defaultShellPath = try container.decodeIfPresent(String.self, forKey: .defaultShellPath)
        startupDirectory = try container.decodeIfPresent(String.self, forKey: .startupDirectory)
        showStatusBar = try container.decodeIfPresent(Bool.self, forKey: .showStatusBar) ?? defaults.showStatusBar
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding)
            ?? defaults.hasCompletedOnboarding
    }
}
