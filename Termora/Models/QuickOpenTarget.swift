import Foundation

/// Hızlı açmanın SAF yol mantığı (briefs/2 "Hızlı Açma").
///
/// Son kullanılan klasörler, favoriler, `termora://` şeması ve Finder servisi AYNI
/// normalleştirmeyi kullanır; aksi hâlde `~/Projects/pinro` ile `/Users/ahmet/Projects/pinro/`
/// listede iki ayrı kayıt olurdu.
///
/// Bu tip dosya sistemine DOKUNMAZ. Varlık kontrolü çağırana (ve enjekte edilebilir bir
/// kapanışa) bırakılır: hem testler makineden bağımsız kalır hem de URL ayrıştırıcısı
/// doğrulama sırasını kendisi belirleyebilir.
///
/// `nonisolated`: proje varsayılanı `MainActor` ama burada hiçbir paylaşılan durum yok ve
/// `directoryExistsOnDisk` bir varsayılan parametre değeri olarak aktarılıyor — MainActor'a
/// bağlı kalsaydı bu aktarım Swift 6 dilinde HATA olurdu.
nonisolated enum QuickOpenPath {

    /// Ham bir yolu kanonik mutlak yola çevirir.
    ///
    /// - `~` ve `~/…` verilen ev dizinine genişler; `~kullanıcı` DESTEKLENMEZ (başka bir
    ///   kullanıcının ev dizinini çözmek dizin servisine sorulacak bir iştir).
    /// - Göreli yol REDDEDİLİR: "neye göre?" sorusunun tek bir doğru cevabı yok ve dışarıdan
    ///   gelen göreli bir yol beklenmedik bir klasör açardı.
    /// - `.` atılır, `..` bir üst bileşeni düşürür ve kökün üstüne çıkamaz.
    /// - Tekrar eden ve sondaki eğik çizgiler silinir.
    ///
    /// - Returns: mutlak, kanonik yol; girdi kullanılamazsa `nil`.
    static func normalize(_ raw: String, home: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let expanded: String
        if trimmed == "~" || trimmed.hasPrefix("~/") {
            guard let expandedHome = collapse(home) else { return nil }
            expanded = expandedHome + trimmed.dropFirst()
        } else if trimmed.hasPrefix("~") {
            return nil
        } else {
            expanded = trimmed
        }
        return collapse(expanded)
    }

    /// Yolun kullanıcıya gösterilecek kısa adı: son bileşen, kök için `/`.
    static func displayName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? "/"
    }

    /// Üretimdeki varsayılan varlık kontrolü. Yalnız KLASÖRLER kabul edilir: hızlı açma
    /// bir dosyanın içinde shell başlatamaz.
    static func directoryExistsOnDisk(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    /// Mutlak bir yoldan `.`/`..`/boş bileşenleri temizler. Mutlak değilse `nil`.
    private static func collapse(_ absolutePath: String) -> String? {
        guard absolutePath.hasPrefix("/") else { return nil }
        var components: [Substring] = []
        for piece in absolutePath.split(separator: "/", omittingEmptySubsequences: true) {
            switch piece {
            case ".":
                continue
            case "..":
                // Kökün üstü yoktur: `/../..` de `/` demektir (POSIX ile aynı davranış).
                if !components.isEmpty { components.removeLast() }
            default:
                components.append(piece)
            }
        }
        return "/" + components.joined(separator: "/")
    }
}

/// Kalıcı bir klasör kaydı (son kullanılan ya da favori).
///
/// `path` her zaman `QuickOpenPath.normalize` çıktısıdır; kimlik odur.
struct QuickOpenFolder: Codable, Equatable, Hashable, Identifiable {
    var path: String
    /// Son açılma / favoriye alınma anı. Yalnız bilgi amaçlıdır: sıra listenin KENDİSİDİR.
    var lastOpenedAt: Date?

    var id: String { path }

    init(path: String, lastOpenedAt: Date? = nil) {
        self.path = path
        self.lastOpenedAt = lastOpenedAt
    }

    private enum CodingKeys: String, CodingKey {
        case path, lastOpenedAt
    }
}

// MARK: - İleri uyumlu çözme
//
// Sentezlenmiş `init(from:)` özellik varsayılanlarını YOK SAYAR ve eksik alanda
// `keyNotFound` fırlatır; modele eklenen tek bir alan kullanıcının diskteki tüm
// klasör listesini bozuk yapardı (bkz. Termora/Models/Workspace.swift).

extension QuickOpenFolder {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Yol UYDURULMAZ: yolu olmayan bir kayıt hiçbir şeyi açamaz, çağıran onu atlar.
        path = try container.decode(String.self, forKey: .path)
        lastOpenedAt = try container.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
    }
}

/// Komut paletinin "Folders" kategorisinde çizilen tek satır.
struct QuickOpenTarget: Equatable, Hashable, Identifiable {

    enum Kind: String, Equatable, Hashable, Sendable {
        case favorite
        case recent
    }

    let path: String
    let kind: Kind

    /// Palet kimliği kalıcı "son kullanılan komutlar" listesinde saklanır: yola bağlı ve
    /// KARARLI olmalı. Favori/son kullanılan ayrımı kimliğe GİRMEZ — aynı klasör favoriye
    /// alındığında geçmişteki komut kaydı kopmamalı.
    var id: String { "folder.\(path)" }

    /// Satır başlığı kısaltılmış YOLDUR (yalnız klasör adı değil): aynı adlı iki klasör
    /// ayırt edilebilsin ve fuzzy arama yol parçalarıyla da eşleşsin diye.
    func title(home: String) -> String {
        PathDisplay.abbreviate(path, home: home)
    }

    /// Durum yalnız renkle anlatılmaz: favori ve son kullanılan satırların İKONU farklıdır.
    var symbolName: String {
        switch kind {
        case .favorite: return "star.fill"
        case .recent: return "clock"
        }
    }

    func accessibilityLabel(home: String) -> String {
        switch kind {
        case .favorite: return "Favorite folder \(title(home: home))"
        case .recent: return "Recent folder \(title(home: home))"
        }
    }

    /// Favoriler önce, sonra favoride OLMAYAN son kullanılanlar.
    /// Her yol TEK satır üretir: palet satır kimlikleri benzersiz olmak zorunda.
    static func merged(favorites: [QuickOpenFolder],
                       recents: [QuickOpenFolder]) -> [QuickOpenTarget] {
        var seen: Set<String> = []
        var targets: [QuickOpenTarget] = []
        for folder in favorites {
            guard seen.insert(folder.path).inserted else { continue }
            targets.append(QuickOpenTarget(path: folder.path, kind: .favorite))
        }
        for folder in recents {
            guard seen.insert(folder.path).inserted else { continue }
            targets.append(QuickOpenTarget(path: folder.path, kind: .recent))
        }
        return targets
    }
}

/// Bir klasörü yeni sekmede açmak için `WorkspaceViewModel.newTab(profile:)`e verilecek
/// geçici profil (aynı kalıp: `SSHLaunch.profile(for:)`).
enum QuickOpenLaunch {

    /// GÜVENLİK: bu profilde `startupCommand` HİÇBİR ZAMAN yoktur. Hızlı açmanın tek
    /// yeteneği kabuğu o dizinde başlatmaktır; dizin `startProcess(currentDirectory:)`e
    /// verilir, bir kabuk satırına gömülmez — yani yol adı komut olarak yorumlanamaz.
    static func profile(forFolder path: String) -> TerminalProfile {
        TerminalProfile(name: QuickOpenPath.displayName(path), startupDirectory: path)
    }
}
