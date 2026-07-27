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
}