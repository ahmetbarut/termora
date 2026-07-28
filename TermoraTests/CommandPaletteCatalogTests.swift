import AppKit
import Foundation
import Testing
@testable import Termora

@Suite("CommandPaletteCatalog")
@MainActor
struct CommandPaletteCatalogTests {

    private struct Fixture {
        let workspace: WorkspaceViewModel
        let sessions: MockSessionManager
        let settings: SettingsStore
        let themes: ThemeStore
        let items: [CommandPaletteItem]
        let openedSettings: () -> Int
    }

    private func makeFixture() -> Fixture {
        let suiteName = "termora.catalog.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let sessions = MockSessionManager()
        let settings = SettingsStore(defaults: defaults)
        let themes = ThemeStore(bundle: .main)
        let workspace = WorkspaceViewModel(sessionManager: sessions,
                                           settings: settings,
                                           profiles: ProfileStore(defaults: defaults))
        workspace.newTab()

        let counter = Counter()
        let items = CommandPaletteCatalog.items(workspace: workspace,
                                                settings: settings,
                                                themes: themes,
                                                openSettings: { counter.value += 1 })
        return Fixture(workspace: workspace,
                       sessions: sessions,
                       settings: settings,
                       themes: themes,
                       items: items,
                       openedSettings: { counter.value })
    }

    @MainActor
    private final class Counter {
        var value = 0
    }

    private func item(_ id: String, in items: [CommandPaletteItem]) throws -> CommandPaletteItem {
        try #require(items.first { $0.id == id }, "\(id) katalogda yok")
    }

    // MARK: - Kapsam

    @Test func identifiersAreUnique() {
        let fixture = makeFixture()
        let ids = fixture.items.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func exposesTodaysActions() {
        let fixture = makeFixture()
        let ids = Set(fixture.items.map(\.id))
        let expected: Set<String> = [
            "action.newTab", "action.closeTab",
            "action.splitVertically", "action.splitHorizontally", "action.closePane",
            "action.nextTab", "action.previousTab",
            "action.find", "action.findNext", "action.findPrevious",
            "action.focusPaneLeft", "action.focusPaneRight",
            "action.focusPaneUp", "action.focusPaneDown",
            "settings.open",
        ]
        #expect(ids.isSuperset(of: expected))
    }

    /// Workspaces / Folders / SSH / AI Actions henüz yok; boş kategori çizilmemeli.
    @Test func onlyShipsCategoriesThatHaveRealCommandsToday() {
        let fixture = makeFixture()
        let categories = Set(fixture.items.map(\.category))
        #expect(categories == [.actions, .settings, .themes])
    }

    @Test func everyItemHasATitleAndAResolvableSymbol() {
        let fixture = makeFixture()
        for item in fixture.items {
            #expect(item.title.isEmpty == false)
            #expect(NSImage(systemSymbolName: item.symbolName, accessibilityDescription: nil) != nil,
                    "\(item.id) SF Symbol'ü yok: \(item.symbolName)")
        }
        for category in CommandPaletteCategory.allCases {
            #expect(NSImage(systemSymbolName: category.symbolName, accessibilityDescription: nil) != nil,
                    "\(category.title) kategori ikonu yok: \(category.symbolName)")
        }
    }

    @Test func showsKeyboardShortcutsInMenuNotation() throws {
        let fixture = makeFixture()
        #expect(try item("action.newTab", in: fixture.items).shortcut == "⌘T")
        #expect(try item("action.splitHorizontally", in: fixture.items).shortcut == "⇧⌘D")
        #expect(try item("action.focusPaneLeft", in: fixture.items).shortcut == "⌥⌘←")
        #expect(try item("settings.open", in: fixture.items).shortcut == "⌘,")
    }

    // MARK: - Eylemler gerçekten çalışıyor mu?

    @Test func newTabActionOpensATab() throws {
        let fixture = makeFixture()
        let before = fixture.workspace.tabs.count

        try item("action.newTab", in: fixture.items).action()

        #expect(fixture.workspace.tabs.count == before + 1)
    }

    @Test func splitActionSplitsTheActivePane() throws {
        let fixture = makeFixture()
        try item("action.splitVertically", in: fixture.items).action()

        let root = try #require(fixture.workspace.activeTab?.root)
        if case .split(_, let axis, _, _, _) = root {
            #expect(axis == .vertical)
        } else {
            Issue.record("Aktif sekme bölünmedi")
        }
    }

    @Test func findActionOpensTheSearchBar() throws {
        let fixture = makeFixture()
        try item("action.find", in: fixture.items).action()
        #expect(fixture.workspace.activeTab?.isSearchVisible == true)
    }

    @Test func settingsActionCallsTheInjectedOpener() throws {
        let fixture = makeFixture()
        try item("settings.open", in: fixture.items).action()
        #expect(fixture.openedSettings() == 1)
    }

    // MARK: - Temalar

    @Test func listsEveryInstalledTheme() {
        let fixture = makeFixture()
        let themeItems = fixture.items.filter { $0.category == .themes }
        #expect(themeItems.count == fixture.themes.themes.count)
        #expect(themeItems.map(\.title) == fixture.themes.themes.map(\.name))
    }

    @Test func themeActionSwitchesTheActiveTheme() throws {
        let fixture = makeFixture()
        let target = try #require(fixture.themes.themes.first { $0.id != fixture.settings.settings.themeID })

        try item("theme.\(target.id)", in: fixture.items).action()

        #expect(fixture.settings.settings.themeID == target.id)
    }

    // MARK: - Kategori sırası (briefs/3 "Sonuç kategorileri")

    /// briefs/3 kategorileri Actions → Workspaces → **Folders** → SSH → Settings → Themes
    /// diye sayar. Sıra ekranda GERÇEKTEN `items`'ın birleştirme sırasından gelir; başka
    /// hiçbir yerde saklanmaz, çünkü iki ayrı kopya sessizce ayrışır.
    @Test func categoriesFollowTheOrderTheBriefLists() throws {
        let suiteName = "termora.catalog.order.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let settings = SettingsStore(defaults: defaults)
        let workspace = WorkspaceViewModel(sessionManager: MockSessionManager(),
                                           settings: settings,
                                           profiles: ProfileStore(defaults: defaults))
        workspace.newTab()

        let folders = RecentFoldersStore(defaults: defaults, home: "/Users/ahmet")
        folders.recordOpen("~/Projects/pinro", at: Date(timeIntervalSince1970: 1_700_000_000))
        let ssh = SSHHostStore(defaults: defaults, configLoader: { [] })
        ssh.hosts = [SSHHost(name: "Pinro", hostName: "pinro.app", user: "deploy")]

        let items: [CommandPaletteItem] = CommandPaletteCatalog.items(workspace: workspace,
                                                                      settings: settings,
                                                                      themes: ThemeStore(bundle: .main),
                                                                      ssh: ssh,
                                                                      folders: folders,
                                                                      openSettings: {})
        let categories: [CommandPaletteCategory] = items.map(\.category)

        let firstFolders = try #require(categories.firstIndex(of: .folders))
        let firstSSH = try #require(categories.firstIndex(of: .ssh))
        #expect(firstFolders < firstSSH, "briefs/3 Folders'ı SSH'tan önce sayıyor")
    }
}
