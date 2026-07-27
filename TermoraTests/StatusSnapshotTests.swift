import Foundation
import Testing
@testable import Termora

/// Durum çubuğu testleri için minimal SessionManaging. `TerminalProcessInfoProviding`'e
/// BİLEREK uymaz: böylece `statusSnapshot()` libproc yolunu atlar ve testler
/// `session.workingDirectory`'ye düşen dalı doğrular (gerçek pid'ler testte yok).
@MainActor
final class StatusStubSessionManager: SessionManaging {
    private var storage: [UUID: TerminalSession] = [:]
    var runningSessionIDs: Set<UUID> = []
    var shellPathForNewSessions = "/bin/zsh"

    func createSession(profile: TerminalProfile?, workingDirectory: String?) -> TerminalSession {
        let session = TerminalSession(shellPath: shellPathForNewSessions,
                                      profileID: profile?.id,
                                      workingDirectory: workingDirectory)
        storage[session.id] = session
        return session
    }
    func session(id: UUID) -> TerminalSession? { storage[id] }
    func terminateSession(id: UUID) { storage[id] = nil; runningSessionIDs.remove(id) }
    func hasRunningProcess(sessionID: UUID) -> Bool { runningSessionIDs.contains(sessionID) }

    func restartSession(id: UUID, forceDefaultShell: Bool) {
        guard let old = storage[id] else { return }
        storage[id] = TerminalSession(id: id,
                                      shellPath: forceDefaultShell ? shellPathForNewSessions : old.shellPath,
                                      profileID: forceDefaultShell ? nil : old.profileID,
                                      workingDirectory: old.workingDirectory)
        runningSessionIDs.remove(id)
    }
}

@Suite("WorkspaceViewModel status snapshot")
@MainActor
struct StatusSnapshotTests {

    private func makeWorkspace() -> (WorkspaceViewModel, StatusStubSessionManager, SettingsStore) {
        let suiteName = "termora.status.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let stub = StatusStubSessionManager()
        let settings = SettingsStore(defaults: defaults)
        let workspace = WorkspaceViewModel(sessionManager: stub,
                                           settings: settings,
                                           profiles: ProfileStore(defaults: defaults))
        workspace.newTab()
        return (workspace, stub, settings)
    }

    private func makeRepository(branch: String) throws -> URL {
        let repo = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("termora-status-\(UUID().uuidString)", isDirectory: true)
        let gitDir = repo.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try "ref: refs/heads/\(branch)\n"
            .write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        return repo
    }

    @Test func snapshotReportsShellBranchSizeAndBusyState() throws {
        let (workspace, stub, _) = makeWorkspace()
        let repo = try makeRepository(branch: "feature/status")
        defer { try? FileManager.default.removeItem(at: repo) }

        let tab = try #require(workspace.activeTab)
        let sessionID = try #require(tab.root.leaves.first?.sessionID)
        let session = try #require(stub.session(id: sessionID))
        session.workingDirectory = repo.path
        session.terminalSize = (cols: 100, rows: 30)
        stub.runningSessionIDs.insert(sessionID)

        let snapshot = workspace.statusSnapshot()

        #expect(snapshot?.shellName == "zsh")
        #expect(snapshot?.branchName == "feature/status")
        #expect(snapshot?.columns == 100)
        #expect(snapshot?.rows == 30)
        #expect(snapshot?.isBusy == true)
    }

    @Test func snapshotFallsBackWhenSizeAndDirectoryAreUnknown() {
        let (workspace, _, _) = makeWorkspace()

        let snapshot = workspace.statusSnapshot()

        #expect(snapshot?.workingDirectory == "—")
        #expect(snapshot?.branchName == nil)
        #expect(snapshot?.columns == 0)
        #expect(snapshot?.rows == 0)
        #expect(snapshot?.isBusy == false)
    }

    @Test func statusBarVisibilityFollowsSettings() {
        let (workspace, _, settings) = makeWorkspace()

        settings.settings.showStatusBar = true
        #expect(workspace.isStatusBarVisible)

        settings.settings.showStatusBar = false
        #expect(workspace.isStatusBarVisible == false)
    }

    @Test func terminalSizeStartsUnsetAndStoresColumnsAndRows() {
        // Not: (cols:rows:) tuple'ı Equatable değil; nil karşılaştırması alan üzerinden yapılır.
        let session = TerminalSession(shellPath: "/bin/zsh")
        #expect(session.terminalSize?.cols == nil)

        session.terminalSize = (cols: 80, rows: 24)
        #expect(session.terminalSize?.cols == 80)
        #expect(session.terminalSize?.rows == 24)
    }
}
