import Foundation

extension CommandPaletteCategory {
    /// Kategorinin ait olduğu Pro özelliği; Free kategorilerde `nil`.
    ///
    /// Eşleme BURADA, tek yerde: her komut üreticisinin ayrı ayrı lisans sorması, bir
    /// gün birinin sormayı unutmasıyla biterdi.
    var proFeature: ProFeature? {
        switch self {
        case .workspaces: .workspaces
        case .ssh: .sshManager
        case .docker: .dockerTools
        case .aiActions: .aiAssistant
        // briefs/2: *Temel terminal özellikleri ücret duvarının arkasına konulmamalıdır.*
        // Aşağıdakiler o temel: eylemler, klasörler, kayıtlı komutlar, ayarlar, temalar.
        case .actions, .folders, .savedCommands, .settings, .themes: nil
        }
    }
}

/// Palet satırlarını lisansa göre süzen — daha doğrusu KİLİTLEYEN — katman.
///
/// briefs/2: *Pro özelliklerinde kilitli durum gösterimi (özelliği gizlemek yerine
/// anlatmak).* Bu yüzden satır listeden ÇIKARILMAZ: kilitli ama görünür kalır, ne işe
/// yaradığını anlatır ve tıklanınca lisans sayfasını açar. Gizlenen bir özellik, olmayan
/// bir özellikten ayırt edilemez ve kullanıcı neyi kaçırdığını hiç öğrenemez.
@MainActor
enum ProGate {

    static func apply(_ items: [CommandPaletteItem],
                      license: LicenseStore,
                      openLicenseSettings: @escaping @MainActor () -> Void) -> [CommandPaletteItem] {
        // Lisanslama kurulmamış yapıda hiç dokunma: kurulmamış bir denetim yüzünden
        // özellik kapatmak, var olmayan bir kuralı uygulamak olurdu.
        guard license.isLicensingConfigured else { return items }

        return items.map { item in
            guard let feature = item.category.proFeature, !license.allows(feature) else {
                return item
            }
            return locked(item, feature: feature, openLicenseSettings: openLicenseSettings)
        }
    }

    private static func locked(_ item: CommandPaletteItem,
                               feature: ProFeature,
                               openLicenseSettings: @escaping @MainActor () -> Void) -> CommandPaletteItem {
        CommandPaletteItem(
            // Kimlik AYNI kalır: "son kullanılanlar" listesi kimlikleri saklar ve
            // kilitlenen komut oradan düşmemeli — lisans alınınca yerinde bulunmalı.
            id: item.id,
            title: "\(item.title) (Pro)",
            category: item.category,
            symbolName: "lock.fill",
            // Kısayol GÖSTERİLMEZ: çalışmayacak bir tuş bileşimini vaat etmek yanlış olur.
            shortcut: nil,
            accessibilityLabel: "\(item.title). Pro feature, locked. \(feature.lockedExplanation)",
            action: openLicenseSettings
        )
    }
}
