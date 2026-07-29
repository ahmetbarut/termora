import Foundation
import Testing
@testable import Termora

@MainActor
@Suite struct WorkspaceViewModelTests {

    private func makeWorkspace() -> (WorkspaceViewModel, MockSessionManager) {
        let defaults = UserDefaults(suiteName: "WorkspaceViewModelTests.\(UUID().uuidString)")!
        let manager = MockSessionManager()
        let workspace = WorkspaceViewModel(
            sessionManager: manager,
            settings: SettingsStore(defaults: defaults),
            profiles: ProfileStore(defaults: defaults)
        )
        return (workspace, manager)
    }

    @Test func newTabCreatesSessionAndActivatesTab() {
        let (workspace, manager) = makeWorkspace()

        workspace.newTab()

        #expect(workspace.tabs.count == 1)
        let tab = workspace.tabs[0]
        #expect(workspace.activeTabID == tab.id)
        #expect(workspace.activeTab === tab)
        #expect(tab.root.leaves.count == 1)
        #expect(tab.root.leaves[0].paneID == tab.activePaneID)
        #expect(manager.session(id: tab.root.leaves[0].sessionID) != nil)
        #expect(manager.createdProfiles == [TerminalProfile?.none])
    }

    @Test func newTabWithProfilePassesProfileAndSeedsAutomaticTitle() {
        let (workspace, manager) = makeWorkspace()
        let profile = TerminalProfile(name: "Sunucu")

        workspace.newTab(profile: profile)

        #expect(manager.createdProfiles.count == 1)
        #expect(manager.createdProfiles[0]?.id == profile.id)
        #expect(workspace.tabs[0].automaticTitle == "Sunucu")
        #expect(workspace.tabs[0].displayTitle == "Sunucu")
    }

    @Test func newTabAppendsAndMovesActivationToTheNewTab() {
        let (workspace, _) = makeWorkspace()

        workspace.newTab()
        let first = workspace.tabs[0].id
        workspace.newTab()

        #expect(workspace.tabs.count == 2)
        #expect(workspace.tabs[0].id == first)
        #expect(workspace.activeTabID == workspace.tabs[1].id)
    }

    // MARK: - Kapatma

    @Test func requestCloseTabClosesIdleTabAndTerminatesItsSessions() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        workspace.newTab()
        let tab = workspace.tabs[1]
        let sessionID = tab.root.leaves[0].sessionID

        workspace.requestCloseTab(id: tab.id)

        #expect(workspace.pendingClose == nil)
        #expect(workspace.tabs.count == 1)
        #expect(workspace.tabs.contains { $0.id == tab.id } == false)
        #expect(manager.terminatedSessionIDs == [sessionID])
    }

    @Test func requestCloseTabWithRunningProcessAsksForConfirmation() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        let tab = workspace.tabs[0]
        manager.busySessionIDs.insert(tab.root.leaves[0].sessionID)

        workspace.requestCloseTab(id: tab.id)

        #expect(workspace.pendingClose?.target == .tab(tab.id))
        #expect(workspace.tabs.count == 1)
        #expect(manager.terminatedSessionIDs.isEmpty)
    }

    @Test func confirmPendingCloseClosesTheTab() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        workspace.newTab()
        let tab = workspace.tabs[1]
        let sessionID = tab.root.leaves[0].sessionID
        manager.busySessionIDs.insert(sessionID)
        workspace.requestCloseTab(id: tab.id)

        workspace.confirmPendingClose()

        #expect(workspace.pendingClose == nil)
        #expect(workspace.tabs.count == 1)
        #expect(manager.terminatedSessionIDs == [sessionID])
    }

    @Test func cancelPendingCloseKeepsTheTabAlive() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        let tab = workspace.tabs[0]
        manager.busySessionIDs.insert(tab.root.leaves[0].sessionID)
        workspace.requestCloseTab(id: tab.id)

        workspace.cancelPendingClose()

        #expect(workspace.pendingClose == nil)
        #expect(workspace.tabs.count == 1)
        #expect(manager.terminatedSessionIDs.isEmpty)
    }

    @Test func closingLastTabOpensAReplacementTab() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        let firstTabID = workspace.tabs[0].id
        let firstSessionID = workspace.tabs[0].root.leaves[0].sessionID

        workspace.requestCloseTab(id: firstTabID)

        // `first` (indeks değil): kırmızı fazda sekme listesi boş kalırsa `tabs[0]` dizi
        // tuzağına düşüp TÜM test sürecini öldürür ve paralel testlerin sinyalini yok eder.
        #expect(workspace.tabs.count == 1)
        #expect(workspace.tabs.first?.id != firstTabID)
        #expect(workspace.activeTabID == workspace.tabs.first?.id)
        #expect(manager.terminatedSessionIDs == [firstSessionID])
        #expect(manager.sessions.count == 1)
    }

    @Test func confirmingCloseOfTheLastBusyTabAlsoOpensAReplacementTab() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        let tab = workspace.tabs[0]
        manager.busySessionIDs.insert(tab.root.leaves[0].sessionID)
        workspace.requestCloseTab(id: tab.id)
        #expect(workspace.tabs.count == 1)

        workspace.confirmPendingClose()

        #expect(workspace.tabs.count == 1)
        #expect(workspace.tabs.first?.id != tab.id)
        #expect(workspace.pendingClose == nil)
    }

    @Test func closingActiveTabActivatesTheNeighbourAtTheSameIndex() {
        let (workspace, _) = makeWorkspace()
        workspace.newTab()
        workspace.newTab()
        workspace.newTab()
        let middle = workspace.tabs[1]
        let last = workspace.tabs[2].id
        workspace.selectTab(at: 1)

        workspace.requestCloseTab(id: middle.id)

        #expect(workspace.tabs.count == 2)
        #expect(workspace.activeTabID == last)
    }

    @Test func closingInactiveTabKeepsCurrentActivation() {
        let (workspace, _) = makeWorkspace()
        workspace.newTab()
        workspace.newTab()
        let active = workspace.activeTabID

        workspace.requestCloseTab(id: workspace.tabs[0].id)

        #expect(workspace.tabs.count == 1)
        #expect(workspace.activeTabID == active)
    }

    @Test func confirmingWindowCloseTerminatesEverySession() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        workspace.newTab()
        let sessionIDs = workspace.tabs.map { $0.root.leaves[0].sessionID }
        workspace.pendingClose = WorkspaceViewModel.PendingClose(id: UUID(), target: .window)

        workspace.confirmPendingClose()

        #expect(workspace.tabs.isEmpty)
        #expect(workspace.activeTabID == nil)
        #expect(Set(manager.terminatedSessionIDs) == Set(sessionIDs))
    }

    @Test func hasAnyRunningProcessReflectsSessionState() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()

        #expect(workspace.hasAnyRunningProcess() == false)

        manager.busySessionIDs.insert(workspace.tabs[0].root.leaves[0].sessionID)
        #expect(workspace.hasAnyRunningProcess())
    }

    // MARK: - Pencere / uygulama kapatma

    /// Dizin indeksi yerine: kırmızı fazda `[i]` tüm test sürecini öldürür.
    private func sessionID(ofTabAt index: Int, in workspace: WorkspaceViewModel) throws -> UUID {
        let tab = try #require(workspace.tabs.indices.contains(index) ? workspace.tabs[index] : nil)
        return try #require(tab.root.leaves.first).sessionID
    }

    @Test func hasAnyRunningProcessScansEveryTab() throws {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        workspace.newTab()
        workspace.newTab()
        #expect(workspace.hasAnyRunningProcess() == false)

        let busySessionID = try sessionID(ofTabAt: 1, in: workspace)
        manager.busySessionIDs.insert(busySessionID)
        #expect(workspace.hasAnyRunningProcess())

        manager.terminateSession(id: busySessionID)
        #expect(workspace.hasAnyRunningProcess() == false)
    }

    @Test func requestCloseWindowAllowsClosingWhenNothingIsRunning() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        var approvedCount = 0

        let canCloseNow = workspace.requestCloseWindow { approvedCount += 1 }

        #expect(canCloseNow)
        #expect(workspace.pendingClose == nil)
        // Onay istenmediği için callback de çalışmaz; oturumları çağıran kapatır.
        #expect(approvedCount == 0)
        #expect(manager.terminatedSessionIDs.isEmpty)
    }

    @Test func requestCloseWindowAsksForConfirmationWhenSomethingIsRunning() throws {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        workspace.newTab()
        manager.busySessionIDs.insert(try sessionID(ofTabAt: 1, in: workspace))
        var approvedCount = 0

        let canCloseNow = workspace.requestCloseWindow { approvedCount += 1 }

        #expect(canCloseNow == false)
        #expect(workspace.pendingClose?.target == .window)
        #expect(approvedCount == 0)
        #expect(manager.terminatedSessionIDs.isEmpty)
        #expect(workspace.tabs.count == 2)
    }

    @Test func confirmingWindowCloseTerminatesSessionsThenRunsTheApproval() throws {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        workspace.newTab()
        let sessionIDs = try (0..<2).map { try sessionID(ofTabAt: $0, in: workspace) }
        manager.busySessionIDs.insert(try #require(sessionIDs.first))
        var terminatedCountAtApproval = -1
        _ = workspace.requestCloseWindow { terminatedCountAtApproval = manager.terminatedSessionIDs.count }

        workspace.confirmPendingClose()

        // Onay callback'i, oturumlar kapatıldıktan SONRA çağrılmalı: pencere kapanırken
        // arkada canlı shell kalmamalı.
        #expect(terminatedCountAtApproval == 2)
        #expect(Set(manager.terminatedSessionIDs) == Set(sessionIDs))
        #expect(workspace.tabs.isEmpty)
        #expect(workspace.activeTabID == nil)
        #expect(workspace.pendingClose == nil)
    }

    @Test func cancellingWindowCloseKeepsSessionsAndDropsTheApproval() throws {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        manager.busySessionIDs.insert(try sessionID(ofTabAt: 0, in: workspace))
        var approvedCount = 0
        _ = workspace.requestCloseWindow { approvedCount += 1 }

        workspace.cancelPendingClose()

        #expect(workspace.pendingClose == nil)
        #expect(workspace.tabs.count == 1)
        #expect(manager.terminatedSessionIDs.isEmpty)
        #expect(approvedCount == 0)

        // Vazgeçilen onay unutulur: yeni bir istek olmadan callback bir daha çalışamaz.
        workspace.confirmPendingClose()
        #expect(approvedCount == 0)
    }

    @Test func pendingCloseMessageDescribesTheTarget() throws {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        let tab = try #require(workspace.tabs.first)
        manager.busySessionIDs.insert(try sessionID(ofTabAt: 0, in: workspace))

        #expect(workspace.pendingCloseTitle.isEmpty)
        #expect(workspace.pendingCloseMessage.isEmpty)
        #expect(workspace.pendingCloseConfirmLabel.isEmpty)

        workspace.requestCloseTab(id: tab.id)
        #expect(workspace.pendingCloseTitle == "Do you want to close this tab?")
        // İşlem adı bilinmiyor (test yöneticisi PTY tutmaz): uydurulmaz, genel ifade kullanılır.
        #expect(workspace.pendingCloseMessage == "A process is still running in this tab.")
        #expect(workspace.pendingCloseConfirmLabel == "Close Tab")

        workspace.cancelPendingClose()
        _ = workspace.requestCloseWindow {}
        #expect(workspace.pendingCloseTitle == "Do you want to close this window?")
        #expect(workspace.pendingCloseMessage == "Processes are still running in this window.")
        #expect(workspace.pendingCloseConfirmLabel == "Close Window")
    }

    @Test func pendingClosePaneUsesPaneWording() throws {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        let tab = try #require(workspace.tabs.first)
        workspace.splitActivePane(axis: .vertical)
        manager.busySessionIDs.insert(try #require(tab.root.sessionID(ofPane: tab.activePaneID)))

        workspace.requestCloseActivePane()

        #expect(workspace.pendingCloseTitle == "Do you want to close this pane?")
        #expect(workspace.pendingCloseMessage == "A process is still running in this pane.")
        #expect(workspace.pendingCloseConfirmLabel == "Close Pane")
    }

    // MARK: - Sekmeleri sürükleyerek sıralama

    @Test func moveTabReordersUsingOnMoveSemantics() throws {
        let (workspace, _) = makeWorkspace()
        workspace.newTab()
        workspace.newTab()
        workspace.newTab()
        let ids = workspace.tabs.map(\.id)

        // İlk sekme sona taşınır (SwiftUI .onMove: hedef, taşıma ÖNCESİ dizinde bir aralık).
        workspace.moveTab(from: IndexSet(integer: 0), to: 3)

        #expect(workspace.tabs.map(\.id) == [ids[1], ids[2], ids[0]])
        // Sıralama aktif sekmeyi değiştirmez.
        #expect(workspace.activeTabID == ids[2])
    }

    @Test func moveTabIgnoresEmptyOrOutOfRangeRequests() throws {
        let (workspace, _) = makeWorkspace()
        workspace.newTab()
        workspace.newTab()
        let ids = workspace.tabs.map(\.id)

        workspace.moveTab(from: IndexSet(), to: 1)
        workspace.moveTab(from: IndexSet(integer: 0), to: 9)
        workspace.moveTab(from: IndexSet(integer: 7), to: 0)

        #expect(workspace.tabs.map(\.id) == ids)
    }

    @Test func droppingATabOnAnotherTakesOverItsSlot() throws {
        let (workspace, _) = makeWorkspace()
        workspace.newTab()
        workspace.newTab()
        workspace.newTab()
        let ids = workspace.tabs.map(\.id)

        // Sona sürüklenen sekme hedefin yerini alır.
        workspace.moveTab(id: ids[0], toSlotOf: ids[2])
        #expect(workspace.tabs.map(\.id) == [ids[1], ids[2], ids[0]])

        // Geriye doğru sürüklemede de hedefin dizini kullanılır.
        workspace.moveTab(id: ids[0], toSlotOf: ids[1])
        #expect(workspace.tabs.map(\.id) == [ids[0], ids[1], ids[2]])
    }

    @Test func droppingATabOnItselfOrOnAnUnknownTabChangesNothing() throws {
        let (workspace, _) = makeWorkspace()
        workspace.newTab()
        workspace.newTab()
        let ids = workspace.tabs.map(\.id)

        workspace.moveTab(id: ids[0], toSlotOf: ids[0])
        workspace.moveTab(id: UUID(), toSlotOf: ids[1])
        workspace.moveTab(id: ids[1], toSlotOf: UUID())

        #expect(workspace.tabs.map(\.id) == ids)
    }

    // MARK: - Seçim ve yeniden adlandırma

    @Test func selectTabUsesZeroBasedIndexAndIgnoresOutOfBounds() {
        let (workspace, _) = makeWorkspace()
        workspace.newTab()
        workspace.newTab()

        workspace.selectTab(at: 0)
        #expect(workspace.activeTabID == workspace.tabs[0].id)

        workspace.selectTab(at: 5)
        #expect(workspace.activeTabID == workspace.tabs[0].id)

        workspace.selectTab(at: -1)
        #expect(workspace.activeTabID == workspace.tabs[0].id)
    }

    @Test func nextAndPreviousTabWrapAround() {
        let (workspace, _) = makeWorkspace()
        workspace.newTab()
        workspace.newTab()
        workspace.newTab()

        workspace.selectTab(at: 2)
        workspace.nextTab()
        #expect(workspace.activeTabID == workspace.tabs[0].id)

        workspace.previousTab()
        #expect(workspace.activeTabID == workspace.tabs[2].id)

        workspace.previousTab()
        #expect(workspace.activeTabID == workspace.tabs[1].id)
    }

    @Test func nextTabOnEmptyWorkspaceIsNoOp() {
        let (workspace, _) = makeWorkspace()
        workspace.nextTab()
        workspace.previousTab()
        #expect(workspace.activeTabID == nil)
    }

    @Test func renameTabSetsCustomTitleAndBlankNameRestoresAutomaticTitle() {
        let (workspace, _) = makeWorkspace()
        workspace.newTab()
        let tab = workspace.tabs[0]
        tab.automaticTitle = "zsh"

        workspace.renameTab(id: tab.id, to: "  Build  ")
        #expect(tab.customTitle == "Build")
        #expect(tab.displayTitle == "Build")

        workspace.renameTab(id: tab.id, to: "   ")
        #expect(tab.customTitle == nil)
        #expect(tab.displayTitle == "zsh")

        workspace.renameTab(id: tab.id, to: "Build")
        workspace.renameTab(id: tab.id, to: nil)
        #expect(tab.customTitle == nil)
    }

    @Test func syncAutomaticTitlesCopiesActivePaneSessionTitle() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        let tab = workspace.tabs[0]
        let sessionID = tab.root.leaves[0].sessionID
        manager.session(id: sessionID)?.title = "~/code — zsh"

        #expect(workspace.sessionTitleDigest.contains("~/code — zsh"))

        workspace.syncAutomaticTitles()
        #expect(tab.automaticTitle == "~/code — zsh")
        #expect(tab.displayTitle == "~/code — zsh")
    }

    @Test func syncAutomaticTitlesKeepsLastKnownTitleWhenSessionIsGone() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        let tab = workspace.tabs[0]
        let sessionID = tab.root.leaves[0].sessionID
        manager.session(id: sessionID)?.title = "vim"
        workspace.syncAutomaticTitles()

        manager.terminateSession(id: sessionID)
        workspace.syncAutomaticTitles()

        #expect(tab.automaticTitle == "vim")
    }

    @Test func automaticTitleFallsBackToWorkingDirectoryBasename() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        let tab = workspace.tabs[0]
        let sessionID = tab.root.leaves[0].sessionID
        manager.session(id: sessionID)?.workingDirectory = "/Users/ahmetbarut/code"

        workspace.syncAutomaticTitles()

        #expect(tab.automaticTitle == "code")
        #expect(tab.displayTitle == "code")
    }

    @Test func automaticTitleFallsBackToShellNameWhenNothingIsKnown() {
        let (workspace, manager) = makeWorkspace()
        manager.defaultShellPath = "/bin/zsh"
        workspace.newTab()
        let tab = workspace.tabs[0]

        workspace.syncAutomaticTitles()

        #expect(tab.automaticTitle == "zsh")
        #expect(tab.displayTitle == "zsh")
    }

    // MARK: - briefs/2 "Menü Çubuğu" ▸ Shell menüsü

    @Test func restartingTheActivePaneRestartsItsSession() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        let sessionID = workspace.tabs[0].root.leaves[0].sessionID

        workspace.restartActivePaneSession()

        #expect(manager.restartedSessionIDs == [sessionID])
    }

    /// "Restart with Default Shell", kullanıcının bozuk bir profil shell'inden çıkış yoludur
    /// (briefs/3 "Error State" örneği: `/usr/local/bin/fish` yok). Profil sıfırlanmazsa bu
    /// öğe hiçbir işe yaramaz.
    @Test func restartingWithTheDefaultShellDropsTheProfileShell() {
        let (workspace, manager) = makeWorkspace()
        manager.defaultShellPath = "/bin/zsh"
        workspace.newTab(profile: TerminalProfile(name: "Kırık", shellPath: "/usr/local/bin/fish"))
        let sessionID = workspace.tabs[0].root.leaves[0].sessionID

        workspace.restartActivePaneSession(forceDefaultShell: true)

        #expect(manager.session(id: sessionID)?.shellPath == "/bin/zsh")
        #expect(manager.session(id: sessionID)?.profileID == nil)
    }

    @Test func restartingWithNoOpenTabDoesNothing() {
        let (workspace, manager) = makeWorkspace()

        workspace.restartActivePaneSession()

        #expect(manager.restartedSessionIDs.isEmpty)
    }

    /// Clear Screen terminale form feed (`\u{0C}`) yazar — shell'in kendi `Ctrl+L`'iyle
    /// aynı yol. Ekranı Termora'nın kendi tarafında "temizlemek" scrollback'i ve shell'in
    /// durumunu Termora'nın bilmediği biçimde ayırırdı.
    @Test func clearingTheActivePaneSendsFormFeedToItsSession() {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        let sessionID = workspace.tabs[0].root.leaves[0].sessionID

        workspace.clearActivePane()

        #expect(manager.sentInput.count == 1)
        #expect(manager.sentInput.first?.sessionID == sessionID)
        #expect(manager.sentInput.first?.text == "\u{0C}")
    }

    @Test func clearingWithNoOpenTabSendsNothing() {
        let (workspace, manager) = makeWorkspace()

        workspace.clearActivePane()

        #expect(manager.sentInput.isEmpty)
    }
}