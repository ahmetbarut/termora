import Foundation
import SwiftTerm
import Testing
@testable import Termora

@MainActor
@Suite struct AppSettingsTests {
    @Test func defaultValuesMatchContract() {
        let settings = AppSettings()
        #expect(settings.fontName == nil)
        #expect(settings.fontSize == 13)
        #expect(settings.lineSpacing == 1.0)
        #expect(settings.cursorStyle == .blinkBlock)
        #expect(settings.themeID == "termora-dark")
        #expect(settings.windowOpacity == 1.0)
        #expect(settings.scrollbackLines == 10_000)
        #expect(settings.defaultShellPath == nil)
        #expect(settings.startupDirectory == nil)
        #expect(settings.showStatusBar == true)
    }

    @Test func codableRoundTrip() throws {
        var settings = AppSettings()
        settings.fontName = "JetBrainsMono-Regular"
        settings.fontSize = 15
        settings.lineSpacing = 1.2
        settings.cursorStyle = .steadyBar
        settings.themeID = "nord"
        settings.windowOpacity = 0.9
        settings.scrollbackLines = 50_000
        settings.defaultShellPath = "/bin/bash"
        settings.startupDirectory = "/Users/me"
        settings.showStatusBar = false
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded == settings)
    }

    @Test func cursorStyleMapsToSwiftTermForAllSixCases() {
        #expect(CursorStyleSetting.allCases.count == 6)
        #expect(CursorStyleSetting.blinkBlock.swiftTermStyle == .blinkBlock)
        #expect(CursorStyleSetting.steadyBlock.swiftTermStyle == .steadyBlock)
        #expect(CursorStyleSetting.blinkUnderline.swiftTermStyle == .blinkUnderline)
        #expect(CursorStyleSetting.steadyUnderline.swiftTermStyle == .steadyUnderline)
        #expect(CursorStyleSetting.blinkBar.swiftTermStyle == .blinkBar)
        #expect(CursorStyleSetting.steadyBar.swiftTermStyle == .steadyBar)
    }

    @Test func cursorStyleRawValuesAreStableForPersistence() {
        #expect(CursorStyleSetting.blinkBlock.rawValue == "blinkBlock")
        #expect(CursorStyleSetting.steadyBar.rawValue == "steadyBar")
    }
}
