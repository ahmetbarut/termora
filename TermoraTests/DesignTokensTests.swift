import AppKit
import Testing
@testable import Termora

/// brief 3 "Marka Kimliği → Ana Renkler" ve "Tipografi" bloklarının tek kaynak olarak
/// `DesignTokens`'ta durduğunu doğrular. Hex değerleri brief'ten birebir alınmıştır.
@MainActor
@Suite("Tasarım tokenleri")
struct DesignTokensTests {

    /// brief 3'teki 12 renk, brief'teki sırayla.
    private static let briefColors: [(name: String, hex: String)] = [
        ("Background Primary", "#080B18"),
        ("Background Secondary", "#0E1326"),
        ("Background Elevated", "#151B32"),
        ("Border", "#252C45"),
        ("Text Primary", "#F4F6FF"),
        ("Text Secondary", "#9CA5BE"),
        ("Text Muted", "#68718B"),
        ("Accent Blue", "#169CFF"),
        ("Accent Violet", "#7A3CFF"),
        ("Success", "#32D583"),
        ("Warning", "#F5B942"),
        ("Danger", "#FF5D67"),
    ]

    @Test func paletteMatchesTheBriefExactly() {
        #expect(DesignTokens.all.count == 12)
        #expect(DesignTokens.all.map(\.name) == Self.briefColors.map(\.name))
        #expect(DesignTokens.all.map(\.hex) == Self.briefColors.map(\.hex))
    }

    @Test func namedAccessorsPointAtTheRightToken() {
        #expect(DesignTokens.backgroundPrimary.hex == "#080B18")
        #expect(DesignTokens.backgroundSecondary.hex == "#0E1326")
        #expect(DesignTokens.backgroundElevated.hex == "#151B32")
        #expect(DesignTokens.border.hex == "#252C45")
        #expect(DesignTokens.textPrimary.hex == "#F4F6FF")
        #expect(DesignTokens.textSecondary.hex == "#9CA5BE")
        #expect(DesignTokens.textMuted.hex == "#68718B")
        #expect(DesignTokens.accentBlue.hex == "#169CFF")
        #expect(DesignTokens.accentViolet.hex == "#7A3CFF")
        #expect(DesignTokens.success.hex == "#32D583")
        #expect(DesignTokens.warning.hex == "#F5B942")
        #expect(DesignTokens.danger.hex == "#FF5D67")
    }

    @Test func everyTokenHasAUniqueNameAndParsableHex() {
        #expect(Set(DesignTokens.all.map(\.name)).count == DesignTokens.all.count)
        #expect(Set(DesignTokens.all.map(\.hex)).count == DesignTokens.all.count)
        for token in DesignTokens.all {
            #expect(token.hex.hasPrefix("#"))
            #expect(token.hex.count == 7)
            #expect(NSColor(hexString: token.hex) != nil, "Ayrıştırılamayan token: \(token.name)")
        }
    }

    @Test func hexIsSplitIntoTheExpectedChannels() throws {
        let accent = try #require(DesignTokens.accentBlue.nsColor.usingColorSpace(.sRGB))
        #expect(abs(accent.redComponent - CGFloat(0x16) / 255.0) < 0.001)
        #expect(abs(accent.greenComponent - CGFloat(0x9C) / 255.0) < 0.001)
        #expect(abs(accent.blueComponent - 1.0) < 0.001)

        let violet = try #require(DesignTokens.accentViolet.nsColor.usingColorSpace(.sRGB))
        #expect(abs(violet.redComponent - CGFloat(0x7A) / 255.0) < 0.001)
        #expect(abs(violet.greenComponent - CGFloat(0x3C) / 255.0) < 0.001)
        #expect(abs(violet.blueComponent - 1.0) < 0.001)

        let danger = try #require(DesignTokens.danger.nsColor.usingColorSpace(.sRGB))
        #expect(abs(danger.redComponent - 1.0) < 0.001)
        #expect(abs(danger.greenComponent - CGFloat(0x5D) / 255.0) < 0.001)
        #expect(abs(danger.blueComponent - CGFloat(0x67) / 255.0) < 0.001)
    }

    @Test func typographyDefaultsMatchTheBrief() {
        #expect(DesignTokens.Typography.terminalFontFamily == "SF Mono")
        #expect(DesignTokens.Typography.terminalFontSize == 13)
        #expect(DesignTokens.Typography.terminalLineHeight == 1.25)
        // Satır yüksekliği ayar aralığının içinde olmalı, yoksa varsayılan anında kırpılır.
        #expect(SettingsLimits.lineSpacingRange.contains(DesignTokens.Typography.terminalLineHeight))
        #expect(SettingsLimits.fontSizeRange.contains(DesignTokens.Typography.terminalFontSize))
    }
}
