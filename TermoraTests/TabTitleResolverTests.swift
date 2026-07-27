import Foundation
import Testing
@testable import Termora

/// Pure priority chain for a tab's automatic title (brief 3, "Tab Bar"):
/// foreground process -> shell reported title -> working directory -> profile -> shell name.
@MainActor
@Suite struct TabTitleResolverTests {

    @Test func foregroundProcessWinsOverEverythingElse() {
        let title = TabTitleResolver.automaticTitle(
            foregroundProcessName: "npm",
            shellReportedTitle: "~/code — zsh",
            workingDirectory: "/Users/me/code",
            profileName: "Server",
            shellPath: "/bin/zsh"
        )
        #expect(title == "npm")
    }

    @Test func shellReportedTitleWinsWhenNoForegroundProcess() {
        let title = TabTitleResolver.automaticTitle(
            foregroundProcessName: nil,
            shellReportedTitle: "~/code — zsh",
            workingDirectory: "/Users/me/code",
            profileName: "Server",
            shellPath: "/bin/zsh"
        )
        #expect(title == "~/code — zsh")
    }

    @Test func workingDirectoryBasenameComesNext() {
        let title = TabTitleResolver.automaticTitle(
            foregroundProcessName: nil,
            shellReportedTitle: "",
            workingDirectory: "/Users/me/code",
            profileName: "Server",
            shellPath: "/bin/zsh"
        )
        #expect(title == "code")
    }

    @Test func rootDirectoryKeepsASlash() {
        let title = TabTitleResolver.automaticTitle(
            foregroundProcessName: nil,
            shellReportedTitle: "",
            workingDirectory: "/",
            profileName: nil,
            shellPath: "/bin/zsh"
        )
        #expect(title == "/")
    }

    @Test func profileNameComesBeforeShellName() {
        let title = TabTitleResolver.automaticTitle(
            foregroundProcessName: nil,
            shellReportedTitle: "",
            workingDirectory: nil,
            profileName: "Server",
            shellPath: "/bin/zsh"
        )
        #expect(title == "Server")
    }

    @Test func shellNameIsTheLastResort() {
        let title = TabTitleResolver.automaticTitle(
            foregroundProcessName: nil,
            shellReportedTitle: "",
            workingDirectory: nil,
            profileName: nil,
            shellPath: "/bin/zsh"
        )
        #expect(title == "zsh")
    }

    @Test func blankCandidatesAreSkipped() {
        let title = TabTitleResolver.automaticTitle(
            foregroundProcessName: "   ",
            shellReportedTitle: "  ",
            workingDirectory: "   ",
            profileName: " ",
            shellPath: "/bin/bash"
        )
        #expect(title == "bash")
    }

    @Test func everythingEmptyYieldsEmptyString() {
        let title = TabTitleResolver.automaticTitle(
            foregroundProcessName: nil,
            shellReportedTitle: "",
            workingDirectory: nil,
            profileName: nil,
            shellPath: ""
        )
        #expect(title.isEmpty)
    }
}

/// `WorkspaceViewModel` reads the foreground command through an optional capability of its
/// session manager, so the priority chain can be exercised without a live pseudo-terminal.
@MainActor
@Suite struct ForegroundProcessTitleTests {

    private func makeWorkspace() -> (WorkspaceViewModel, ForegroundNamingSessionManager) {
        let defaults = UserDefaults(suiteName: "ForegroundProcessTitleTests.\(UUID().uuidString)")!
        let manager = ForegroundNamingSessionManager()
        let workspace = WorkspaceViewModel(
            sessionManager: manager,
            settings: SettingsStore(defaults: defaults),
            profiles: ProfileStore(defaults: defaults)
        )
        return (workspace, manager)
    }

    @Test func runningCommandBecomesTheTabTitle() throws {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        let tab = try #require(workspace.tabs.first)
        let sessionID = try #require(tab.root.leaves.first?.sessionID)
        manager.session(id: sessionID)?.workingDirectory = "/Users/me/code"
        manager.foregroundNames[sessionID] = "npm"

        workspace.syncAutomaticTitles()

        #expect(tab.automaticTitle == "npm")
        #expect(tab.displayTitle == "npm")
    }

    @Test func titleFallsBackWhenTheCommandExits() throws {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        let tab = try #require(workspace.tabs.first)
        let sessionID = try #require(tab.root.leaves.first?.sessionID)
        manager.session(id: sessionID)?.workingDirectory = "/Users/me/code"
        manager.foregroundNames[sessionID] = "npm"
        workspace.syncAutomaticTitles()

        manager.foregroundNames[sessionID] = nil
        workspace.syncAutomaticTitles()

        #expect(tab.automaticTitle == "code")
    }

    @Test func userGivenNameStillOutranksTheRunningCommand() throws {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        let tab = try #require(workspace.tabs.first)
        let sessionID = try #require(tab.root.leaves.first?.sessionID)
        manager.foregroundNames[sessionID] = "npm"
        workspace.renameTab(id: tab.id, to: "Build")

        workspace.syncAutomaticTitles()

        #expect(tab.displayTitle == "Build")
    }

    @Test func closeConfirmationNamesTheRunningProcess() throws {
        let (workspace, manager) = makeWorkspace()
        workspace.newTab()
        let tab = try #require(workspace.tabs.first)
        let sessionID = try #require(tab.root.leaves.first?.sessionID)
        manager.busySessionIDs.insert(sessionID)
        manager.foregroundNames[sessionID] = "npm run dev"

        workspace.requestCloseTab(id: tab.id)

        #expect(workspace.pendingCloseTitle == "Do you want to close this tab?")
        #expect(workspace.pendingCloseMessage == "A process is still running: npm run dev")
    }
}

/// Decorates `MockSessionManager` with the optional foreground-command capability;
/// the shared mock cannot be subclassed (it is `final`).
@MainActor
final class ForegroundNamingSessionManager: SessionManaging, ForegroundProcessNaming {
    private let base = MockSessionManager()

    /// Command reported as running in the foreground of a session's pseudo-terminal.
    var foregroundNames: [UUID: String] = [:]

    var busySessionIDs: Set<UUID> {
        get { base.busySessionIDs }
        set { base.busySessionIDs = newValue }
    }

    func createSession(profile: TerminalProfile?, workingDirectory: String?) -> TerminalSession {
        base.createSession(profile: profile, workingDirectory: workingDirectory)
    }

    func session(id: UUID) -> TerminalSession? { base.session(id: id) }

    func terminateSession(id: UUID) { base.terminateSession(id: id) }

    func hasRunningProcess(sessionID: UUID) -> Bool { base.hasRunningProcess(sessionID: sessionID) }

    func restartSession(id: UUID, forceDefaultShell: Bool) {
        base.restartSession(id: id, forceDefaultShell: forceDefaultShell)
    }

    func foregroundProcessName(sessionID: UUID) -> String? { foregroundNames[sessionID] }
}
