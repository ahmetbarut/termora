import Foundation
import Testing
@testable import Termora

/// Hem oturum yöneticisi hem arama yürütücüsü rolünü üstlenen çift.
@MainActor
final class WorkspaceSearchStubManager: SessionManaging, TerminalSearchRunner {
    private var storage: [UUID: TerminalSession] = [:]
    var summaryToReturn = SearchSummary(index: 1, total: 3)
    private(set) var findNextCalls: [(sessionID: UUID, query: TerminalSearchQuery)] = []
    private(set) var findPreviousCalls: [(sessionID: UUID, query: TerminalSearchQuery)] = []
    private(set) var clearCalls: [UUID] = []
    private(set) var focusCalls: [UUID] = []

    func createSession(profile: TerminalProfile?, workingDirectory: String?) -> TerminalSession {
        let session = TerminalSession(shellPath: "/bin/zsh",
                                      profileID: profile?.id,
                                      workingDirectory: workingDirectory)
        storage[session.id] = session
        return session
    }
    func session(id: UUID) -> TerminalSession? { storage[id] }
    func terminateSession(id: UUID) { storage[id] = nil }
    func hasRunningProcess(sessionID: UUID) -> Bool { false }

    /// `SessionManaging`'in beşinci üyesi (Task 8). Arama süiti yeniden başlatmayı test
    /// etmez ama protokol zorunlu kıldığı için burada da bulunmalı; çağrı yalnız kaydedilir.
    private(set) var restartedSessionIDs: [UUID] = []
    func restartSession(id: UUID, forceDefaultShell: Bool) { restartedSessionIDs.append(id) }

    func findNext(sessionID: UUID, query: TerminalSearchQuery) -> Bool {
        findNextCalls.append((sessionID, query))
        return summaryToReturn.total > 0
    }
    func findPrevious(sessionID: UUID, query: TerminalSearchQuery) -> Bool {
        findPreviousCalls.append((sessionID, query))
        return summaryToReturn.total > 0
    }
    func matchSummary(sessionID: UUID, query: TerminalSearchQuery) -> SearchSummary { summaryToReturn }
    func clearSearch(sessionID: UUID) { clearCalls.append(sessionID) }
    func focusTerminal(sessionID: UUID) { focusCalls.append(sessionID) }
}

@Suite("WorkspaceViewModel search")
@MainActor
struct WorkspaceSearchTests {

    private func makeWorkspace() -> (WorkspaceViewModel, WorkspaceSearchStubManager) {
        let suiteName = "termora.search.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let stub = WorkspaceSearchStubManager()
        let workspace = WorkspaceViewModel(sessionManager: stub,
                                           settings: SettingsStore(defaults: defaults),
                                           profiles: ProfileStore(defaults: defaults))
        workspace.newTab()
        return (workspace, stub)
    }

    /// Aktif sekmenin tek panelinin oturum kimliği. Dizi indeksi/force-unwrap yerine
    /// `#require` kullanılır: kırmızı fazda çökme TÜM test sürecini öldürür.
    private func activeSessionID(_ workspace: WorkspaceViewModel) throws -> UUID {
        let tab = try #require(workspace.activeTab)
        return try #require(tab.root.leaves.first?.sessionID)
    }

    @Test func toggleShowsAndHidesSearchBar() {
        let (workspace, stub) = makeWorkspace()

        workspace.toggleSearchBar()
        #expect(workspace.activeTab?.isSearchVisible == true)

        workspace.toggleSearchBar()
        #expect(workspace.activeTab?.isSearchVisible == false)
        #expect(stub.clearCalls.count == 1)
        #expect(stub.focusCalls.count == 1)
    }

    @Test func findNextForwardsQueryOfActivePaneAndStoresSummary() throws {
        let (workspace, stub) = makeWorkspace()
        let sessionID = try activeSessionID(workspace)
        workspace.activeTab?.searchQuery = TerminalSearchQuery(term: "error", caseSensitive: true, wholeWord: true)
        stub.summaryToReturn = SearchSummary(index: 2, total: 14)

        workspace.findNextMatch()

        #expect(stub.findNextCalls.count == 1)
        #expect(stub.findNextCalls.first?.sessionID == sessionID)
        #expect(stub.findNextCalls.first?.query.term == "error")
        #expect(stub.findNextCalls.first?.query.caseSensitive == true)
        #expect(stub.findNextCalls.first?.query.wholeWord == true)
        #expect(workspace.activeTab?.searchSummary == SearchSummary(index: 2, total: 14))
    }

    @Test func findPreviousForwardsQuery() {
        let (workspace, stub) = makeWorkspace()
        workspace.activeTab?.searchQuery = TerminalSearchQuery(term: "warn")

        workspace.findPreviousMatch()

        #expect(stub.findPreviousCalls.count == 1)
        #expect(stub.findPreviousCalls.first?.query.term == "warn")
    }

    @Test func emptyTermDoesNotSearchAndResetsSummary() {
        let (workspace, stub) = makeWorkspace()
        workspace.activeTab?.searchSummary = SearchSummary(index: 2, total: 14)
        workspace.activeTab?.searchQuery = TerminalSearchQuery(term: "")

        workspace.refreshSearchSummary()
        workspace.findNextMatch()

        #expect(stub.findNextCalls.isEmpty)
        #expect(workspace.activeTab?.searchSummary == .empty)
        #expect(stub.clearCalls.count == 1)
    }

    @Test func closeSearchClearsHighlightAndReturnsFocus() throws {
        let (workspace, stub) = makeWorkspace()
        let sessionID = try activeSessionID(workspace)
        workspace.toggleSearchBar()
        workspace.activeTab?.searchQuery = TerminalSearchQuery(term: "abc")
        workspace.activeTab?.searchSummary = SearchSummary(index: 1, total: 4)

        workspace.closeSearch()

        #expect(workspace.activeTab?.isSearchVisible == false)
        #expect(workspace.activeTab?.searchSummary == .empty)
        #expect(stub.clearCalls == [sessionID])
        #expect(stub.focusCalls == [sessionID])
    }
}
