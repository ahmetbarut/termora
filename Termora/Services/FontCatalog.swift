import AppKit

/// Terminal için kullanılabilir sabit genişlikli (monospace) font ailelerini
/// listeler ve ayarlardaki aile adını gerçek bir `NSFont`'a çözer.
enum FontCatalog {

    /// Her macOS kurulumunda bulunan güvenli varsayılan.
    static let fallbackFamily = "Menlo"

    /// brief 3 "Tipografi": varsayılan terminal fontu.
    static let defaultFamily = DesignTokens.Typography.terminalFontFamily

    /// brief 3 "Alternatif fontlar" — listede brief'teki sırayla, önerilen grupta gösterilir.
    /// Kurulu olmayanlar listelenmez (seçilse çözülemez, sessizce başka bir fonta düşerdi).
    static let recommendedFamilies = [
        defaultFamily, "JetBrains Mono", "Menlo", "Monaco", "Fira Code", "MesloLGS NF",
    ]

    /// Font seçicisinin iki bölümü: önerilenler (brief sırası) ve kalan kurulu aileler (alfabetik).
    struct FontMenu: Equatable {
        var recommended: [String]
        var others: [String]

        var allFamilies: [String] { recommended + others }
    }

    /// Saf çekirdek. `defaultFamily` her zaman önerilenlerde: SF Mono bir sistem fontudur,
    /// `NSFontManager.availableFontFamilies` onu listelemez ama `resolvedFont` her zaman
    /// üretebilir. Diğer öneriler yalnızca gerçekten kuruluysa görünür.
    static func menu(from families: [String], isFixedPitch: (String) -> Bool) -> FontMenu {
        let installed = monospacedFamilies(from: families, isFixedPitch: isFixedPitch)
        var offerable = Set(installed)
        offerable.insert(defaultFamily)
        let recommended = recommendedFamilies.filter { offerable.contains($0) }
        let recommendedSet = Set(recommended)
        let others = installed.filter { !recommendedSet.contains($0) }
        return FontMenu(recommended: recommended, others: others)
    }

    @MainActor
    static func availableFontMenu() -> FontMenu {
        menu(
            from: NSFontManager.shared.availableFontFamilies,
            isFixedPitch: { isFixedPitchFamily($0) }
        )
    }

    /// Saf çekirdek: dosya sistemi/AppKit dokunuşu yok, `isFixedPitch` dikişiyle test edilir.
    /// Tekrarlar atılır, `fallbackFamily` her zaman listede olur, sonuç harf duyarsız sıralanır.
    static func monospacedFamilies(from families: [String], isFixedPitch: (String) -> Bool) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for family in families where isFixedPitch(family) {
            if seen.insert(family).inserted {
                result.append(family)
            }
        }
        if seen.insert(fallbackFamily).inserted {
            result.append(fallbackFamily)
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    @MainActor
    static func isFixedPitchFamily(_ family: String) -> Bool {
        guard let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 12) else {
            return false
        }
        return font.isFixedPitch
    }

    /// Ayarlardaki aile adı + boyuttan gerçek fontu üretir; aile bulunamazsa Menlo'ya,
    /// o da yoksa sistem monospace fontuna düşer.
    ///
    /// `usesLigatures` kapalıyken ligature font descriptor'ında kapatılır. Bu, Termora'nın
    /// elindeki tek kaldıraç: terminal metnini `NSAttributedString`'e SwiftTerm çevirir,
    /// yani `.ligature` özniteliğini biz veremeyiz — ama verdiğimiz fontu Core Text dinler.
    @MainActor
    static func resolvedFont(name: String?, size: Double, usesLigatures: Bool = false) -> NSFont {
        let clampedSize = SettingsLimits.clampFontSize(size)
        return applyingLigatureSetting(baseFont(name: name, size: clampedSize), usesLigatures: usesLigatures)
    }

    @MainActor
    private static func baseFont(name: String?, size: CGFloat) -> NSFont {
        if let name, !name.isEmpty {
            if let font = NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: size) {
                return font
            }
            // SF Mono macOS'ta font panelinde/`availableFontFamilies`'te GÖRÜNMEZ ve
            // PostScript adıyla da açılmaz (sistem fontu). Aksi hâlde brief'in varsayılanı
            // sessizce Menlo'ya düşerdi; `monospacedSystemFont` aynı yazı tipini verir.
            if name.caseInsensitiveCompare(defaultFamily) == .orderedSame {
                return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            }
        }
        if let font = NSFont(name: fallbackFamily, size: size) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Ligature açıkken font olduğu gibi döner: hangi ligature'ları sunacağına font karar
    /// verir. Kapalıyken `kCommonLigaturesOffSelector` eklenir; descriptor'dan font
    /// üretilemezse ligature'lı hâli döndürmek, hiç font döndürmemekten iyidir.
    private static func applyingLigatureSetting(_ font: NSFont, usesLigatures: Bool) -> NSFont {
        guard !usesLigatures else { return font }
        let descriptor = font.fontDescriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kLigaturesType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kCommonLigaturesOffSelector,
            ]],
        ])
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }
}
