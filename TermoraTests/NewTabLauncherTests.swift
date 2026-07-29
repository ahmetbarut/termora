import Foundation
import Testing
@testable import Termora

/// briefs/3 "Yeni Sekme Ekranı".
///
/// Brief'in ilk cümlesi kuralı koyuyor: *Yeni sekme açıldığında shell doğrudan
/// başlatılmalıdır.* Launcher yalnız kullanıcı isterse araya girer — bu yüzden burada
/// ölçülen ilk şey varsayılanın KAPALI olması.
@MainActor
@Suite("Yeni sekme launcher'ı")
struct NewTabLauncherTests {

    @Test func theLauncherIsOffByDefaultSoNewTabsOpenAShellDirectly() {
        #expect(AppSettings().showsNewTabLauncher == false)
    }

    /// briefs/3'ün saydığı beş seçenek, saydığı sırayla.
    @Test func theLauncherOffersExactlyWhatTheBriefLists() {
        #expect(NewTabLauncherOption.allCases.map(\.title) == [
            "Default Shell", "Open Folder", "Open Workspace", "Connect SSH", "Recent Sessions",
        ])
    }

    @Test func everyOptionHasASymbolAndAnExplanation() {
        for option in NewTabLauncherOption.allCases {
            #expect(!option.symbolName.isEmpty)
            #expect(!option.explanation.isEmpty)
        }
    }

    /// Klavyeyle tam kullanım: her seçeneğin bir rakam kısayolu var ve rakamlar
    /// sırayla gidiyor. Fare zorunluluk değil alternatif olmalı (briefs/3 "Klavye
    /// Öncelikli Kullanım").
    @Test func everyOptionIsReachableWithANumberKey() {
        let keys = NewTabLauncherOption.allCases.map(\.shortcutDigit)
        #expect(keys == Array(1...NewTabLauncherOption.allCases.count))
    }

    /// Kayıtsız seçenekler gizlenmez, DEVRE DIŞI görünür (briefs/3 "Sağ Tık Menüleri"
    /// ile aynı kural: kullanılamayan seçenek gizlenmek yerine disabled gösterilir).
    @Test func optionsWithNothingToOfferAreDisabledNotHidden() {
        let empty = NewTabLauncherAvailability(hasWorkspaces: false,
                                               hasSSHHosts: false,
                                               hasRecentFolders: false)
        #expect(empty.isEnabled(.defaultShell))
        #expect(empty.isEnabled(.openFolder))
        #expect(empty.isEnabled(.openWorkspace) == false)
        #expect(empty.isEnabled(.connectSSH) == false)
        #expect(empty.isEnabled(.recentSessions) == false)

        let full = NewTabLauncherAvailability(hasWorkspaces: true,
                                              hasSSHHosts: true,
                                              hasRecentFolders: true)
        #expect(NewTabLauncherOption.allCases.allSatisfy(full.isEnabled))
    }

    /// "Open Folder" her zaman açık: klasör seçici kayıt gerektirmez.
    @Test func openingAFolderNeedsNoStoredRecords() {
        let empty = NewTabLauncherAvailability(hasWorkspaces: false,
                                               hasSSHHosts: false,
                                               hasRecentFolders: false)
        #expect(empty.isEnabled(.openFolder))
    }
}
