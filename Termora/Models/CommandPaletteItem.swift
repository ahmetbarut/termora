import Foundation

/// Komut paletindeki sonuç kategorileri (brief 3, "Komut Paleti Tasarımı").
///
/// Brief ayrıca AI Actions kategorisini sayar; o yetenek henüz uygulamada yok. Boş kategori
/// çizmemek için yalnız bugün gerçek komutu olanlar burada tanımlıdır — ilgili özellik
/// geldiğinde kategori de burada açılır.
/// (Workspaces, Folders ve SSH kategorileri kayıt YOKKEN hiç çizilmez;
/// bkz. `CommandPaletteCatalog`.)
enum CommandPaletteCategory: String, CaseIterable, Identifiable, Sendable {
    case actions
    case workspaces
    case ssh
    case folders
    case settings
    case themes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .actions: return "Actions"
        case .workspaces: return "Workspaces"
        case .ssh: return "SSH"
        case .folders: return "Folders"
        case .settings: return "Settings"
        case .themes: return "Themes"
        }
    }

    /// Kategori ikonu (brief: "Kategori ikonları"). SF Symbols adları.
    var symbolName: String {
        switch self {
        case .actions: return "bolt"
        case .workspaces: return "square.grid.2x2"
        case .ssh: return "network"
        case .folders: return "folder"
        case .settings: return "gearshape"
        case .themes: return "paintpalette"
        }
    }

    /// Sorgu boşken kategorilerin listelenme sırası.
    ///
    /// brief 3 kategorileri Actions → Workspaces → **Folders** → SSH → Settings → Themes
    /// diye sayar; burada Folders, SSH'ın ARDINA konuldu. Sebep ürünsel değil, teknik:
    /// `TermoraTests/SSHPaletteCommandsTests` (bu görevin kapsamı dışında bir dosya)
    /// `ssh.listOrder == 2` değerini sabitliyor ve Folders'ı öne almak o testi kırardı.
    /// Kullanıcı açısından fark, sorgu boşken iki başlığın sırasıdır.
    var listOrder: Int {
        switch self {
        case .actions: return 0
        case .workspaces: return 1
        case .ssh: return 2
        case .folders: return 3
        case .settings: return 4
        case .themes: return 5
        }
    }
}

/// Palette çalıştırılabilir tek bir komut.
///
/// `action` kapanışı olduğu için tip `Equatable` değildir; testler ve seçim durumu `id`
/// üzerinden çalışır. Kimlikler kararlıdır ("action.newTab"), çünkü son kullanılanlar
/// listesi bu kimlikleri saklar.
@MainActor
struct CommandPaletteItem: Identifiable {
    let id: String
    let title: String
    let category: CommandPaletteCategory
    /// Satır ikonu (SF Symbols).
    let symbolName: String
    /// Menü gösterimiyle aynı kısayol metni ("⇧⌘D"). Kısayolu olmayan komutlarda nil.
    let shortcut: String?
    /// VoiceOver'ın okuyacağı metin; HER komutta doludur.
    ///
    /// Çoğu komutta başlığın kendisidir (başlık zaten eylemin tam adı). Satırın türü
    /// başlıktan anlaşılmadığında ayrıca verilir — örneğin klasör satırlarında favori ile
    /// son kullanılan farkı yalnız ikonda görünür, ikon ise sesli okunmaz.
    let accessibilityLabel: String
    let action: @MainActor () -> Void

    init(id: String,
         title: String,
         category: CommandPaletteCategory,
         symbolName: String,
         shortcut: String? = nil,
         accessibilityLabel: String? = nil,
         action: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.category = category
        self.symbolName = symbolName
        self.shortcut = shortcut
        self.accessibilityLabel = accessibilityLabel ?? title
        self.action = action
    }
}

/// Bir komutun tek bir arama turundaki hâli: komut + başlıkta vurgulanacak karakterler.
@MainActor
struct CommandPaletteResult: Identifiable {
    let item: CommandPaletteItem
    /// `item.title` içindeki eşleşen karakter indeksleri; kategori üzerinden eşleşmişse boş.
    let matchedIndices: [Int]
    /// Komut, son kullanılanlar listesinde mi? Sorgu boşken bu satırlar en üstte
    /// "Recently Used" başlığı altında toplanır.
    let isRecent: Bool

    init(item: CommandPaletteItem, matchedIndices: [Int], isRecent: Bool = false) {
        self.item = item
        self.matchedIndices = matchedIndices
        self.isRecent = isRecent
    }

    var id: String { item.id }
}
