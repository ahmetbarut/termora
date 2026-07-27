import Testing
@testable import Termora

@Suite("Ayar sınırları")
struct SettingsLimitsTests {

    @Test func scrollbackClampsToRange() {
        #expect(SettingsLimits.clampScrollback(50) == 100)
        #expect(SettingsLimits.clampScrollback(100) == 100)
        #expect(SettingsLimits.clampScrollback(10_000) == 10_000)
        #expect(SettingsLimits.clampScrollback(100_000) == 100_000)
        #expect(SettingsLimits.clampScrollback(250_000) == 100_000)
    }

    @Test func scrollbackTextParsingFallsBackOnGarbage() {
        #expect(SettingsLimits.scrollback(fromText: "4200", fallback: 10_000) == 4200)
        #expect(SettingsLimits.scrollback(fromText: "  8000 ", fallback: 10_000) == 8000)
        #expect(SettingsLimits.scrollback(fromText: "", fallback: 10_000) == 10_000)
        #expect(SettingsLimits.scrollback(fromText: "abc", fallback: 10_000) == 10_000)
        #expect(SettingsLimits.scrollback(fromText: "999999", fallback: 10_000) == 100_000)
    }

    @Test func scrollbackTextFallbackIsItselfClamped() {
        #expect(SettingsLimits.scrollback(fromText: "abc", fallback: 5) == 100)
        #expect(SettingsLimits.scrollback(fromText: "abc", fallback: 500_000) == 100_000)
    }

    @Test func lineSpacingAndOpacityAndFontSizeClamp() {
        #expect(SettingsLimits.clampLineSpacing(0.5) == 1.0)
        #expect(SettingsLimits.clampLineSpacing(1.25) == 1.25)
        #expect(SettingsLimits.clampLineSpacing(9.0) == 1.6)
        #expect(SettingsLimits.clampOpacity(0.1) == 0.5)
        #expect(SettingsLimits.clampOpacity(0.75) == 0.75)
        #expect(SettingsLimits.clampOpacity(1.5) == 1.0)
        #expect(SettingsLimits.clampFontSize(2) == 8)
        #expect(SettingsLimits.clampFontSize(13) == 13)
        #expect(SettingsLimits.clampFontSize(99) == 32)
    }

    @Test func nonFiniteValuesFallBackToSafeDefaults() {
        #expect(SettingsLimits.clampFontSize(.nan) == 13)
        #expect(SettingsLimits.clampLineSpacing(.nan) == 1.0)
        #expect(SettingsLimits.clampOpacity(.nan) == 1.0)
        #expect(SettingsLimits.clampFontSize(.infinity) == 32)
    }
}
