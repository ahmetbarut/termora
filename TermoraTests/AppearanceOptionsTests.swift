import Testing
@testable import Termora

@Suite("Görünüm seçenekleri")
struct AppearanceOptionsTests {

    @Test func everyCursorStyleHasUniqueNonEmptyDisplayName() {
        let names = CursorStyleSetting.allCases.map(\.displayName)
        #expect(names.count == 6)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
    }

    /// brief 3 "Uygulama Metin Dili": arayüz metinleri İngilizce.
    @Test func displayNamesAreEnglish() {
        #expect(CursorStyleSetting.blinkBlock.displayName == "Block (blinking)")
        #expect(CursorStyleSetting.steadyBlock.displayName == "Block (steady)")
        #expect(CursorStyleSetting.blinkUnderline.displayName == "Underline (blinking)")
        #expect(CursorStyleSetting.steadyUnderline.displayName == "Underline (steady)")
        #expect(CursorStyleSetting.blinkBar.displayName == "Bar (blinking)")
        #expect(CursorStyleSetting.steadyBar.displayName == "Bar (steady)")
    }

    @Test func blockStylesAreDistinguishedByBlinking() {
        #expect(CursorStyleSetting.blinkBlock.displayName != CursorStyleSetting.steadyBlock.displayName)
        #expect(CursorStyleSetting.blinkBar.displayName != CursorStyleSetting.steadyBar.displayName)
        #expect(CursorStyleSetting.blinkUnderline.displayName != CursorStyleSetting.steadyUnderline.displayName)
    }
}
