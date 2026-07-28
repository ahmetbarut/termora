import AppKit
import Foundation
import Testing
@testable import Termora

/// briefs/3 "Komut Paleti Tasarımı → Sonuç kategorileri: Folders" +
/// briefs/2 "Hızlı Açma": son kullanılanlar ve favoriler palette listelenir; Enter o
/// klasörde YENİ BİR SEKME açar.
@MainActor
@Suite("Komut paletinde Folders kategorisi")
struct FoldersPaletteCommandsTests {

    private static let home = "/Users/ahmet"
    private static let moment = Date(timeIntervalSince1970: 1_700_000_000)

    private struct Subject {
        let viewModel: WorkspaceViewModel
        let folders: RecentFoldersStore
        let sessions: MockSessionManager
        let settings: SettingsStore
        let themes: ThemeStore
    }

    private func makeSubject() throws -> Subject {
        let suiteName = "FoldersPalette.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let sessions = MockSessionManager()
        let settings = SettingsStore(defaults: defaults)
        let viewModel = WorkspaceViewModel(sessionManager: sessions,
                                           settings: settings,
                                           profiles: ProfileStore(defaults: defaults))
        viewModel.newTab()
        return Subject(viewModel: viewModel,
                       folders: RecentFoldersStore(defaults: defaults, home: Self.home),
                       sessions: sessions,
                       settings: settings,
                       themes: ThemeStore(bundle: .main))
    }

    private func items(_ subject: Subject,
                       folders: RecentFoldersStore?,
                       currentDirectory: String? = nil) -> [CommandPaletteItem] {
        CommandPaletteCatalog.items(workspace: subject.viewModel,
                                    settings: subject.settings,
                                    themes: subject.themes,
                                    folders: folders,
                                    currentDirectory: currentDirectory,
                                    home: Self.home,
                                    now: { Self.moment },
                                    openSettings: {})
    }

    private func folderItems(_ subject: Subject) -> [CommandPaletteItem] {
        items(subject, folders: subject.folders).filter { $0.category == .folders }
    }

    // MARK: - Listeleme

    /// Depo bağlı değilse kategori hiç çizilmez (SSH ile aynı kural).
    @Test func withoutAStoreThereIsNoFoldersCategory() throws {
        let subject = try makeSubject()
        subject.folders.recordOpen("~/Projects/pinro", at: Self.moment)

        #expect(items(subject, folders: nil).contains { $0.category == .folders } == false)
    }

    /// Boş kategori çizilmez: hiç klasör yokken "Folders" başlığı görünmemeli.
    @Test func noFoldersMeansNoCategory() throws {
        let subject = try makeSubject()

        #expect(folderItems(subject).isEmpty)
    }

    @Test func listsFavoritesBeforeRecents() throws {
        let subject = try makeSubject()
        subject.folders.recordOpen("~/Projects/pinro", at: Self.moment)
        subject.folders.addFavorite("~/Work/api", at: Self.moment)

        #expect(folderItems(subject).map(\.title) == ["~/Work/api", "~/Projects/pinro"])
    }

    /// Başlık kısaltılmış yoldur: aynı adlı iki klasör palet satırında ayırt edilebilmeli.
    @Test func twoFoldersWithTheSameNameStayDistinguishable() throws {
        let subject = try makeSubject()
        subject.folders.recordOpen("~/a/pinro", at: Self.moment)
        subject.folders.recordOpen("~/b/pinro", at: Self.moment)

        #expect(Set(folderItems(subject).map(\.title)) == ["~/a/pinro", "~/b/pinro"])
    }

    @Test func everyFolderCommandHasAUniqueIdentifierAndAResolvableSymbol() throws {
        let subject = try makeSubject()
        subject.folders.recordOpen("~/Projects/pinro", at: Self.moment)
        subject.folders.addFavorite("~/Work/api", at: Self.moment)
        let all = items(subject, folders: subject.folders)

        #expect(Set(all.map(\.id)).count == all.count)
        for item in folderItems(subject) {
            #expect(NSImage(systemSymbolName: item.symbolName, accessibilityDescription: nil) != nil)
        }
    }

    /// Aynı klasör hem favori hem son kullanılansa palette TEK satır çizilir.
    @Test func aFolderThatIsBothFavoriteAndRecentIsListedOnce() throws {
        let subject = try makeSubject()
        subject.folders.recordOpen("~/Projects/pinro", at: Self.moment)
        subject.folders.addFavorite("~/Projects/pinro", at: Self.moment)

        #expect(folderItems(subject).count == 1)
    }

    /// Her satırın VoiceOver etiketi vardır ve favori/son kullanılan ayrımını SÖYLER;
    /// ayrım yalnız ikon ya da renkle bırakılmaz.
    @Test func everyFolderRowHasASpokenLabelThatNamesItsKind() throws {
        let subject = try makeSubject()
        subject.folders.recordOpen("~/Projects/pinro", at: Self.moment)
        subject.folders.addFavorite("~/Work/api", at: Self.moment)

        #expect(folderItems(subject).map(\.accessibilityLabel)
                == ["Favorite folder ~/Work/api", "Recent folder ~/Projects/pinro"])
    }

    @Test func foldersIsListedAsItsOwnCategoryWithAResolvableIcon() {
        #expect(CommandPaletteCategory.folders.title == "Folders")
        #expect(NSImage(systemSymbolName: CommandPaletteCategory.folders.symbolName,
                        accessibilityDescription: nil) != nil)
    }

    // MARK: - Enter: klasörde yeni sekme

    @Test func runningAFolderCommandOpensANewTabInThatDirectory() throws {
        let subject = try makeSubject()
        subject.folders.recordOpen("~/Projects/pinro", at: Self.moment)
        let tabsBefore = subject.viewModel.tabs.count

        try #require(folderItems(subject).first).action()

        #expect(subject.viewModel.tabs.count == tabsBefore + 1)
        #expect(subject.sessions.createdProfiles.last??.startupDirectory
                == "/Users/ahmet/Projects/pinro")
    }

    /// GÜVENLİK: klasör açmak KOMUT ÇALIŞTIRMAZ.
    @Test func openingAFolderNeverCarriesAStartupCommand() throws {
        let subject = try makeSubject()
        subject.folders.recordOpen("~/Projects/pinro", at: Self.moment)

        try #require(folderItems(subject).first).action()

        #expect(subject.sessions.createdStartupCommands.last == .some(nil))
    }

    /// Açık sekmeler kapanmaz: klasör açmak pencereyi sıfırlayan bir işlem DEĞİLDİR.
    @Test func openingAFolderLeavesTheOpenTabsAlone() throws {
        let subject = try makeSubject()
        subject.folders.recordOpen("~/Projects/pinro", at: Self.moment)

        try #require(folderItems(subject).first).action()

        #expect(subject.sessions.terminatedSessionIDs.isEmpty)
    }

    @Test func theNewTabIsNamedAfterTheFolder() throws {
        let subject = try makeSubject()
        subject.folders.recordOpen("~/Projects/pinro", at: Self.moment)

        try #require(folderItems(subject).first).action()

        #expect(subject.viewModel.activeTab?.displayTitle == "pinro")
    }

    /// Palet üzerinden açmak da bir "açma"dır: klasör listenin başına taşınır.
    @Test func openingAFolderFromThePaletteRefreshesItsPlaceInTheHistory() throws {
        let subject = try makeSubject()
        subject.folders.recordOpen("~/a", at: Self.moment)
        subject.folders.recordOpen("~/b", at: Self.moment)

        let itemForA = try #require(folderItems(subject).first { $0.title == "~/a" })
        itemForA.action()

        #expect(subject.folders.recents.map(\.path) == ["/Users/ahmet/a", "/Users/ahmet/b"])
    }

    // MARK: - Favoriye alma / çıkarma

    /// Aktif panelin dizini bilinmiyorsa (ya da depo yoksa) komut hiç görünmez.
    @Test func withoutACurrentDirectoryThereIsNoFavoriteCommand() throws {
        let subject = try makeSubject()
        let ids = Set(items(subject, folders: subject.folders).map(\.id))

        #expect(ids.contains("action.addFolderToFavorites") == false)
        #expect(ids.contains("action.removeFolderFromFavorites") == false)
    }

    @Test func theCurrentFolderCanBeFavorited() throws {
        let subject = try makeSubject()
        let all = items(subject, folders: subject.folders, currentDirectory: "/Users/ahmet/Projects/pinro")
        let add = try #require(all.first { $0.id == "action.addFolderToFavorites" })

        #expect(add.title == "Add “pinro” to Favorites")
        add.action()

        #expect(subject.folders.favorites.map(\.path) == ["/Users/ahmet/Projects/pinro"])
    }

    /// Klasör zaten favoriyse yalnız çıkarma komutu görünür — iki karşıt komut aynı anda
    /// listelenmez.
    @Test func aFavoritedFolderOffersOnlyTheRemoveCommand() throws {
        let subject = try makeSubject()
        subject.folders.addFavorite("/Users/ahmet/Projects/pinro", at: Self.moment)
        let all = items(subject, folders: subject.folders, currentDirectory: "~/Projects/pinro")
        let ids = Set(all.map(\.id))

        #expect(ids.contains("action.addFolderToFavorites") == false)
        let remove = try #require(all.first { $0.id == "action.removeFolderFromFavorites" })
        #expect(remove.title == "Remove “pinro” from Favorites")

        remove.action()
        #expect(subject.folders.favorites.isEmpty)
    }

    /// Favoriye almak geçmişe YAZMAZ: kullanıcı klasörü açmadı, işaretledi.
    @Test func favoritingDoesNotRecordAnOpen() throws {
        let subject = try makeSubject()
        let all = items(subject, folders: subject.folders, currentDirectory: "/Users/ahmet/Projects/pinro")

        try #require(all.first { $0.id == "action.addFolderToFavorites" }).action()

        #expect(subject.folders.recents.isEmpty)
    }
}
