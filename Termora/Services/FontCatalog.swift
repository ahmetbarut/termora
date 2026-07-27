import AppKit

/// Terminal için kullanılabilir sabit genişlikli (monospace) font ailelerini
/// listeler ve ayarlardaki aile adını gerçek bir `NSFont`'a çözer.
enum FontCatalog {

    /// Her macOS kurulumunda bulunan güvenli varsayılan.
    static let fallbackFamily = "Menlo"

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

    @MainActor
    static func availableMonospacedFamilies() -> [String] {
        monospacedFamilies(
            from: NSFontManager.shared.availableFontFamilies,
            isFixedPitch: { isFixedPitchFamily($0) }
        )
    }

    /// Ayarlardaki aile adı + boyuttan gerçek fontu üretir; aile bulunamazsa Menlo'ya,
    /// o da yoksa sistem monospace fontuna düşer.
    @MainActor
    static func resolvedFont(name: String?, size: Double) -> NSFont {
        let clampedSize = SettingsLimits.clampFontSize(size)
        if let name, !name.isEmpty,
           let font = NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: clampedSize) {
            return font
        }
        if let font = NSFont(name: fallbackFamily, size: clampedSize) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: clampedSize, weight: .regular)
    }
}
