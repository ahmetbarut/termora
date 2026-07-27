import AppKit
import Foundation
import SwiftTerm
import Testing
@testable import Termora

@MainActor
@Suite struct ThemeTests {
    static let sampleJSON = """
    {
      "id": "sample",
      "name": "Sample",
      "background": "#101015",
      "foreground": "#F0F0F0",
      "cursor": "#FF5500",
      "selection": "#33467C",
      "ansi": ["#000000", "#FF0000", "#00FF00", "#FFFF00",
               "#0000FF", "#FF00FF", "#00FFFF", "#FFFFFF",
               "#808080", "#FF8080", "#80FF80", "#FFFF80",
               "#8080FF", "#FF80FF", "#80FFFF", "#C0C0C0"]
    }
    """

    @Test func decodesFromJSON() throws {
        let theme = try JSONDecoder().decode(Theme.self, from: Data(Self.sampleJSON.utf8))
        #expect(theme.id == "sample")
        #expect(theme.name == "Sample")
        #expect(theme.background == "#101015")
        #expect(theme.selection == "#33467C")
        #expect(theme.ansi.count == 16)
        #expect(theme.ansi[1] == "#FF0000")
    }

    @Test func swiftTermAnsiColorsHasSixteenScaledEntries() throws {
        let theme = try JSONDecoder().decode(Theme.self, from: Data(Self.sampleJSON.utf8))
        let colors = theme.swiftTermAnsiColors()
        #expect(colors.count == 16)
        // 0x00 -> 0, 0xFF -> 65535, 0x80 -> 32896 (128 * 257)
        #expect(colors[0] == SwiftTerm.Color(red: 0, green: 0, blue: 0))
        #expect(colors[1].red == 65535)
        #expect(colors[1].green == 0)
        #expect(colors[1].blue == 0)
        #expect(colors[7] == SwiftTerm.Color(red: 65535, green: 65535, blue: 65535))
        #expect(colors[8].red == 32896)
        #expect(colors[8].green == 32896)
        #expect(colors[8].blue == 32896)
    }

    @Test func nsColorAccessorsParseThemeColors() throws {
        let theme = try JSONDecoder().decode(Theme.self, from: Data(Self.sampleJSON.utf8))
        let cursor = try #require(theme.cursorNSColor.usingColorSpace(.sRGB))
        #expect(abs(cursor.redComponent - 1.0) < 0.001)
        #expect(abs(cursor.greenComponent - CGFloat(0x55) / 255.0) < 0.001)
        #expect(abs(cursor.blueComponent - 0.0) < 0.001)
        let background = try #require(theme.backgroundNSColor.usingColorSpace(.sRGB))
        #expect(abs(background.blueComponent - CGFloat(0x15) / 255.0) < 0.001)
        let selection = try #require(theme.selectionNSColor.usingColorSpace(.sRGB))
        #expect(abs(selection.redComponent - CGFloat(0x33) / 255.0) < 0.001)
        #expect(abs(selection.greenComponent - CGFloat(0x46) / 255.0) < 0.001)
        #expect(abs(selection.blueComponent - CGFloat(0x7C) / 255.0) < 0.001)
    }
}
