import Foundation
import Observation
import os

/// Son kullanılan ve favori klasörler (briefs/2 "Hızlı Açma").
///
/// "Son kullanılan" = kullanıcının AÇTIĞI klasör: workspace açma, palet üzerinden klasörden
/// sekme açma, `termora://open` ve Finder servisi. Oturum içinde `cd` yapmak ya da yeni bir
/// kabuğun bir dizinde başlaması bu listeye YAZMAZ — liste kullanıcının niyetini saklar,
/// kabuğun gezintisini değil.
///
/// Kalıcılık `SSHHostStore` / `WorkspaceStore` ile aynı kalıptır: UserDefaults'a JSON blob,
/// her mutasyonda `didSet` üzerinden yazma, öğe öğe çözme (tek bozuk kayıt listeyi silmez),
/// blob bozuksa yedek anahtara taşıma.
@MainActor
@Observable
final class RecentFoldersStore {

    static let recentsKey = "quickOpen.recentFolders.v1"
    static let favoritesKey = "quickOpen.favoriteFolders.v1"
    static let recentsBackupKey = "quickOpen.recentFolders.v1.corrupt-backup"
    static let favoritesBackupKey = "quickOpen.favoriteFolders.v1.corrupt-backup"

    /// Listenin üst sınırı. Palet zaten fuzzy arama sunuyor; daha uzun bir geçmiş
    /// "son kullanılan" olmaktan çıkıp aranması gereken ikinci bir listeye dönüşür.
    static let recentLimit = 20

    private static let logger = Logger(subsystem: "com.ahmetbarut.Termora",
                                       category: "RecentFoldersStore")

    /// En yeni üstte.
    private(set) var recents: [QuickOpenFolder] = [] {
        didSet { persist(recents, key: Self.recentsKey) }
    }

    /// Kullanıcının yıldızladığı klasörler; son kullanılanlardan AYRI liste.
    private(set) var favorites: [QuickOpenFolder] = [] {
        didSet { persist(favorites, key: Self.favoritesKey) }
    }

    /// Şu an diskte bulunamayan favoriler. KALICI DEĞİLDİR: bağlantısı kesilmiş bir dış
    /// diskin klasörü kullanıcının favorisi olmaktan çıkmaz, yalnız gösterilmez.
    private(set) var unavailableFavoritePaths: Set<String> = []

    private let defaults: UserDefaults
    private let home: String

    init(defaults: UserDefaults = .standard, home: String = NSHomeDirectory()) {
        self.defaults = defaults
        self.home = home
        self.recents = Self.load(key: Self.recentsKey,
                                 backupKey: Self.recentsBackupKey,
                                 defaults: defaults)
        self.favorites = Self.load(key: Self.favoritesKey,
                                   backupKey: Self.favoritesBackupKey,
                                   defaults: defaults)
    }

    // MARK: - Son kullanılanlar

    /// Kullanıcı bir klasörü açtı. Kayıt varsa yukarı TAŞINIR (kopyalanmaz), liste
    /// `recentLimit` uzunluğunda kalır ve en eski kayıt düşer.
    ///
    /// - Parameter date: testte sabitlenebilsin diye dışarıdan verilir.
    func recordOpen(_ rawPath: String, at date: Date) {
        guard let path = QuickOpenPath.normalize(rawPath, home: home) else { return }
        var updated = recents.filter { $0.path != path }
        updated.insert(QuickOpenFolder(path: path, lastOpenedAt: date), at: 0)
        recents = Array(updated.prefix(Self.recentLimit))
    }

    func forgetRecent(_ rawPath: String) {
        guard let path = QuickOpenPath.normalize(rawPath, home: home) else { return }
        recents.removeAll { $0.path == path }
    }

    func clearRecents() {
        guard !recents.isEmpty else { return }
        recents = []
    }

    // MARK: - Favoriler

    func isFavorite(_ rawPath: String) -> Bool {
        guard let path = QuickOpenPath.normalize(rawPath, home: home) else { return false }
        return favorites.contains { $0.path == path }
    }

    func addFavorite(_ rawPath: String, at date: Date) {
        guard let path = QuickOpenPath.normalize(rawPath, home: home),
              !favorites.contains(where: { $0.path == path }) else { return }
        favorites.append(QuickOpenFolder(path: path, lastOpenedAt: date))
    }

    func removeFavorite(_ rawPath: String) {
        guard let path = QuickOpenPath.normalize(rawPath, home: home) else { return }
        favorites.removeAll { $0.path == path }
        unavailableFavoritePaths.remove(path)
    }

    /// - Returns: işlemden SONRA klasör favori mi?
    @discardableResult
    func toggleFavorite(_ rawPath: String, at date: Date) -> Bool {
        guard let path = QuickOpenPath.normalize(rawPath, home: home) else { return false }
        if favorites.contains(where: { $0.path == path }) {
            removeFavorite(path)
            return false
        }
        addFavorite(path, at: date)
        return true
    }

    // MARK: - Silinmiş klasörler
    //
    // KARAR (briefs/2: "silinmiş klasör listede kalmasın ya da açıkça işaretlensin"):
    //
    // * Son kullanılanlar TÜRETİLMİŞ bir geçmiştir. Açılamayan bir satır saf gürültüdür ve
    //   listeden DÜŞÜRÜLÜR.
    // * Favoriler kullanıcının kendi seçimidir. Bağlantısı kesilmiş bir dış diskin klasörü
    //   SİLİNMEZ — yalnız erişilemez olduğu sürece listelerde gösterilmez. Disk geri
    //   geldiğinde favori de geri gelir. Böylece palet hiçbir zaman açılamayan bir satır
    //   çizmez, ama kullanıcının işareti de bir kablo çıktı diye kaybolmaz.

    /// Diskten okur; bu yüzden çizim döngüsünde DEĞİL, paletin `onAppear`'ında çağrılır.
    func refreshAvailability(directoryExists: (String) -> Bool = QuickOpenPath.directoryExistsOnDisk) {
        let survivors = recents.filter { directoryExists($0.path) }
        if survivors.count != recents.count { recents = survivors }

        let missing = Set(favorites.map(\.path).filter { !directoryExists($0) })
        if missing != unavailableFavoritePaths { unavailableFavoritePaths = missing }
    }

    // MARK: - Palet hedefleri

    /// Komut paletinin "Folders" kategorisinde çizilecek satırlar: önce (erişilebilir)
    /// favoriler, sonra son kullanılanlar. Aynı klasör tek satır üretir.
    var targets: [QuickOpenTarget] {
        QuickOpenTarget.merged(
            favorites: favorites.filter { !unavailableFavoritePaths.contains($0.path) },
            recents: recents)
    }

    // MARK: - Kalıcılık

    private func persist(_ folders: [QuickOpenFolder], key: String) {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load(key: String,
                             backupKey: String,
                             defaults: UserDefaults) -> [QuickOpenFolder] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            // Öğe öğe: tek bozuk kayıt bütün listeyi silmemeli. Blob'a DOKUNULMAZ —
            // atlanan kaydın ham verisi bir sonraki yazmaya kadar diskte kalsın.
            let decoded = try JSONDecoder().decode(LenientArray<QuickOpenFolder>.self, from: data)
            if !decoded.failures.isEmpty {
                logger.error("""
                    Skipped \(decoded.failures.count, privacy: .public) undecodable folder(s) in \
                    \(key, privacy: .public), kept \(decoded.elements.count, privacy: .public): \
                    \(decoded.failureSummary, privacy: .public)
                    """)
            }
            return decoded.elements
        } catch {
            defaults.set(data, forKey: backupKey)
            defaults.removeObject(forKey: key)
            logger.error("Corrupt folder blob moved to \(backupKey, privacy: .public); falling back to empty list")
            return []
        }
    }
}
