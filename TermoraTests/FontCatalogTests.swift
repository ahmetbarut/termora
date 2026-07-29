import AppKit
import CoreText
import Testing
@testable import Termora

@Suite("Font kataloğu")
struct FontCatalogTests {

    @Test func onlyFixedPitchFamiliesSurvive() {
        let fixedPitch: Set<String> = ["Menlo", "SF Mono"]
        let result = FontCatalog.monospacedFamilies(
            from: ["Helvetica", "SF Mono", "Times New Roman", "Menlo"],
            isFixedPitch: { fixedPitch.contains($0) }
        )
        #expect(result == ["Menlo", "SF Mono"])
    }

    @Test func fallbackFamilyIsAlwaysPresent() {
        let result = FontCatalog.monospacedFamilies(
            from: ["Helvetica", "Times New Roman"],
            isFixedPitch: { _ in false }
        )
        #expect(result == ["Menlo"])
        #expect(FontCatalog.fallbackFamily == "Menlo")
    }

    @Test func duplicatesRemovedAndOrderIsCaseInsensitive() {
        let result = FontCatalog.monospacedFamilies(
            from: ["Zed Mono", "Menlo", "andale Mono", "Menlo"],
            isFixedPitch: { _ in true }
        )
        #expect(result == ["andale Mono", "Menlo", "Zed Mono"])
    }

    @Test func emptyInputStillYieldsUsableList() {
        let result = FontCatalog.monospacedFamilies(from: [], isFixedPitch: { _ in true })
        #expect(result == ["Menlo"])
    }

    // MARK: - brief 3 "Alternatif fontlar"

    @Test func recommendedFamiliesFollowTheBriefOrder() {
        #expect(FontCatalog.recommendedFamilies ==
                ["SF Mono", "JetBrains Mono", "Menlo", "Monaco", "Fira Code", "MesloLGS NF"])
        #expect(FontCatalog.defaultFamily == "SF Mono")
    }

    @Test func menuPutsInstalledRecommendationsFirstInBriefOrder() {
        let installed: Set<String> = ["Menlo", "Monaco", "Fira Code", "Andale Mono", "Courier"]
        let menu = FontCatalog.menu(
            from: ["Courier", "Fira Code", "Andale Mono", "Helvetica", "Monaco", "Menlo"],
            isFixedPitch: { installed.contains($0) }
        )
        // SF Mono sistem fontu: NSFontManager listelemez ama her zaman çözülebilir.
        #expect(menu.recommended == ["SF Mono", "Menlo", "Monaco", "Fira Code"])
        #expect(menu.others == ["Andale Mono", "Courier"])
        #expect(menu.allFamilies == ["SF Mono", "Menlo", "Monaco", "Fira Code", "Andale Mono", "Courier"])
    }

    @Test func menuNeverOffersAFontThatIsNotInstalled() {
        let menu = FontCatalog.menu(from: ["Helvetica"], isFixedPitch: { _ in false })
        #expect(menu.recommended == ["SF Mono", "Menlo"])
        #expect(menu.others.isEmpty)
        #expect(!menu.allFamilies.contains("JetBrains Mono"))
        #expect(!menu.allFamilies.contains("MesloLGS NF"))
        #expect(!menu.allFamilies.contains("Helvetica"))
    }

    @Test func menuListsEveryFamilyOnlyOnce() {
        let menu = FontCatalog.menu(from: ["Menlo", "Menlo", "Monaco"], isFixedPitch: { _ in true })
        #expect(Set(menu.allFamilies).count == menu.allFamilies.count)
    }

    // Step 20'de `SessionManager.resolveFont`'un yerini aldığı için font çözümlemesinin
    // karakterizasyon testleri de buraya taşınır.

    @Test func resolvedFontFallsBackWhenTheFamilyIsMissingOrUnknown() {
        #expect(FontCatalog.resolvedFont(name: nil, size: 13).pointSize == 13)
        #expect(FontCatalog.resolvedFont(name: "", size: 17).pointSize == 17)
        #expect(FontCatalog.resolvedFont(name: "ThereIsNoSuchFont-42", size: 17).pointSize == 17)
    }

    @Test func resolvedFontHonoursAnInstalledFamily() {
        let menlo = FontCatalog.resolvedFont(name: "Menlo", size: 15)
        #expect(menlo.familyName == "Menlo")
        #expect(menlo.pointSize == 15)
    }

    /// brief 3 varsayılanı SF Mono; macOS onu aile adıyla vermez, sessizce Menlo'ya
    /// düşmek yerine sistem monospace fontu (aynı yazı tipi) döndürülmeli.
    @Test func sfMonoResolvesToASystemMonospaceFontInsteadOfMenlo() {
        let font = FontCatalog.resolvedFont(name: FontCatalog.defaultFamily, size: 14)
        #expect(font.isFixedPitch)
        #expect(Double(font.pointSize) == 14)
        #expect(font.familyName != "Menlo")
    }

    @Test func resolvedFontSizeIsClamped() {
        // `Double(...)` şart: `pointSize` CGFloat'tır ve #expect içinde iki taraf AnyHashable'a
        // kutulanır. AnyHashable(CGFloat(32)) != AnyHashable(Double(32)) olduğundan, açık
        // dönüşüm olmadan bu karşılaştırma değerler eşitken bile HER ZAMAN başarısız olur.
        #expect(Double(FontCatalog.resolvedFont(name: nil, size: 400).pointSize) == SettingsLimits.fontSizeRange.upperBound)
        #expect(Double(FontCatalog.resolvedFont(name: nil, size: 1).pointSize) == SettingsLimits.fontSizeRange.lowerBound)
    }

    // MARK: - brief 3 "Ligature desteği kullanıcı tarafından açılıp kapatılabilmelidir"

    /// Bir satırdaki glyph sayısı.
    ///
    /// Ölçüm Helvetica ile yapılır, terminal fontuyla değil: bu makinede ligature içeren
    /// hiçbir monospace font (Fira Code, JetBrains Mono, MesloLGS NF) kurulu olmayabilir ve
    /// `resolvedFont`'un sözleşmesi aileye bağlı değildir. Helvetica her macOS'ta bulunur ve
    /// "fi" ligature'ını kesin taşır, yani ayarın etkisini ölçebileceğimiz tek güvenilir zemin.
    private func glyphCount(of text: String, in font: NSFont) -> Int {
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [.font: font])
        )
        return CTLineGetGlyphCount(line)
    }

    /// SwiftTerm bir satırı `CTLine` olarak çizer ve her glyph'i `sütun × glyphIndex` ile
    /// konumlandırır (`AppleTerminalView`, "Pre-create CTLines" döngüsü). Ligature iki
    /// karakteri tek glyph'e indirdiğinde satırın geri kalanı bir sütun kayar. Attributed
    /// string'i SwiftTerm kurduğu için Termora'nın tek müdahale noktası fontun kendisidir:
    /// ligature'ı font descriptor'ında kapatmak.
    @Test func ligaturesOffYieldsAFontCoreTextWillNotMergeGlyphsWith() {
        let on = FontCatalog.resolvedFont(name: "Helvetica", size: 13, usesLigatures: true)
        let off = FontCatalog.resolvedFont(name: "Helvetica", size: 13, usesLigatures: false)
        #expect(glyphCount(of: "fi", in: on) == 1)
        #expect(glyphCount(of: "fi", in: off) == 2)
    }

    /// Varsayılan kapalı. Terminalde hizalama doğruluğu tipografik zarafetten önce gelir
    /// (briefs/2 MVP kriteri: "Unicode ve emoji hizalaması bozulmuyor"); ligature isteyen
    /// kullanıcı onu açıkça açar.
    @Test func ligaturesAreOffUnlessTheCallerAsksForThem() {
        #expect(glyphCount(of: "fi", in: FontCatalog.resolvedFont(name: "Helvetica", size: 13)) == 2)
    }

    @Test func disablingLigaturesChangesNothingElseAboutTheFont() {
        let font = FontCatalog.resolvedFont(name: "Menlo", size: 15, usesLigatures: false)
        #expect(font.familyName == "Menlo")
        #expect(font.pointSize == 15)
        #expect(font.isFixedPitch)
    }

    /// Aile çözülemediğinde geri düşülen fontta da ayar geçerli olmalı — aksi hâlde
    /// kullanıcı bilinmeyen bir font seçtiğinde ligature sessizce geri gelirdi.
    @Test func theFallbackFontHonoursTheLigatureSettingToo() {
        let font = FontCatalog.resolvedFont(name: "ThereIsNoSuchFont-42", size: 13, usesLigatures: false)
        #expect(glyphCount(of: "fi", in: font) == 2)
    }
}
