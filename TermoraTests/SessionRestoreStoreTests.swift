import Foundation
import Testing
@testable import Termora

/// Oturum kaydının kalıcılığı ve açılış kuyruğu (briefs/2 "Oturum Geri Yükleme").
@MainActor
@Suite struct SessionRestoreStoreTests {

    private static func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "SessionRestoreStoreTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func window(title: String, directory: String = "/Users/dev") -> SessionWindowSnapshot {
        SessionWindowSnapshot(
            tabs: [SessionTabSnapshot(
                tab: WorkspaceTab(title: title,
                                  layout: .pane(WorkspacePane(startupDirectory: directory))))])
    }

    // MARK: - Kalıcılık

    @Test func freshStoreHasNothingToRestore() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SessionRestoreStore(defaults: defaults)
        #expect(store.snapshot == .empty)
        #expect(store.snapshot.windows.isEmpty)
    }

    @Test func recordedWindowSurvivesReload() throws {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SessionRestoreStore(defaults: defaults)
        store.record(window(title: "Server", directory: "/Users/dev/api"),
                     at: Date(timeIntervalSince1970: 1_700_000_000))

        let reloaded = SessionRestoreStore(defaults: defaults)
        let restored = try #require(reloaded.snapshot.windows.first)
        #expect(reloaded.snapshot.windows.count == 1)
        #expect(restored.tabs.first?.tab.title == "Server")
        #expect(restored.tabs.first?.tab.layout.panes.first?.startupDirectory == "/Users/dev/api")
        #expect(reloaded.snapshot.savedAt == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func recordUpdatesTheSameWindowInPlace() throws {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SessionRestoreStore(defaults: defaults)
        var first = window(title: "Before")
        store.record(first)
        first.tabs = [SessionTabSnapshot(tab: WorkspaceTab(title: "After", layout: .pane(WorkspacePane())))]
        store.record(first)

        // Aynı kimlik iki kayıt üretmemeli: pencere aksi hâlde iki kez geri yüklenirdi.
        #expect(store.snapshot.windows.count == 1)
        #expect(store.snapshot.windows.first?.tabs.first?.tab.title == "After")
    }

    @Test func replaceAllDropsWindowsTheUserDeliberatelyClosed() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SessionRestoreStore(defaults: defaults)
        let closed = window(title: "Closed")
        let stillOpen = window(title: "Open")
        store.record(closed)
        store.record(stillOpen)

        store.replaceAll(with: [stillOpen])

        #expect(store.snapshot.windows.count == 1)
        #expect(store.snapshot.windows.first?.id == stillOpen.id)
        #expect(SessionRestoreStore(defaults: defaults).snapshot.windows.count == 1)
    }

    @Test func replaceAllWithNoWindowsClearsTheRecord() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SessionRestoreStore(defaults: defaults)
        store.record(window(title: "Gone"))
        store.replaceAll(with: [])

        #expect(store.snapshot.windows.isEmpty)
        #expect(SessionRestoreStore(defaults: defaults).snapshot.windows.isEmpty)
    }

    @Test func clearRemovesTheBlobFromDisk() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SessionRestoreStore(defaults: defaults)
        store.record(window(title: "Private", directory: "/Users/dev/secret"))
        store.clear()

        // Gizlilik: ayar kapatıldığında çalışma dizinleri diskte KALMAMALI.
        #expect(store.snapshot.windows.isEmpty)
        #expect(defaults.data(forKey: SessionRestoreStore.storageKey) == nil)
    }

    @Test func corruptBlobMovesToBackupAndRestoresNothing() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let garbage = Data("not json at all".utf8)
        defaults.set(garbage, forKey: SessionRestoreStore.storageKey)

        let store = SessionRestoreStore(defaults: defaults)
        #expect(store.snapshot.windows.isEmpty)
        #expect(defaults.data(forKey: SessionRestoreStore.storageKey) == nil)
        #expect(defaults.data(forKey: SessionRestoreStore.backupKey) == garbage)
    }

    // MARK: - Açılış kuyruğu

    @Test func disabledSettingRestoresNothingEvenWithAWrittenBlob() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let seed = SessionRestoreStore(defaults: defaults)
        seed.record(window(title: "A"))
        seed.record(window(title: "B"))

        let store = SessionRestoreStore(defaults: defaults)
        store.prepareRestore(isEnabled: false)

        // Ayar kapalıysa diskte kayıt olsa BİLE hiçbir pencere geri yüklenmez.
        #expect(store.pendingWindowCount == 0)
        #expect(store.claimWindow() == nil)
        #expect(store.claimAdditionalWindowCount() == 0)
    }

    @Test func enabledSettingHandsOutEveryWindowExactlyOnce() throws {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let seed = SessionRestoreStore(defaults: defaults)
        let first = window(title: "A")
        let second = window(title: "B")
        seed.replaceAll(with: [first, second])

        let store = SessionRestoreStore(defaults: defaults)
        store.prepareRestore(isEnabled: true)

        #expect(store.pendingWindowCount == 2)
        #expect(try #require(store.claimWindow()).id == first.id)
        // İlk pencere kendi payını aldıktan sonra AÇILACAK ek pencere sayısı 1'dir.
        #expect(store.claimAdditionalWindowCount() == 1)
        #expect(try #require(store.claimWindow()).id == second.id)
        #expect(store.claimWindow() == nil)
    }

    @Test func additionalWindowCountIsHandedOutOnlyOnce() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let seed = SessionRestoreStore(defaults: defaults)
        seed.replaceAll(with: [window(title: "A"), window(title: "B"), window(title: "C")])

        let store = SessionRestoreStore(defaults: defaults)
        store.prepareRestore(isEnabled: true)
        _ = store.claimWindow()

        #expect(store.claimAdditionalWindowCount() == 2)
        // İkinci çağrı 0 dönmeli; yoksa geri yükleme için açılan her pencere yeniden
        // pencere açmak ister ve uygulama pencere üretir dururdu.
        #expect(store.claimAdditionalWindowCount() == 0)
    }

    @Test func windowsWithoutTabsAreNotRestored() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let seed = SessionRestoreStore(defaults: defaults)
        seed.replaceAll(with: [SessionWindowSnapshot(tabs: []), window(title: "Real")])

        let store = SessionRestoreStore(defaults: defaults)
        store.prepareRestore(isEnabled: true)

        #expect(store.pendingWindowCount == 1)
        #expect(store.claimWindow()?.tabs.first?.tab.title == "Real")
    }
}
