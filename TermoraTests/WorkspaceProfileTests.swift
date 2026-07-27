import Foundation
import Testing
@testable import Termora

@Suite("Profille yeni sekme")
@MainActor
struct WorkspaceProfileTests {

    private func makeWorkspace() -> (WorkspaceViewModel, ProfileLaunchMockSessionManager, ProfileStore) {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let settingsStore = SettingsStore(defaults: defaults)
        let profileStore = ProfileStore(defaults: defaults)
        let mock = ProfileLaunchMockSessionManager()
        let workspace = WorkspaceViewModel(
            sessionManager: mock,
            settings: settingsStore,
            profiles: profileStore
        )
        return (workspace, mock, profileStore)
    }

    @Test func newTabWithProfileForwardsProfileToSessionManager() {
        let (workspace, mock, _) = makeWorkspace()
        let profile = TerminalProfile(
            name: "Fish",
            shellPath: "/opt/homebrew/bin/fish",
            startupDirectory: "/tmp"
        )

        workspace.newTab(profile: profile)

        #expect(mock.createCalls.count == 1)
        #expect(mock.createCalls.last?.profile?.id == profile.id)
        #expect(mock.createCalls.last?.profile?.shellPath == "/opt/homebrew/bin/fish")
    }

    @Test func newTabWithProfileCreatesSessionWithProfileShellAndDirectory() throws {
        let (workspace, mock, _) = makeWorkspace()
        let profile = TerminalProfile(
            name: "Fish",
            shellPath: "/opt/homebrew/bin/fish",
            startupDirectory: "/tmp"
        )

        workspace.newTab(profile: profile)

        let tab = try #require(workspace.activeTab)
        let leaves = tab.root.leaves
        #expect(leaves.count == 1)
        let leaf = try #require(leaves.first)
        let session = try #require(mock.session(id: leaf.sessionID))
        #expect(session.shellPath == "/opt/homebrew/bin/fish")
        #expect(session.workingDirectory == "/tmp")
        #expect(session.profileID == profile.id)
    }

    @Test func newTabWithoutProfileUsesDefaultShell() throws {
        let (workspace, mock, _) = makeWorkspace()

        workspace.newTab()

        #expect(mock.createCalls.count == 1)
        #expect(mock.createCalls.last?.profile == nil)
        let tab = try #require(workspace.activeTab)
        let leaf = try #require(tab.root.leaves.first)
        let session = try #require(mock.session(id: leaf.sessionID))
        #expect(session.shellPath == mock.defaultShellPath)
        #expect(session.profileID == nil)
    }

    @Test func eachProfileTabGetsItsOwnSession() {
        let (workspace, mock, _) = makeWorkspace()
        let profile = TerminalProfile(name: "Fish", shellPath: "/opt/homebrew/bin/fish")

        workspace.newTab(profile: profile)
        workspace.newTab(profile: profile)

        #expect(mock.createCalls.count == 2)
        #expect(workspace.tabs.count == 2)
        let sessionIDs = workspace.tabs.flatMap { $0.root.leaves.map(\.sessionID) }
        #expect(Set(sessionIDs).count == 2)
    }
}
