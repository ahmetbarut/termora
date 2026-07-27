import Testing
@testable import Termora

/// Brief 3 "Error State": panel ici hata bandi dort soruyu yanitlamalidir —
/// ne basarisiz oldu (baslik), muhtemel sebep + teknik detay (aciklama),
/// kullanici ne yapabilir (eylem butonlari). Metinler Ingilizcedir.
@Suite("Panel cikis bandi")
struct PaneExitBannerTests {

    @Test("shell baslatilamadi: yol, sebep ve uc kurtarma eylemi")
    func launchFailure() {
        let banner = PaneExitBanner.make(exitStatus: ExitStatus(rawStatus: 256),
                                         launchFailure: "/usr/local/bin/fish")

        #expect(banner.title == "Shell failed to start")
        #expect(banner.detail.contains("/usr/local/bin/fish"))
        #expect(banner.detail.contains("missing or not executable"))
        #expect(banner.detail.contains("Settings"))
        #expect(banner.actions == [.openSettings, .useDefaultShell, .retry])
    }

    @Test("temiz cikis: sifir kodu hata gibi sunulmaz")
    func cleanExit() {
        let banner = PaneExitBanner.make(exitStatus: ExitStatus(rawStatus: 0), launchFailure: nil)

        #expect(banner.title == "Shell exited")
        #expect(banner.detail.contains("exit code 0"))
        #expect(banner.actions == [.restart])
    }

    @Test("sifirdan farkli cikis kodu hata olarak sunulur")
    func failingExit() {
        let banner = PaneExitBanner.make(exitStatus: ExitStatus(rawStatus: 256), launchFailure: nil)

        #expect(banner.title == "Shell exited with an error")
        #expect(banner.detail.contains("exit code 1"))
        #expect(banner.actions == [.restart])
    }

    @Test("sinyalle sonlanma ayri bir baslik kullanir")
    func terminatedBySignal() {
        let banner = PaneExitBanner.make(exitStatus: ExitStatus(rawStatus: 9), launchFailure: nil)

        #expect(banner.title == "Shell was terminated")
        #expect(banner.detail.contains("SIGKILL"))
        #expect(banner.actions == [.restart])
    }

    @Test("cozumlenemeyen durumda ham deger teknik detay olarak gosterilir")
    func unknownStatus() {
        let banner = PaneExitBanner.make(exitStatus: ExitStatus(rawStatus: 0x7f), launchFailure: nil)

        #expect(banner.title == "Shell stopped")
        #expect(banner.detail.contains("127"))
        #expect(banner.actions == [.restart])
    }

    @Test("eylem basliklari belirsiz degil, ne yaptigini soyler")
    func actionTitles() {
        #expect(PaneExitBanner.Action.openSettings.title == "Open Settings")
        #expect(PaneExitBanner.Action.useDefaultShell.title == "Use Default Shell")
        #expect(PaneExitBanner.Action.retry.title == "Try Again")
        #expect(PaneExitBanner.Action.restart.title == "Restart Shell")
    }

    @Test("erisilebilirlik etiketi baslik ve aciklamayi birlestirir")
    func accessibilityLabel() {
        let banner = PaneExitBanner.make(exitStatus: ExitStatus(rawStatus: 0), launchFailure: nil)
        #expect(banner.accessibilityLabel == "\(banner.title). \(banner.detail)")
    }
}
