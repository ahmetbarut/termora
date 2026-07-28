import Foundation
import Testing
@testable import Termora

/// Ayarın açılış ve kapanış davranışını nasıl kapıya bağladığı (briefs/2 "Oturum Geri Yükleme").
@MainActor
@Suite struct SessionRestoreWiringTests {

    private static func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "SessionRestoreWiringTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func window(title: String) -> SessionWindowSnapshot {
        SessionWindowSnapshot(
            tabs: [SessionTabSnapshot(
                tab: WorkspaceTab(title: title,
                                  layout: .pane(WorkspacePane(startupDirectory: "/Users/dev"))))])
    }

    /// Diske hem ayarı hem de önceki oturumu yazar.
    private func seed(_ defaults: UserDefaults, restores: Bool, windows: [SessionWindowSnapshot]) {
        let settings = SettingsStore(defaults: defaults)
        settings.settings.restoresPreviousSession = restores
        SessionRestoreStore(defaults: defaults).replaceAll(with: windows)
    }

    // MARK: - Açılış

    @Test func launchWithTheSettingOffRestoresNothing() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        seed(defaults, restores: false, windows: [window(title: "A"), window(title: "B")])

        let services = AppServices(defaults: defaults)

        // Kayıt DİSKTE duruyor ama kuyruk boş: hiçbir pencere geri yüklenmez.
        #expect(services.sessionRestore.snapshot.windows.count == 2)
        #expect(services.sessionRestore.pendingWindowCount == 0)
        #expect(services.sessionRestore.claimWindow() == nil)
        #expect(services.sessionRestore.claimAdditionalWindowCount() == 0)
    }

    @Test func launchWithTheSettingOnQueuesEverySavedWindow() throws {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = window(title: "A")
        seed(defaults, restores: true, windows: [first, window(title: "B")])

        let services = AppServices(defaults: defaults)

        #expect(services.sessionRestore.pendingWindowCount == 2)
        #expect(try #require(services.sessionRestore.claimWindow()).id == first.id)
        #expect(services.sessionRestore.claimAdditionalWindowCount() == 1)
    }

    // MARK: - Kapanış

    @Test func quittingWithTheSettingOnRecordsTheOpenWindows() throws {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        seed(defaults, restores: true, windows: [])
        let services = AppServices(defaults: defaults)

        services.persistSessionSnapshot(windows: [window(title: "Still Open")])

        #expect(SessionRestoreStore(defaults: defaults).snapshot.windows.count == 1)
        #expect(services.sessionRestore.snapshot.windows.first?.tabs.first?.tab.title == "Still Open")
    }

    @Test func quittingWithNoOpenWindowsLeavesNothingToRestore() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        seed(defaults, restores: true, windows: [window(title: "Closed Earlier")])
        let services = AppServices(defaults: defaults)

        // macOS konvansiyonu: kullanıcı tüm pencereleri kapatıp çıktıysa uygulama temiz açılır.
        services.persistSessionSnapshot(windows: [])

        #expect(services.sessionRestore.snapshot.windows.isEmpty)
        #expect(SessionRestoreStore(defaults: defaults).snapshot.windows.isEmpty)
    }

    @Test func quittingWithTheSettingOffErasesTheRecord() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        seed(defaults, restores: false, windows: [window(title: "Leftover")])
        let services = AppServices(defaults: defaults)

        services.persistSessionSnapshot(windows: [window(title: "Ignore Me")])

        // Gizlilik: kapalı bir özellik çalışma dizinlerini diske YAZMAZ ve eski izi de siler.
        #expect(services.sessionRestore.snapshot.windows.isEmpty)
        #expect(defaults.data(forKey: SessionRestoreStore.storageKey) == nil)
    }
}
