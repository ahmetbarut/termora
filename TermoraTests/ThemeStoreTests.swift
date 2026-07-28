import Foundation
import Testing
@testable import Termora

private final class FixtureBundleToken {}

@MainActor
@Suite struct ThemeStoreTests {
    private var fixtureBundle: Bundle { Bundle(for: FixtureBundleToken.self) }

    /// Paket temalarını sınayan her testin kullanıcı klasörü BOŞ olmalı. Uygulama sandbox'sız
    /// olduğu için varsayılan klasör geliştiricinin gerçek Application Support'udur; oradan
    /// okuyan bir test makineden makineye farklı sonuç verirdi.
    static func store(bundle: Bundle) -> ThemeStore {
        ThemeStore(bundle: bundle, userThemesDirectory: emptyDirectory())
    }

    /// Var olmayan benzersiz bir yol: `ThemeStore` okuyamadığı klasörü boş sayar,
    /// böylece test diske hiçbir şey bırakmaz.
    static func emptyDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("termora-no-user-themes-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func loadsValidFixtureTheme() {
        let store = Self.store(bundle: fixtureBundle)
        let theme = store.theme(id: "fixture-valid")
        #expect(theme.id == "fixture-valid")
        #expect(theme.name == "Fixture Valid")
        #expect(theme.ansi.count == 16)
    }

    @Test func skipsBrokenFixtureTheme() {
        let store = Self.store(bundle: fixtureBundle)
        #expect(!store.themes.contains { $0.id == "fixture-broken" })
    }

    @Test func unknownIDReturnsFallback() {
        let store = Self.store(bundle: fixtureBundle)
        let theme = store.theme(id: "no-such-theme")
        #expect(theme == ThemeStore.fallback)
        #expect(theme.id == "termora-dark")
    }

    @Test func fallbackThemeIsComplete() {
        #expect(ThemeStore.fallback.id == "termora-dark")
        #expect(ThemeStore.fallback.ansi.count == 16)
        #expect(ThemeStore.fallback.swiftTermAnsiColors().count == 16)
    }

    @Test func appBundleShipsFiveThemes() {
        let store = Self.store(bundle: .main)
        let ids = Set(store.themes.map(\.id))
        #expect(ids.isSuperset(of: ["termora-dark", "termora-light", "dracula", "nord", "tokyo-night"]))
    }
}
