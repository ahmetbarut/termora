import Foundation
import Testing
@testable import Termora

/// Açık pencerenin anlık görüntüye çevrilmesi ve kayıttan geri kurulması
/// (briefs/2 "Oturum Geri Yükleme").
@MainActor
@Suite struct SessionRestoreTests {

    private func makeViewModel() -> (vm: WorkspaceViewModel, mock: MockSessionManager, suiteName: String) {
        let mock = MockSessionManager()
        let suiteName = "SessionRestoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = SettingsStore(defaults: defaults)
        let profiles = ProfileStore(defaults: defaults)
        let vm = WorkspaceViewModel(sessionManager: mock, settings: settings, profiles: profiles)
        return (vm, mock, suiteName)
    }

    /// ((A | B) üstünde C) — iç içe split; round-trip'in asıl sınavı.
    private func nestedWindow(directory: String = "/Users/dev",
                              startupCommand: String? = nil) -> SessionWindowSnapshot {
        let a = WorkspacePane(startupDirectory: "\(directory)/api", startupCommand: startupCommand)
        let b = WorkspacePane(startupDirectory: "\(directory)/api/logs", startupCommand: startupCommand)
        let c = WorkspacePane(startupDirectory: "\(directory)/web", startupCommand: startupCommand)
        let layout = WorkspaceLayout.split(
            axis: .horizontal,
            ratio: 0.3,
            first: .split(axis: .vertical, ratio: 0.7, first: .pane(a), second: .pane(b)),
            second: .pane(c))
        let tab = WorkspaceTab(title: "Server", layout: layout)
        return SessionWindowSnapshot(tabs: [SessionTabSnapshot(tab: tab, activePaneID: b.id)],
                                     activeTabID: tab.id)
    }

    // MARK: - Güvenlik: geri yüklemede komut çalışmaz

    @Test func restoringNeverRunsStartupCommands() {
        let (vm, mock, suiteName) = makeViewModel()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        // Elle düzenlenmiş ya da eski bir blob komut TAŞIYOR olabilir.
        vm.restoreSession(from: nestedWindow(startupCommand: "rm -rf ~/"),
                          directoryExists: { _ in true })

        #expect(mock.createdSessions.count == 3)
        // briefs/2 güvenlik kuralı: kullanıcı onayı olmadan hiçbir başlangıç komutu çalışmaz.
        #expect(mock.createdStartupCommands.allSatisfy { $0 == nil })
        // Profil hiç kurulmaz: komutun shell'e ulaşabileceği TEK yol profildir.
        #expect(mock.createdProfiles.allSatisfy { $0 == nil })
    }

    @Test func restoredLayoutCarriesNoStartupCommandBack() throws {
        let (vm, _, suiteName) = makeViewModel()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        vm.restoreSession(from: nestedWindow(startupCommand: "npm run dev"),
                          directoryExists: { _ in true })
        let recaptured = vm.captureSessionWindow()

        // Komut yeniden kaydedilirse bir sonraki açılışta geri gelirdi.
        let panes = try #require(recaptured.tabs.first).tab.layout.panes
        #expect(panes.allSatisfy { $0.startupCommand == nil })
    }

    // MARK: - Geri yükleme

    @Test func restoringStartsFreshShellsInTheSavedDirectories() {
        let (vm, mock, suiteName) = makeViewModel()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        vm.restoreSession(from: nestedWindow(), directoryExists: { _ in true })

        #expect(mock.createdWorkingDirectories == ["/Users/dev/api", "/Users/dev/api/logs", "/Users/dev/web"])
        // Süreç devamlılığı taklit edilmez: her panel için YENİ bir oturum açılır.
        #expect(mock.createdSessions.count == 3)
    }

    @Test func restoringRebuildsTheNestedSplitTree() throws {
        let (vm, _, suiteName) = makeViewModel()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        let window = nestedWindow()
        vm.restoreSession(from: window, directoryExists: { _ in true })

        let tab = try #require(vm.tabs.first)
        guard case let .split(_, axis, ratio, first, second) = tab.root else {
            Issue.record("Root should be a split")
            return
        }
        #expect(axis == .horizontal)
        #expect(ratio == 0.3)
        #expect(second.leaves.count == 1)
        guard case let .split(_, innerAxis, innerRatio, _, _) = first else {
            Issue.record("First child should itself be a split")
            return
        }
        #expect(innerAxis == .vertical)
        #expect(innerRatio == 0.7)
        #expect(tab.root.leaves.count == 3)
    }

    @Test func restoringKeepsTabIdentityTitleAndFocus() throws {
        let (vm, _, suiteName) = makeViewModel()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        let window = nestedWindow()
        let savedTab = try #require(window.tabs.first)
        vm.restoreSession(from: window, directoryExists: { _ in true })

        let tab = try #require(vm.tabs.first)
        #expect(tab.id == savedTab.tab.id)
        #expect(tab.customTitle == "Server")
        #expect(vm.activeTabID == savedTab.tab.id)
        #expect(tab.activePaneID == savedTab.activePaneID)
    }

    @Test func restoringAdoptsTheSavedWindowIdentity() {
        let (vm, _, suiteName) = makeViewModel()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        let window = nestedWindow()
        let fresh = vm.sessionWindowID
        vm.restoreSession(from: window, directoryExists: { _ in true })

        // Kimlik devralınmazsa `record` upsert'i şaşar ve pencere iki kez geri yüklenirdi.
        #expect(fresh != window.id)
        #expect(vm.sessionWindowID == window.id)
        #expect(vm.captureSessionWindow().id == window.id)
    }

    @Test func restoringAWindowWithNoTabsChangesNothing() {
        let (vm, mock, suiteName) = makeViewModel()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        let restored = vm.restoreSession(from: SessionWindowSnapshot(tabs: []),
                                         directoryExists: { _ in true })

        #expect(restored == false)
        #expect(vm.tabs.isEmpty)
        #expect(mock.createdSessions.isEmpty)
    }

    @Test func unknownActiveTabFallsBackToTheFirstTab() throws {
        let (vm, _, suiteName) = makeViewModel()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        var window = nestedWindow()
        window.activeTabID = UUID()  // artık var olmayan sekme
        vm.restoreSession(from: window, directoryExists: { _ in true })

        #expect(vm.activeTabID == vm.tabs.first?.id)
        #expect(vm.activeTab != nil)
    }

    // MARK: - Silinmiş klasör

    @Test func deletedDirectoryDoesNotCrashAndFallsBackToTheDefault() throws {
        let (vm, mock, suiteName) = makeViewModel()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        // Kayıttaki klasörlerin HİÇBİRİ artık diskte yok.
        vm.restoreSession(from: nestedWindow(), directoryExists: { _ in false })

        #expect(vm.tabs.count == 1)
        #expect(try #require(vm.tabs.first).root.leaves.count == 3)
        // nil → SessionManager kendi geri düşüşünü uygular (ayardaki başlangıç dizini, ev dizini).
        #expect(mock.createdWorkingDirectories == [nil, nil, nil])
    }

    @Test func onlyTheMissingDirectoryIsDropped() {
        let (vm, mock, suiteName) = makeViewModel()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        vm.restoreSession(from: nestedWindow(),
                          directoryExists: { $0 != "/Users/dev/api/logs" })

        #expect(mock.createdWorkingDirectories == ["/Users/dev/api", nil, "/Users/dev/web"])
    }

    // MARK: - Yakalama

    @Test func captureRecordsTabsDirectoriesAndFrame() throws {
        let (vm, mock, suiteName) = makeViewModel()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        vm.newTab()
        vm.splitActivePane(axis: .vertical)
        mock.createdSessions.first?.workingDirectory = "/Users/dev/api"
        mock.createdSessions.last?.workingDirectory = "/Users/dev/web"
        vm.renameTab(id: try #require(vm.activeTabID), to: "Build")

        let frame = SessionWindowFrame(x: 40, y: 60, width: 1200, height: 800)
        let snapshot = vm.captureSessionWindow(frame: frame, isFullScreen: false)

        let tab = try #require(snapshot.tabs.first)
        #expect(snapshot.tabs.count == 1)
        #expect(tab.tab.title == "Build")
        #expect(tab.tab.layout.panes.compactMap(\.startupDirectory) == ["/Users/dev/api", "/Users/dev/web"])
        #expect(snapshot.frame == frame)
        #expect(snapshot.isFullScreen == false)
        #expect(snapshot.activeTabID == vm.activeTabID)
    }

    @Test func captureKeepsEveryTabOfTheWindow() throws {
        let (vm, _, suiteName) = makeViewModel()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        vm.newTab()
        vm.newTab()
        vm.newTab()

        let snapshot = vm.captureSessionWindow()
        #expect(snapshot.tabs.count == 3)
        #expect(snapshot.tabs.map(\.tab.id) == vm.tabs.map(\.id))
    }

    @Test func captureRoundTripsThroughRestoreUnchanged() throws {
        let (source, mock, suiteName) = makeViewModel()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        source.newTab()
        source.splitActivePane(axis: .horizontal)
        source.splitActivePane(axis: .vertical)
        for (index, session) in mock.createdSessions.enumerated() {
            session.workingDirectory = "/Users/dev/pane\(index)"
        }
        source.renameTab(id: try #require(source.activeTabID), to: "Round Trip")
        let first = source.captureSessionWindow()

        let (target, _, targetSuite) = makeViewModel()
        defer { UserDefaults().removePersistentDomain(forName: targetSuite) }
        target.restoreSession(from: first, directoryExists: { _ in true })
        let second = target.captureSessionWindow()

        // Panel kimlikleri ve ağacın şekli korunur; oturum kimlikleri zaten saklanmaz.
        #expect(second.tabs.map(\.tab) == first.tabs.map(\.tab))
        #expect(second.tabs.first?.activePaneID == first.tabs.first?.activePaneID)
        #expect(second.tabs.first?.tab.layout.panes.count == 3)
    }

    @Test func captureRemembersTheOpenWorkspace() throws {
        let (vm, _, suiteName) = makeViewModel()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        let workspace = Workspace(name: "API", directory: "/Users/dev/api",
                                  tabs: [WorkspaceTab(title: "Server",
                                                      layout: .pane(WorkspacePane()))])
        vm.openWorkspace(workspace)

        #expect(vm.captureSessionWindow().workspaceID == workspace.id)
    }

    @Test func aPlainWindowIsNotTiedToAnyWorkspace() {
        let (vm, _, suiteName) = makeViewModel()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        vm.newTab()
        #expect(vm.captureSessionWindow().workspaceID == nil)
    }
}
