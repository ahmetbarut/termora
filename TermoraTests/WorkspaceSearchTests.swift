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

    /// Bu süit girdi yazmayı ölçmez; üye protokolü tamamlamak için var.
    func sendInput(_ text: String, toSession id: UUID) {}

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

    /// Çubuk kapanırken sayaç sıfırlanır ama terim korunur. Yeniden açıldığında sayacın
    /// "0/0" yalanını söylememesi için oturumdan tazelenmesi gerekir (elle doğrulamada
    /// çubuk `line [0-9]+9` terimiyle açılıp 3 eşleşme varken "0/0" gösteriyordu).
    @Test func reopeningSearchRecomputesSummaryForPreservedTerm() {
        let (workspace, stub) = makeWorkspace()
        workspace.toggleSearchBar()
        workspace.activeTab?.searchQuery = TerminalSearchQuery(term: "error")
        workspace.closeSearch()
        #expect(workspace.activeTab?.searchSummary == .empty)

        stub.summaryToReturn = SearchSummary(index: 0, total: 40)
        workspace.toggleSearchBar()

        #expect(workspace.activeTab?.isSearchVisible == true)
        #expect(workspace.activeTab?.searchSummary == SearchSummary(index: 0, total: 40))
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

    // MARK: - Search Selection (briefs/3 "Sağ Tık Menüleri")

    /// Sağ tık menüsünden gelen arama: çubuğu AÇAR, terimi seçili metne kurar ve sayacı
    /// tazeler. Kullanıcı ⌘F'e basıp metni elle yazmak zorunda kalmaz.
    @Test func searchingASelectionOpensTheBarWithThatTerm() throws {
        let (workspace, stub) = makeWorkspace()

        workspace.searchForSelection("connection refused")

        #expect(workspace.activeTab?.isSearchVisible == true)
        #expect(workspace.activeTab?.searchQuery.term == "connection refused")
        #expect(workspace.activeTab?.searchSummary == stub.summaryToReturn)
    }

    /// Çubuk zaten AÇIKSA kapanmaz — `toggleSearchBar()` çağrılsaydı ikinci bir arama
    /// çubuğu kapatır ve kullanıcı hiçbir sonuç göremezdi.
    @Test func searchingAgainWhileTheBarIsOpenDoesNotCloseIt() throws {
        let (workspace, _) = makeWorkspace()
        workspace.toggleSearchBar()

        workspace.searchForSelection("first")
        workspace.searchForSelection("second")

        #expect(workspace.activeTab?.isSearchVisible == true)
        #expect(workspace.activeTab?.searchQuery.term == "second")
    }

    /// Çok satırlı seçim arama terimi OLAMAZ (arama tek satırda çalışır); ilk dolu satır
    /// alınır. Ham metni geçirmek çubuğa görünmez bir satır sonu koyar ve hiçbir eşleşme
    /// bulunmazdı.
    @Test func aMultiLineSelectionIsReducedToItsFirstLine() throws {
        let (workspace, _) = makeWorkspace()

        workspace.searchForSelection("  \nfatal: not a git repository\nsecond line\n")

        #expect(workspace.activeTab?.searchQuery.term == "fatal: not a git repository")
    }

    /// Yalnız boşluktan oluşan seçim hiçbir şey yapmaz: boş terim çubuğu açıp "0/0"
    /// gösterirdi.
    @Test func aBlankSelectionDoesNotOpenTheBar() throws {
        let (workspace, stub) = makeWorkspace()

        workspace.searchForSelection("   \n\t ")

        #expect(workspace.activeTab?.isSearchVisible != true)
        #expect(stub.findNextCalls.isEmpty)
    }
}
