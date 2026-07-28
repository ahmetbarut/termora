import Foundation
import Testing
@testable import Termora

/// briefs/3 "Workspace Ekranı": kartta ad, proje yolu, sekme sayısı, son açılma zamanı,
/// git deposu ve başlatma butonu bulunur. Kartın METNİ saf mantıktır; SwiftUI görünümü
/// yalnız bu değerleri çizer, bu yüzden doğruluğu burada denetlenir.
@Suite("Workspace kartı metinleri")
struct WorkspaceCardModelTests {

    private let home = "/Users/dev"

    private func makeWorkspace(name: String = "API",
                               directory: String = "/Users/dev/api",
                               tabs: [WorkspaceTab] = [WorkspaceTab(layout: .pane(WorkspacePane()))],
                               trusts: Bool = false,
                               lastOpenedAt: Date? = nil) -> Workspace {
        Workspace(name: name,
                  directory: directory,
                  tabs: tabs,
                  trustsStartupCommands: trusts,
                  lastOpenedAt: lastOpenedAt)
    }

    private func card(_ workspace: Workspace,
                      repository: GitRepositoryInfo? = nil,
                      now: Date = Date(timeIntervalSince1970: 1_000_000)) -> WorkspaceCardModel {
        WorkspaceCardModel.make(workspace: workspace, repository: repository, now: now, home: home)
    }

    // MARK: - Ad ve yol

    @Test func showsTheWorkspaceNameAndTheHomeRelativePath() {
        let model = card(makeWorkspace())
        #expect(model.name == "API")
        #expect(model.pathText == "~/api")
    }

    @Test func blankNameFallsBackToAReadableLabel() {
        let model = card(makeWorkspace(name: "   "))
        #expect(model.name == WorkspaceCardModel.untitledName)
        #expect(!model.name.isEmpty)
    }

    @Test func missingFolderIsSpelledOutInsteadOfLeavingTheLineEmpty() {
        let model = card(makeWorkspace(directory: ""))
        #expect(model.pathText == WorkspaceCardModel.noFolderText)
    }

    @Test func pathsOutsideHomeStayAbsolute() {
        let model = card(makeWorkspace(directory: "/opt/src"))
        #expect(model.pathText == "/opt/src")
    }

    // MARK: - Sekme / panel sayısı

    @Test func countsTabsAndPanes() {
        let split = WorkspaceLayout.split(axis: .vertical,
                                          ratio: 0.5,
                                          first: .pane(WorkspacePane()),
                                          second: .pane(WorkspacePane()))
        let model = card(makeWorkspace(tabs: [WorkspaceTab(layout: split),
                                              WorkspaceTab(layout: .pane(WorkspacePane()))]))
        #expect(model.tabsText == "2 tabs")
        #expect(model.panesText == "3 panes")
    }

    @Test func singularCountsAreNotWrittenAsPlurals() {
        let model = card(makeWorkspace())
        #expect(model.tabsText == "1 tab")
        #expect(model.panesText == "1 pane")
    }

    @Test func aWorkspaceWithoutTabsSaysSoInsteadOfShowingZero() {
        let model = card(makeWorkspace(tabs: []))
        #expect(model.tabsText == "No tabs")
        #expect(model.panesText == nil)
    }

    // MARK: - Son açılma zamanı

    @Test func neverOpenedWorkspaceIsLabelled() {
        let model = card(makeWorkspace(lastOpenedAt: nil))
        #expect(model.lastOpenedText == WorkspaceRelativeTime.neverText)
    }

    @Test func recentOpensReadAsJustNow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(WorkspaceRelativeTime.text(lastOpenedAt: now.addingTimeInterval(-5), now: now)
                == "Opened just now")
    }

    @Test func relativeTimeWalksUpTheUnits() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func text(_ secondsAgo: Double) -> String {
            WorkspaceRelativeTime.text(lastOpenedAt: now.addingTimeInterval(-secondsAgo), now: now)
        }
        #expect(text(60) == "Opened 1 minute ago")
        #expect(text(120) == "Opened 2 minutes ago")
        #expect(text(3600) == "Opened 1 hour ago")
        #expect(text(7200) == "Opened 2 hours ago")
        #expect(text(86_400) == "Opened 1 day ago")
        #expect(text(3 * 86_400) == "Opened 3 days ago")
        #expect(text(7 * 86_400) == "Opened 1 week ago")
        #expect(text(21 * 86_400) == "Opened 3 weeks ago")
        #expect(text(30 * 86_400) == "Opened 1 month ago")
        #expect(text(120 * 86_400) == "Opened 4 months ago")
        #expect(text(365 * 86_400) == "Opened 1 year ago")
        #expect(text(800 * 86_400) == "Opened 2 years ago")
    }

    /// Sistem saati geri alınırsa "-3 dakika önce" gibi bir metin çıkmamalı.
    @Test func futureTimestampsDoNotProduceNegativeText() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let text = WorkspaceRelativeTime.text(lastOpenedAt: now.addingTimeInterval(500), now: now)
        #expect(text == "Opened just now")
        #expect(!text.contains("-"))
    }

    // MARK: - Git deposu

    @Test func showsRepositoryNameAndBranch() {
        let model = card(makeWorkspace(),
                         repository: GitRepositoryInfo(repositoryName: "termora", branch: "main"))
        #expect(model.repositoryText == "termora · main")
    }

    @Test func repositoryWithoutAReadableBranchStillNamesTheRepository() {
        let model = card(makeWorkspace(),
                         repository: GitRepositoryInfo(repositoryName: "termora", branch: nil))
        #expect(model.repositoryText == "termora")
    }

    @Test func nonRepositoryFolderDrawsNoRepositoryChip() {
        #expect(card(makeWorkspace()).repositoryText == nil)
    }

    // MARK: - Başlangıç komutları ve güven rozeti

    @Test func countsStartupCommands() {
        let tabs = [WorkspaceTab(layout: .split(axis: .horizontal,
                                                ratio: 0.5,
                                                first: .pane(WorkspacePane(startupCommand: "npm run dev")),
                                                second: .pane(WorkspacePane(startupCommand: "npm test"))))]
        #expect(card(makeWorkspace(tabs: tabs)).startupCommandsText == "2 startup commands")
    }

    @Test func oneCommandIsSingular() {
        let tabs = [WorkspaceTab(layout: .pane(WorkspacePane(startupCommand: "npm run dev")))]
        #expect(card(makeWorkspace(tabs: tabs)).startupCommandsText == "1 startup command")
    }

    @Test func noCommandsMeansNoChip() {
        #expect(card(makeWorkspace()).startupCommandsText == nil)
    }

    /// briefs/3 erişilebilirlik: durum yalnız renkle anlatılamaz. Güven rozetinin
    /// hem METNİ hem SİMGESİ vardır.
    @Test func trustedWorkspaceIsMarkedWithTextNotOnlyColour() {
        let tabs = [WorkspaceTab(layout: .pane(WorkspacePane(startupCommand: "npm run dev")))]
        let model = card(makeWorkspace(tabs: tabs, trusts: true))
        #expect(model.trustText == "Trusted")
        #expect(!WorkspaceCardModel.trustedSymbolName.isEmpty)
    }

    /// Çalıştıracak komut yoksa "Trusted" rozeti anlamsızdır.
    @Test func trustBadgeOnlyAppearsWhenThereAreCommandsToTrust() {
        #expect(card(makeWorkspace(trusts: true)).trustText == nil)
    }

    // MARK: - VoiceOver

    @Test func theRowIsSpokenAsOneSentenceCoveringEveryVisibleFact() {
        let tabs = [WorkspaceTab(layout: .pane(WorkspacePane(startupCommand: "npm run dev")))]
        let model = card(makeWorkspace(tabs: tabs, trusts: true,
                                       lastOpenedAt: Date(timeIntervalSince1970: 1_000_000 - 7200)),
                         repository: GitRepositoryInfo(repositoryName: "termora", branch: "main"))

        #expect(model.accessibilityLabel.contains("API"))
        #expect(model.accessibilityLabel.contains("~/api"))
        #expect(model.accessibilityLabel.contains("1 tab"))
        #expect(model.accessibilityLabel.contains("1 startup command"))
        #expect(model.accessibilityLabel.contains("termora"))
        #expect(model.accessibilityLabel.contains("main"))
        #expect(model.accessibilityLabel.contains("Opened 2 hours ago"))
    }

    /// Ekranda çok sayıda "Open" düğmesi olur; her biri hangi workspace'i açtığını söylemeli.
    @Test func iconOnlyButtonsNameTheirOwnWorkspace() {
        let model = card(makeWorkspace(name: "API"))
        #expect(model.launchAccessibilityLabel == "Open workspace API")
        #expect(model.editAccessibilityLabel == "Edit workspace API")
        #expect(model.deleteAccessibilityLabel == "Delete workspace API")
    }

    @Test func iconOnlyButtonLabelsSurviveABlankName() {
        let model = card(makeWorkspace(name: ""))
        #expect(model.launchAccessibilityLabel.contains(WorkspaceCardModel.untitledName))
    }

    // MARK: - Boş durum

    /// briefs/3 "Empty State": tek cümlelik açıklama + birincil eylem, illüstrasyon yok.
    @Test func theEmptyStateHasOneSentenceAndOneNamedAction() {
        #expect(!WorkspacesEmptyState.title.isEmpty)
        #expect(WorkspacesEmptyState.message.filter { $0 == "." }.count == 1)
        #expect(WorkspacesEmptyState.primaryActionTitle == "New Workspace")
    }
}
