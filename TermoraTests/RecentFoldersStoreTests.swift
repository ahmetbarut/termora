import Foundation
import Testing
@testable import Termora

/// briefs/2 "Hızlı Açma": son kullanılan klasörler + favori klasörler.
///
/// "Son kullanılan" = kullanıcının AÇTIĞI klasör (workspace açma, klasörden sekme açma,
/// URL ile açma). Oturum içinde `cd` yapmak bu listeye yazmaz.
@MainActor
@Suite("Son kullanılan ve favori klasörler")
struct RecentFoldersStoreTests {

    private let home = "/Users/ahmet"

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "RecentFolders.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeStore(_ defaults: UserDefaults) -> RecentFoldersStore {
        RecentFoldersStore(defaults: defaults, home: home)
    }

    private func moment(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + offset)
    }

    // MARK: - Son kullanılanlar

    @Test func aFreshStoreIsEmpty() throws {
        let store = makeStore(try makeDefaults())

        #expect(store.recents.isEmpty)
        #expect(store.favorites.isEmpty)
        #expect(store.targets.isEmpty)
    }

    @Test func openingAFolderPutsItOnTop() throws {
        let store = makeStore(try makeDefaults())

        store.recordOpen("/Users/ahmet/a", at: moment(0))
        store.recordOpen("/Users/ahmet/b", at: moment(1))

        #expect(store.recents.map(\.path) == ["/Users/ahmet/b", "/Users/ahmet/a"])
    }

    /// Tekrar açılan klasör kopyalanmaz, yukarı TAŞINIR ve damgası tazelenir.
    @Test func reopeningAFolderMovesItUpWithoutDuplicating() throws {
        let store = makeStore(try makeDefaults())

        store.recordOpen("/Users/ahmet/a", at: moment(0))
        store.recordOpen("/Users/ahmet/b", at: moment(1))
        store.recordOpen("/Users/ahmet/a", at: moment(2))

        #expect(store.recents.map(\.path) == ["/Users/ahmet/a", "/Users/ahmet/b"])
        #expect(store.recents.first?.lastOpenedAt == moment(2))
    }

    /// Aynı klasörün farklı yazımları (tilde, çift eğik çizgi, `..`) TEK kayıttır.
    @Test func differentSpellingsOfTheSameFolderAreOneEntry() throws {
        let store = makeStore(try makeDefaults())

        store.recordOpen("~/Projects/pinro", at: moment(0))
        store.recordOpen("/Users/ahmet//Projects/pinro/", at: moment(1))
        store.recordOpen("/Users/ahmet/Projects/../Projects/pinro", at: moment(2))

        #expect(store.recents.map(\.path) == ["/Users/ahmet/Projects/pinro"])
    }

    @Test func theListIsCappedAndDropsTheOldestEntry() throws {
        let store = makeStore(try makeDefaults())

        for index in 0...RecentFoldersStore.recentLimit {
            store.recordOpen("/Users/ahmet/p\(index)", at: moment(TimeInterval(index)))
        }

        #expect(store.recents.count == RecentFoldersStore.recentLimit)
        #expect(store.recents.first?.path == "/Users/ahmet/p\(RecentFoldersStore.recentLimit)")
        #expect(store.recents.contains { $0.path == "/Users/ahmet/p0" } == false)
    }

    @Test func unusablePathsAreIgnored() throws {
        let store = makeStore(try makeDefaults())

        store.recordOpen("", at: moment(0))
        store.recordOpen("   ", at: moment(1))
        store.recordOpen("Projects/pinro", at: moment(2))

        #expect(store.recents.isEmpty)
    }

    @Test func aRecentEntryCanBeForgotten() throws {
        let store = makeStore(try makeDefaults())
        store.recordOpen("/Users/ahmet/a", at: moment(0))

        store.forgetRecent("~/a")

        #expect(store.recents.isEmpty)
    }

    // MARK: - Favoriler

    /// Favoriler son kullanılanlardan AYRI bir listedir: favoriye almak geçmişi
    /// değiştirmez, geçmişten düşmek favoriyi silmez.
    @Test func favoritesAreASeparateList() throws {
        let store = makeStore(try makeDefaults())
        store.recordOpen("/Users/ahmet/a", at: moment(0))

        store.toggleFavorite("/Users/ahmet/a", at: moment(1))

        #expect(store.favorites.map(\.path) == ["/Users/ahmet/a"])
        #expect(store.recents.map(\.path) == ["/Users/ahmet/a"])

        store.forgetRecent("/Users/ahmet/a")
        #expect(store.favorites.map(\.path) == ["/Users/ahmet/a"])
    }

    @Test func togglingTwiceRemovesTheFavorite() throws {
        let store = makeStore(try makeDefaults())

        #expect(store.toggleFavorite("/Users/ahmet/a", at: moment(0)) == true)
        #expect(store.isFavorite("/Users/ahmet/a"))
        #expect(store.toggleFavorite("~/a", at: moment(1)) == false)
        #expect(store.isFavorite("/Users/ahmet/a") == false)
        #expect(store.favorites.isEmpty)
    }

    @Test func favoritingAFolderTwiceDoesNotDuplicateIt() throws {
        let store = makeStore(try makeDefaults())

        store.addFavorite("/Users/ahmet/a", at: moment(0))
        store.addFavorite("~/a", at: moment(1))

        #expect(store.favorites.count == 1)
    }

    @Test func unusablePathsCannotBeFavorited() throws {
        let store = makeStore(try makeDefaults())

        #expect(store.toggleFavorite("nope/relative", at: moment(0)) == false)
        #expect(store.favorites.isEmpty)
    }

    // MARK: - Kalıcılık

    @Test func bothListsSurviveARestart() throws {
        let defaults = try makeDefaults()
        let store = makeStore(defaults)
        store.recordOpen("/Users/ahmet/a", at: moment(0))
        store.addFavorite("/Users/ahmet/b", at: moment(1))

        let reopened = makeStore(defaults)

        #expect(reopened.recents.map(\.path) == ["/Users/ahmet/a"])
        #expect(reopened.recents.first?.lastOpenedAt == moment(0))
        #expect(reopened.favorites.map(\.path) == ["/Users/ahmet/b"])
    }

    /// İleri uyumluluk: eski/eksik alanlı bir kayıt TÜM listeyi düşürmemeli.
    @Test func aRecordWithoutATimestampStillLoads() throws {
        let defaults = try makeDefaults()
        let json = #"[{"path":"/Users/ahmet/a"}]"#
        defaults.set(Data(json.utf8), forKey: RecentFoldersStore.recentsKey)

        let store = makeStore(defaults)

        #expect(store.recents.map(\.path) == ["/Users/ahmet/a"])
        #expect(store.recents.first?.lastOpenedAt == nil)
    }

    /// Tek bozuk kayıt listeyi silmez; çözülebilenler kalır.
    @Test func oneUndecodableRecordDoesNotWipeTheList() throws {
        let defaults = try makeDefaults()
        let json = #"[{"path":"/Users/ahmet/a"},{"nope":1},{"path":"/Users/ahmet/b"}]"#
        defaults.set(Data(json.utf8), forKey: RecentFoldersStore.recentsKey)

        let store = makeStore(defaults)

        #expect(store.recents.map(\.path) == ["/Users/ahmet/a", "/Users/ahmet/b"])
    }

    @Test func aCorruptBlobIsSetAsideInsteadOfCrashing() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("not json".utf8), forKey: RecentFoldersStore.favoritesKey)

        let store = makeStore(defaults)

        #expect(store.favorites.isEmpty)
        #expect(defaults.data(forKey: RecentFoldersStore.favoritesBackupKey) != nil)
    }

    // MARK: - Silinmiş klasörler
    //
    // KARAR: son kullanılanlar TÜRETİLMİŞ bir geçmiştir — açılamayan bir satır saf gürültü
    // olduğu için listeden DÜŞÜRÜLÜR. Favoriler kullanıcının kendi seçimidir: bağlantısı
    // kesilmiş bir dış diskin klasörü SİLİNMEZ, yalnız erişilemez olduğu sürece listelerde
    // GÖSTERİLMEZ; disk geri geldiğinde favori de geri gelir.

    @Test func missingRecentFoldersAreDropped() throws {
        let store = makeStore(try makeDefaults())
        store.recordOpen("/Users/ahmet/gone", at: moment(0))
        store.recordOpen("/Users/ahmet/here", at: moment(1))

        store.refreshAvailability { $0 == "/Users/ahmet/here" }

        #expect(store.recents.map(\.path) == ["/Users/ahmet/here"])
    }

    @Test func missingFavoritesAreKeptButHidden() throws {
        let defaults = try makeDefaults()
        let store = makeStore(defaults)
        store.addFavorite("/Volumes/backup/pinro", at: moment(0))

        store.refreshAvailability { _ in false }

        #expect(store.favorites.map(\.path) == ["/Volumes/backup/pinro"])
        #expect(store.targets.isEmpty)
        #expect(makeStore(defaults).favorites.map(\.path) == ["/Volumes/backup/pinro"])
    }

    @Test func aFavoriteComesBackWhenItsVolumeReturns() throws {
        let store = makeStore(try makeDefaults())
        store.addFavorite("/Volumes/backup/pinro", at: moment(0))
        store.refreshAvailability { _ in false }

        store.refreshAvailability { _ in true }

        #expect(store.targets.map(\.path) == ["/Volumes/backup/pinro"])
    }

    // MARK: - Palet hedefleri

    @Test func targetsListFavoritesFirstThenRecents() throws {
        let store = makeStore(try makeDefaults())
        store.recordOpen("/Users/ahmet/a", at: moment(0))
        store.recordOpen("/Users/ahmet/b", at: moment(1))
        store.addFavorite("/Users/ahmet/a", at: moment(2))

        #expect(store.targets.map(\.path) == ["/Users/ahmet/a", "/Users/ahmet/b"])
        #expect(store.targets.map(\.kind) == [.favorite, .recent])
    }
}
