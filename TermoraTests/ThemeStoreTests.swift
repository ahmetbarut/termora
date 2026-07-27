import Foundation
import Testing
@testable import Termora

private final class FixtureBundleToken {}

@MainActor
@Suite struct ThemeStoreTests {
    private var fixtureBundle: Bundle { Bundle(for: FixtureBundleToken.self) }

    @Test func loadsValidFixtureTheme() {
        let store = ThemeStore(bundle: fixtureBundle)
        let theme = store.theme(id: "fixture-valid")
        #expect(theme.id == "fixture-valid")
        #expect(theme.name == "Fixture Valid")
        #expect(theme.ansi.count == 16)
    }

    @Test func skipsBrokenFixtureTheme() {
        let store = ThemeStore(bundle: fixtureBundle)
        #expect(!store.themes.contains { $0.id == "fixture-broken" })
    }

    @Test func unknownIDReturnsFallback() {
        let store = ThemeStore(bundle: fixtureBundle)
        let theme = store.theme(id: "no-such-theme")
        #expect(theme == ThemeStore.fallback)
        #expect(theme.id == "termora-dark")
    }

    @Test func fallbackThemeIsComplete() {
        #expect(ThemeStore.fallback.id == "termora-dark")
        #expect(ThemeStore.fallback.ansi.count == 16)
        #expect(ThemeStore.fallback.swiftTermAnsiColors().count == 16)
    }
}
