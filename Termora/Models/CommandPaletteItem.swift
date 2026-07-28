import Foundation

/// Komut paletindeki sonuç kategorileri (brief 3, "Komut Paleti Tasarımı").
///
/// Brief ayrıca Workspaces, Folders, SSH ve AI Actions kategorilerini sayar; bu yetenekler
/// henüz uygulamada yok. Boş kategori çizmemek için yalnız bugün gerçek komutu olanlar
/// burada tanımlıdır — ilgili özellikler geldiğinde kategori de burada açılır.
enum CommandPaletteCategory: String, CaseIterable, Identifiable, Sendable {
    case actions
    case settings
    case themes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .actions: return "Actions"
        case .settings: return "Settings"
        case .themes: return "Themes"
        }
    }

    /// Kategori ikonu (brief: "Kategori ikonları"). SF Symbols adları.
    var symbolName: String {
        switch self {
        case .actions: return "bolt"
        case .settings: return "gearshape"
        case .themes: return "paintpalette"
        }
    }

    /// Sorgu boşken kategorilerin listelenme sırası.
    var listOrder: Int {
        switch self {
        case .actions: return 0
        case .settings: return 1
        case .themes: return 2
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
    let action: @MainActor () -> Void

    init(id: String,
         title: String,
         category: CommandPaletteCategory,
         symbolName: String,
         shortcut: String? = nil,
         action: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.category = category
        self.symbolName = symbolName
        self.shortcut = shortcut
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
