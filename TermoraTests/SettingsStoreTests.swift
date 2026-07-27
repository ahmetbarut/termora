import Foundation
import Testing
@testable import Termora

@MainActor
@Suite struct SettingsStoreTests {
    private static func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "SettingsStoreTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    @Test func freshStoreUsesDefaults() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        #expect(store.settings == AppSettings())
    }

    @Test func mutationPersistsAndRoundTrips() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        store.settings.fontSize = 18
        store.settings.themeID = "dracula"

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.settings.fontSize == 18)
        #expect(reloaded.settings.themeID == "dracula")
        #expect(reloaded.settings == store.settings)
    }

    @Test func didSetWritesEncodedBlobUnderStorageKey() throws {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        store.settings.scrollbackLines = 25_000

        let data = try #require(defaults.data(forKey: SettingsStore.storageKey))
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded.scrollbackLines == 25_000)
    }
}
