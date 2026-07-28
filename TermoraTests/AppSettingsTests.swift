import Foundation
import SwiftTerm
import Testing
@testable import Termora

@MainActor
@Suite struct AppSettingsTests {
    @Test func defaultValuesMatchContract() {
        let settings = AppSettings()
        // brief 3 "Tipografi": SF Mono — 13 pt, satır yüksekliği 1.25.
        #expect(settings.fontName == "SF Mono")
        #expect(settings.fontSize == 13)
        #expect(settings.lineSpacing == 1.25)
        #expect(settings.cursorStyle == .blinkBlock)
        #expect(settings.themeID == "termora-dark")
        #expect(settings.windowOpacity == 1.0)
        #expect(settings.scrollbackLines == 10_000)
        #expect(settings.defaultShellPath == nil)
        #expect(settings.startupDirectory == nil)
        #expect(settings.showStatusBar == true)
        // brief 3 "İlk Açılış Akışı": ilk açılışta onboarding gösterilir.
        #expect(settings.hasCompletedOnboarding == false)
        // briefs/2 "Oturum Geri Yükleme": isteğe bağlı; kullanıcı açıkça istemeli.
        #expect(settings.restoresPreviousSession == false)
        // briefs/2 "Bildirimler" isteğe bağlı + briefs/3 "Ses Kullanımı" varsayılan sessiz:
        // ana anahtar KAPALI gelir, böylece macOS izin sorusu istenmeden çıkmaz.
        #expect(settings.notifiesOnLongCommands == false)
        // Ana anahtar açıldığında iki alt filtre de açıktır: kullanıcı "bildir" dediğinde
        // sessizlik değil, bildirim bekler.
        #expect(settings.notifiesOnCommandSuccess == true)
        #expect(settings.notifiesOnCommandFailure == true)
        #expect(Double(settings.longCommandThresholdSeconds) == 30)
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
        settings.hasCompletedOnboarding = true
        settings.restoresPreviousSession = true
        settings.notifiesOnLongCommands = true
        settings.notifiesOnCommandSuccess = false
        settings.notifiesOnCommandFailure = false
        settings.longCommandThresholdSeconds = 120
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded == settings)
        #expect(decoded.hasCompletedOnboarding == true)
        #expect(decoded.restoresPreviousSession == true)
        #expect(decoded.notifiesOnLongCommands == true)
        #expect(decoded.notifiesOnCommandSuccess == false)
        #expect(decoded.notifiesOnCommandFailure == false)
        #expect(Double(decoded.longCommandThresholdSeconds) == 120)
    }

    /// Eski (onboarding alanı olmayan) bloblar hâlâ çözülmeli; aksi hâlde güncelleyen
    /// kullanıcının tüm ayarları sıfırlanırdı.
    @Test func legacyBlobWithoutOnboardingFlagStillDecodes() throws {
        let legacy = Data(#"{"fontSize":15,"lineSpacing":1.25,"cursorStyle":"blinkBlock","themeID":"nord","windowOpacity":1,"scrollbackLines":10000,"showStatusBar":true}"#.utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacy)
        #expect(decoded.themeID == "nord")
        #expect(decoded.hasCompletedOnboarding == false)
        // Eksik bayrak KAPALI demektir: güncelleyen kullanıcı için oturum kaydı
        // kendiliğinden açılmaz.
        #expect(decoded.restoresPreviousSession == false)
        // Aynı gerekçe bildirimler için de geçerli: güncelleyen kullanıcıya izin sorusu
        // kendiliğinden sorulmaz.
        #expect(decoded.notifiesOnLongCommands == false)
        #expect(decoded.notifiesOnCommandSuccess == true)
        #expect(decoded.notifiesOnCommandFailure == true)
        #expect(Double(decoded.longCommandThresholdSeconds) == 30)
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

    /// Varsayılanlar tek kaynaktan (DesignTokens) gelmeli; kopyalar sürüklenmesin.
    @Test func defaultsComeFromTheDesignTokens() {
        let settings = AppSettings()
        #expect(settings.fontName == DesignTokens.Typography.terminalFontFamily)
        #expect(settings.fontSize == DesignTokens.Typography.terminalFontSize)
        #expect(settings.lineSpacing == DesignTokens.Typography.terminalLineHeight)
        #expect(FontCatalog.defaultFamily == DesignTokens.Typography.terminalFontFamily)
    }

    @Test func cursorStyleRawValuesAreStableForPersistence() {
        #expect(CursorStyleSetting.blinkBlock.rawValue == "blinkBlock")
        #expect(CursorStyleSetting.steadyBar.rawValue == "steadyBar")
    }
}
