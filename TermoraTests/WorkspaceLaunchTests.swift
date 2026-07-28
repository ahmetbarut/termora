import Foundation
import Testing
@testable import Termora

/// Workspace yakalama ve açma akışı (briefs/2 "Workspace Sistemi").
/// En kritik kural burada doğrulanır: **onay verilmeden başlangıç komutu ÇALIŞMAZ.**
@MainActor
@Suite struct WorkspaceLaunchTests {

    private struct Subject {
        let viewModel: WorkspaceViewModel
        let sessions: MockSessionManager
        let store: WorkspaceStore
        let profiles: ProfileStore
        let defaults: UserDefaults
    }

    private func makeSubject(now: @escaping () -> Date = Date.init) -> Subject {
        let defaults = UserDefaults(suiteName: "WorkspaceLaunchTests.\(UUID().uuidString)")!
        let sessions = MockSessionManager()
        let store = WorkspaceStore(defaults: defaults)
        let profiles = ProfileStore(defaults: defaults)
        let viewModel = WorkspaceViewModel(
            sessionManager: sessions,
            settings: SettingsStore(defaults: defaults),
            profiles: profiles,
            workspaces: store,
            now: now
        )
        return Subject(viewModel: viewModel,
                       sessions: sessions,
                       store: store,
                       profiles: profiles,
                       defaults: defaults)
    }

    private func singlePaneWorkspace(command: String? = nil,
                                     trusts: Bool = false,
                                     directory: String = "/Users/dev/api") -> Workspace {
        Workspace(name: "API",
                  directory: directory,
                  tabs: [WorkspaceTab(title: "Server",
                                      layout: .pane(WorkspacePane(startupCommand: command)))],
                  trustsStartupCommands: trusts)
    }

    // MARK: - Yakalama

    @Test func captureRecordsTabTitlesPaneTreeAndSessionDirectories() throws {
        let s = makeSubject()
        s.viewModel.newTab()
        let tab = try #require(s.viewModel.tabs.first)
        s.viewModel.renameTab(id: tab.id, to: "Server")
        let firstSession = try #require(tab.root.leaves.first?.sessionID)
        s.sessions.session(id: firstSession)?.workingDirectory = "/Users/dev/api"
        s.viewModel.splitActivePane(axis: .vertical)
        let secondSession = try #require(tab.root.leaves.last?.sessionID)
        s.sessions.session(id: secondSession)?.workingDirectory = "/Users/dev/api/logs"

        let captured = s.viewModel.captureWorkspace(name: "API", directory: "/Users/dev")

        #expect(captured.name == "API")
        #expect(captured.directory == "/Users/dev")
        #expect(captured.tabs.count == 1)
        #expect(captured.paneCount == 2)
        #expect(captured.trustsStartupCommands == false)

        let capturedTab = try #require(captured.tabs.first)
        #expect(capturedTab.title == "Server")
        guard case let .split(axis, ratio, first, second) = capturedTab.layout else {
            Issue.record("expected a split layout, got \(capturedTab.layout)")
            return
        }
        #expect(axis == .vertical)
        #expect(Double(ratio) == 0.5)
        #expect(first.panes.first?.startupDirectory == "/Users/dev/api")
        #expect(second.panes.first?.startupDirectory == "/Users/dev/api/logs")
        // Açık düzenden yakalanan hiçbir panel komut taşımaz: komutlar elle eklenir.
        #expect(captured.tabs.flatMap(\.layout.panes).allSatisfy { $0.startupCommand == nil })
    }

    @Test func captureKeepsAutomaticTitlesOutOfTheRecord() throws {
        let s = makeSubject()
        s.viewModel.newTab()
        let tab = try #require(s.viewModel.tabs.first)
        tab.automaticTitle = "zsh"

        let captured = s.viewModel.captureWorkspace(name: "API", directory: "/Users/dev")

        // İç içe optional'da `== nil` yanıltıcıdır (.some(nil) != nil): önce dış kabuk açılır.
        let capturedTab = try #require(captured.tabs.first)
        #expect(capturedTab.title == nil)
    }

    @Test func captureDoesNotPersistTheWorkspace() {
        let s = makeSubject()
        s.viewModel.newTab()

        _ = s.viewModel.captureWorkspace(name: "API", directory: "/Users/dev")

        #expect(s.store.workspaces.isEmpty)
    }

    // MARK: - Onaysız komut ÇALIŞMAZ

    @Test func startupCommandsNeverRunWithoutApproval() throws {
        let s = makeSubject()
        s.viewModel.newTab()
        let openTabIDs = s.viewModel.tabs.map(\.id)
        let sessionsBefore = s.sessions.createdSessions.count
        let workspace = singlePaneWorkspace(command: "npm run dev")
        s.store.upsert(workspace)

        s.viewModel.openWorkspace(workspace)

        let pending = try #require(s.viewModel.pendingWorkspaceLaunch)
        #expect(pending.workspace.id == workspace.id)
        #expect(pending.commands == ["npm run dev"])
        // Hiçbir shell başlatılmaz, hiçbir komut gönderilmez, açık düzen bozulmaz.
        #expect(s.sessions.createdSessions.count == sessionsBefore)
        #expect(s.sessions.createdStartupCommands.compactMap { $0 }.isEmpty)
        #expect(s.sessions.terminatedSessionIDs.isEmpty)
        #expect(s.viewModel.tabs.map(\.id) == openTabIDs)
        let stored = try #require(s.store.workspaces.first)
        #expect(stored.trustsStartupCommands == false)
        #expect(stored.lastOpenedAt == nil)
    }

    @Test func cancellingTheLaunchLeavesEverythingUnchanged() throws {
        let s = makeSubject()
        s.viewModel.newTab()
        let openTabIDs = s.viewModel.tabs.map(\.id)
        let sessionsBefore = s.sessions.createdSessions.count
        let workspace = singlePaneWorkspace(command: "npm run dev")
        s.store.upsert(workspace)
        s.viewModel.openWorkspace(workspace)

        s.viewModel.cancelWorkspaceLaunch()

        #expect(s.viewModel.pendingWorkspaceLaunch == nil)
        #expect(s.sessions.createdSessions.count == sessionsBefore)
        #expect(s.sessions.createdStartupCommands.compactMap { $0 }.isEmpty)
        #expect(s.viewModel.tabs.map(\.id) == openTabIDs)
        let stored = try #require(s.store.workspaces.first)
        #expect(stored.trustsStartupCommands == false)
        #expect(stored.lastOpenedAt == nil)
    }

    @Test func confirmingTheLaunchRunsTheCommandInItsSavedDirectory() throws {
        let s = makeSubject()
        let workspace = singlePaneWorkspace(command: "npm run dev")
        s.store.upsert(workspace)
        s.viewModel.openWorkspace(workspace)

        s.viewModel.confirmWorkspaceLaunch(trustFromNowOn: false)

        #expect(s.viewModel.pendingWorkspaceLaunch == nil)
        #expect(s.sessions.createdStartupCommands.compactMap { $0 } == ["npm run dev"])
        #expect(s.sessions.createdWorkingDirectories == ["/Users/dev/api"])
        // "Bir kez izin ver": kayıt güvenilir işaretlenmez, bir dahakine yine sorulur.
        #expect(s.store.workspaces.first?.trustsStartupCommands == false)
    }

    @Test func trustingTheWorkspacePersistsTheDecision() throws {
        let s = makeSubject()
        let workspace = singlePaneWorkspace(command: "npm run dev")
        s.store.upsert(workspace)
        s.viewModel.openWorkspace(workspace)

        s.viewModel.confirmWorkspaceLaunch(trustFromNowOn: true)

        #expect(s.store.workspaces.first?.trustsStartupCommands == true)
        // Diskten okunan kopya da güvenilir olmalı.
        let reloaded = WorkspaceStore(defaults: s.defaults)
        #expect(reloaded.workspaces.first?.trustsStartupCommands == true)
    }

    @Test func trustedWorkspaceOpensWithoutAsking() throws {
        let s = makeSubject()
        let workspace = singlePaneWorkspace(command: "npm run dev", trusts: true)
        s.store.upsert(workspace)

        s.viewModel.openWorkspace(workspace)

        #expect(s.viewModel.pendingWorkspaceLaunch == nil)
        #expect(s.sessions.createdStartupCommands.compactMap { $0 } == ["npm run dev"])
        #expect(s.viewModel.tabs.count == 1)
    }

    @Test func workspaceWithoutCommandsOpensWithoutAsking() throws {
        let s = makeSubject()
        let workspace = singlePaneWorkspace()
        s.store.upsert(workspace)

        s.viewModel.openWorkspace(workspace)

        #expect(s.viewModel.pendingWorkspaceLaunch == nil)
        #expect(s.sessions.createdStartupCommands.compactMap { $0 }.isEmpty)
        #expect(s.viewModel.tabs.count == 1)
    }

    // MARK: - Açma

    @Test func openingReplacesTheOpenTabsAndTerminatesTheirSessions() throws {
        let s = makeSubject()
        s.viewModel.newTab()
        let oldSessionID = try #require(s.viewModel.tabs.first?.root.leaves.first?.sessionID)
        let workspace = singlePaneWorkspace()

        s.viewModel.openWorkspace(workspace)

        #expect(s.sessions.terminatedSessionIDs == [oldSessionID])
        #expect(s.viewModel.tabs.count == 1)
        let tab = try #require(s.viewModel.tabs.first)
        #expect(tab.customTitle == "Server")
        #expect(tab.displayTitle == "Server")
        #expect(s.viewModel.activeTabID == tab.id)
        #expect(tab.root.leaves.first?.paneID == tab.activePaneID)
        #expect(s.sessions.createdWorkingDirectories.last == "/Users/dev/api")
    }

    @Test func paneWithoutADirectoryFallsBackToTheWorkspaceDirectory() throws {
        let s = makeSubject()
        let workspace = Workspace(
            name: "API",
            directory: "/Users/dev/api",
            tabs: [WorkspaceTab(layout: .split(
                axis: .horizontal,
                ratio: 0.3,
                first: .pane(WorkspacePane(startupDirectory: "/Users/dev/api/web")),
                second: .pane(WorkspacePane())))])

        s.viewModel.openWorkspace(workspace)

        #expect(s.sessions.createdWorkingDirectories == ["/Users/dev/api/web", "/Users/dev/api"])
        let tab = try #require(s.viewModel.tabs.first)
        guard case let .split(_, axis, ratio, _, _) = tab.root else {
            Issue.record("expected a split root, got \(tab.root)")
            return
        }
        #expect(axis == .horizontal)
        #expect(Double(ratio) == 0.3)
        #expect(tab.root.leaves.count == 2)
    }

    @Test func openingStampsLastOpenedWithTheInjectedDate() throws {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let s = makeSubject(now: { stamp })
        let workspace = singlePaneWorkspace()
        s.store.upsert(workspace)

        s.viewModel.openWorkspace(workspace)

        #expect(s.store.workspaces.first?.lastOpenedAt == stamp)
    }

    @Test func openingAWorkspaceWithoutTabsStillLeavesOneTerminal() {
        let s = makeSubject()

        s.viewModel.openWorkspace(Workspace(name: "Empty", directory: "/Users/dev"))

        #expect(s.viewModel.tabs.count == 1)
        #expect(s.viewModel.activeTabID == s.viewModel.tabs.first?.id)
    }

    @Test func captureThenOpenPreservesTheLayout() throws {
        let s = makeSubject()
        s.viewModel.newTab()
        let firstTab = try #require(s.viewModel.tabs.first)
        s.viewModel.renameTab(id: firstTab.id, to: "Server")
        let leftSession = try #require(firstTab.root.leaves.first?.sessionID)
        s.sessions.session(id: leftSession)?.workingDirectory = "/Users/dev/api"
        s.viewModel.splitActivePane(axis: .horizontal)
        let rightSession = try #require(firstTab.root.leaves.last?.sessionID)
        s.sessions.session(id: rightSession)?.workingDirectory = "/Users/dev/api/logs"
        s.viewModel.newTab()
        let secondSession = try #require(s.viewModel.tabs.last?.root.leaves.first?.sessionID)
        s.sessions.session(id: secondSession)?.workingDirectory = "/Users/dev/web"

        let captured = s.viewModel.captureWorkspace(name: "API", directory: "/Users/dev")
        s.viewModel.openWorkspace(captured)
        let recaptured = s.viewModel.captureWorkspace(name: "API", directory: "/Users/dev")

        #expect(recaptured.tabs.map(\.layout) == captured.tabs.map(\.layout))
        #expect(recaptured.tabs.map(\.title) == captured.tabs.map(\.title))
        #expect(recaptured.paneCount == 3)
    }

    // MARK: - Profil ve ortam

    @Test func workspaceEnvironmentReachesTheLaunchProfile() throws {
        let s = makeSubject()
        var workspace = singlePaneWorkspace()
        workspace.environment = ["API_URL": "http://localhost:3000"]

        s.viewModel.openWorkspace(workspace)

        let profile = try #require(s.sessions.createdProfiles.last ?? nil)
        #expect(profile.environment["API_URL"] == "http://localhost:3000")
        #expect(profile.startupCommand == nil)
    }

    @Test func workspaceProfileIsUsedAndItsEnvironmentIsOverridden() throws {
        let s = makeSubject()
        let base = TerminalProfile(name: "Node",
                                   shellPath: "/bin/bash",
                                   environment: ["NODE_ENV": "development", "API_URL": "http://staging"])
        s.profiles.profiles = [base]
        var workspace = singlePaneWorkspace()
        workspace.profileID = base.id
        workspace.environment = ["API_URL": "http://localhost:3000"]

        s.viewModel.openWorkspace(workspace)

        let profile = try #require(s.sessions.createdProfiles.last ?? nil)
        #expect(profile.id == base.id)
        #expect(profile.shellPath == "/bin/bash")
        #expect(profile.environment["NODE_ENV"] == "development")
        #expect(profile.environment["API_URL"] == "http://localhost:3000")
    }

    @Test func workspaceWithoutProfileOrEnvironmentLaunchesTheDefaultShell() {
        let s = makeSubject()

        s.viewModel.openWorkspace(singlePaneWorkspace())

        #expect(s.sessions.createdProfiles.compactMap { $0 }.isEmpty)
    }

    // MARK: - Çalışan işlemler

    @Test func openingAsksBeforeReplacingTabsWithARunningProcess() throws {
        let s = makeSubject()
        s.viewModel.newTab()
        let sessionID = try #require(s.viewModel.tabs.first?.root.leaves.first?.sessionID)
        s.sessions.busySessionIDs.insert(sessionID)

        s.viewModel.openWorkspace(singlePaneWorkspace())

        #expect(s.viewModel.pendingClose?.target == .workspaceSwitch(name: "API"))
        #expect(s.viewModel.pendingCloseTitle == "Do you want to open the workspace “API”?")
        #expect(s.viewModel.pendingCloseConfirmLabel == "Open Workspace")
        #expect(s.viewModel.pendingCloseMessage.contains("Opening “API”"))
        #expect(s.sessions.terminatedSessionIDs.isEmpty)
        let untouchedTab = try #require(s.viewModel.tabs.first)
        #expect(untouchedTab.customTitle == nil)

        s.viewModel.confirmPendingClose()

        #expect(s.viewModel.pendingClose == nil)
        #expect(s.sessions.terminatedSessionIDs == [sessionID])
        #expect(s.viewModel.tabs.count == 1)
        #expect(s.viewModel.tabs.first?.customTitle == "Server")
    }

    @Test func cancellingTheReplacementKeepsTheBusyTabs() throws {
        let s = makeSubject()
        s.viewModel.newTab()
        let sessionID = try #require(s.viewModel.tabs.first?.root.leaves.first?.sessionID)
        s.sessions.busySessionIDs.insert(sessionID)
        let sessionsBefore = s.sessions.createdSessions.count
        s.viewModel.openWorkspace(singlePaneWorkspace())

        s.viewModel.cancelPendingClose()

        #expect(s.viewModel.pendingClose == nil)
        #expect(s.sessions.terminatedSessionIDs.isEmpty)
        #expect(s.sessions.createdSessions.count == sessionsBefore)
        #expect(s.viewModel.tabs.first?.root.leaves.first?.sessionID == sessionID)
    }

    @Test func openWorkspaceDoesNotOverrideAPendingCloseConfirmation() throws {
        let s = makeSubject()
        s.viewModel.newTab()
        let tab = try #require(s.viewModel.tabs.first)
        s.sessions.busySessionIDs.insert(try #require(tab.root.leaves.first?.sessionID))
        s.viewModel.requestCloseTab(id: tab.id)
        let pendingBefore = s.viewModel.pendingClose

        s.viewModel.openWorkspace(singlePaneWorkspace(command: "npm run dev"))

        #expect(s.viewModel.pendingClose == pendingBefore)
        #expect(s.viewModel.pendingWorkspaceLaunch == nil)
        #expect(s.sessions.createdStartupCommands.compactMap { $0 }.isEmpty)
    }

    @Test func openWorkspaceIgnoresASecondRequestWhileApprovalIsPending() throws {
        let s = makeSubject()
        let first = singlePaneWorkspace(command: "npm run dev")
        let second = Workspace(name: "Web",
                               directory: "/Users/dev/web",
                               tabs: [WorkspaceTab(layout: .pane(WorkspacePane(startupCommand: "vite")))])
        s.viewModel.openWorkspace(first)

        s.viewModel.openWorkspace(second)

        #expect(s.viewModel.pendingWorkspaceLaunch?.workspace.id == first.id)
        #expect(s.viewModel.pendingWorkspaceLaunch?.commands == ["npm run dev"])
    }
}
