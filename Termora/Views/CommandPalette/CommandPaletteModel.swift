import AppKit
import Foundation
import Observation

/// Komut paletinin durumu: açık mı, ne yazıldı, hangi satır seçili, en son ne çalıştırıldı.
///
/// Palet terminalin ÜZERİNDE bir katman olarak çizilir; hiçbir oturumu duraklatmaz
/// (brief 3: "Komut paleti açıldığında terminal oturumu durmamalıdır"). Bu tip yalnız
/// durum tutar, terminale dokunmaz.
@MainActor
@Observable
final class CommandPaletteModel {

    /// Son kullanılanlar listesinin uzunluğu.
    static let recentLimit = 8
    static let storageKey = "commandPalette.recentIDs.v1"

    private(set) var isPresented = false
    var query = ""
    private(set) var selectedIndex = 0
    private(set) var recentIDs: [String] = []

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recentIDs = defaults.stringArray(forKey: Self.storageKey) ?? []
    }

    // MARK: - Açılma / kapanma

    /// Palet her açılışta boş sorgu ve ilk satır seçili olarak gelir.
    func present() {
        query = ""
        selectedIndex = 0
        isPresented = true
    }

    func dismiss() {
        isPresented = false
    }

    /// Belirli bir kategoriyi arayarak açar (briefs/3 "Yeni Sekme Ekranı" yolları).
    ///
    /// Launcher kendi workspace/SSH/klasör listesini ÇİZMEZ: aynı kaydı iki ayrı yerde
    /// bakımı gereken iki listeye bölmek yerine paletin arama ve önizleme yüzeyini
    /// kullanır.
    func open(category: CommandPaletteCategory) {
        query = category.title
        isPresented = true
    }

    func toggle() {
        if isPresented { dismiss() } else { present() }
    }

    // MARK: - Klavye gezinmesi

    /// ↑/↓ hareketi. Uçlarda durur (başa/sona sarmaz).
    func moveSelection(by delta: Int, resultCount: Int) {
        guard resultCount > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(max(selectedIndex + delta, 0), resultCount - 1)
    }

    /// Sonuç listesi kısaldığında seçimi geçerli aralığa çeker.
    func clampSelection(resultCount: Int) {
        guard resultCount > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(selectedIndex, resultCount - 1)
    }

    // MARK: - Çalıştırma

    /// Seçili komutu çalıştırır. Palet ÖNCE kapanır: komut bir pencere açıyorsa
    /// (örn. Ayarlar) paletin katmanı odağı çalmasın.
    func run(_ result: CommandPaletteResult) {
        markUsed(id: result.item.id)
        dismiss()
        result.item.action()
    }

    func markUsed(id: String) {
        var updated = recentIDs.filter { $0 != id }
        updated.insert(id, at: 0)
        recentIDs = Array(updated.prefix(Self.recentLimit))
        defaults.set(recentIDs, forKey: Self.storageKey)
    }
}

/// ⌘⇧P alternatif kısayolunun saf tanımı (⌘K menüden gelir).
///
/// Menü öğesine yalnız BİR kısayol bağlanabildiği için ikinci kısayol pencereye özel bir
/// olay dinleyicisiyle yakalanır; karar mantığı test edilebilsin diye burada durur.
enum CommandPaletteHotkey {

    static func isAlternateShortcut(characters: String?,
                                    modifiers: NSEvent.ModifierFlags) -> Bool {
        guard let characters, characters.lowercased() == "p" else { return false }
        // capsLock/function gibi bayraklar sistem tarafından eklenebilir; kararı bozmamalı.
        let relevant = modifiers.intersection([.command, .shift, .option, .control])
        return relevant == [.command, .shift]
    }
}
