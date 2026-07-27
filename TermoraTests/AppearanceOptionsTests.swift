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

    @Test func blockStylesAreDistinguishedByBlinking() {
        #expect(CursorStyleSetting.blinkBlock.displayName != CursorStyleSetting.steadyBlock.displayName)
        #expect(CursorStyleSetting.blinkBar.displayName != CursorStyleSetting.steadyBar.displayName)
        #expect(CursorStyleSetting.blinkUnderline.displayName != CursorStyleSetting.steadyUnderline.displayName)
    }
}
