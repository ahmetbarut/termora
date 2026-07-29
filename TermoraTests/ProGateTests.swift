import CryptoKit
import Foundation
import Testing
@testable import Termora

/// briefs/2 "Lisanslama" ▸ *Pro özelliklerinde kilitli durum gösterimi (özelliği gizlemek
/// yerine anlatmak).*
///
/// Kilit paletin ÜSTÜNE konur, kataloğun içine değil: her komut üreticisinin ayrı ayrı
/// lisans sorması, bir gün birinin sormayı unutması demekti.
@MainActor
@Suite("Pro kilidi")
struct ProGateTests {

    private let signingKey = Curve25519.Signing.PrivateKey()

    /// Lisans denetimi AÇIK ama lisans yok.
    private var gatedStore: LicenseStore {
        LicenseStore(keychain: KeychainService(service: "test.gate.\(UUID().uuidString)"),
                     verifier: LicenseVerifier(publicKey: signingKey.publicKey))
    }

    /// Açık anahtarı olmayan yapı: lisanslama kurulmamış.
    private var unconfiguredStore: LicenseStore {
        LicenseStore(keychain: KeychainService(service: "test.gate.\(UUID().uuidString)"),
                     verifier: LicenseVerifier(publicKey: nil))
    }

    private func item(_ category: CommandPaletteCategory,
                      ran: @escaping @MainActor () -> Void = {}) -> CommandPaletteItem {
        CommandPaletteItem(id: "\(category.rawValue).sample",
                           title: "Sample",
                           category: category,
                           symbolName: "circle",
                           action: ran)
    }

    private func gate(_ items: [CommandPaletteItem],
                      license: LicenseStore,
                      openSettings: @escaping @MainActor () -> Void = {}) -> [CommandPaletteItem] {
        ProGate.apply(items, license: license, openLicenseSettings: openSettings)
    }

    /// Bu yapıda açık anahtar yok — lisanslama HİÇ kurulmamış. O hâlde kilit de yok:
    /// kurulmamış bir denetim yüzünden özellik kapatmak, kullanıcının parası karşılığı
    /// aldığı bir şeyi değil, hiç var olmamış bir kuralı uygulamak olurdu.
    @Test func abuildWithoutLicensingLocksNothing() {
        let store = unconfiguredStore
        #expect(store.isLicensingConfigured == false)

        for category in CommandPaletteCategory.allCases {
            let gated = gate([item(category)], license: store)
            #expect(gated[0].title == "Sample", "\(category) kilitlenmemeliydi")
        }
    }

    /// Denetim açık ve lisans yoksa Pro kategorileri kilitlenir.
    @Test func proCategoriesAreLockedWithoutAlicense() {
        let store = gatedStore
        #expect(store.isLicensingConfigured)

        for category in [CommandPaletteCategory.workspaces, .ssh, .docker, .aiActions] {
            let gated = gate([item(category)], license: store)
            #expect(gated[0].title.contains("Pro"), "\(category) kilitli görünmeliydi")
            #expect(gated[0].symbolName == "lock.fill")
        }
    }

    /// briefs/2'nin en bağlayıcı cümlesi: *Temel terminal özellikleri ücret duvarının
    /// arkasına konulmamalıdır.* Free kategoriler lisans denetimi açıkken bile serbest.
    @Test func freeCategoriesAreNeverLocked() {
        let store = gatedStore
        for category in [CommandPaletteCategory.actions, .folders, .savedCommands,
                         .settings, .themes] {
            let gated = gate([item(category)], license: store)
            #expect(gated[0].title == "Sample", "\(category) ücret duvarına konulamaz")
        }
    }

    /// Kilitli satır GİZLENMEZ ve kimliği DEĞİŞMEZ: "son kullanılanlar" listesi
    /// kimlikleri saklar, kilitlenen komut oradan düşmemeli.
    @Test func alockedRowKeepsItsPlaceAndItsIdentity() {
        let gated = gate([item(.workspaces), item(.actions)], license: gatedStore)
        #expect(gated.count == 2)
        #expect(gated[0].id == "workspaces.sample")
        #expect(gated[1].id == "actions.sample")
    }

    /// Kilitli satır kendi eylemini ÇALIŞTIRMAZ; lisans sayfasını açar.
    @Test func alockedRowOpensTheLicensePageInsteadOfRunning() {
        var didRun = false
        var didOpenSettings = false
        let gated = gate([item(.ssh) { didRun = true }],
                         license: gatedStore,
                         openSettings: { didOpenSettings = true })

        gated[0].action()

        #expect(didRun == false)
        #expect(didOpenSettings)
    }

    /// Satır neden kilitli olduğunu SÖYLER — VoiceOver kullanıcısı yalnız bir kilit
    /// ikonu duymaz.
    @Test func alockedRowSaysWhyItIsLocked() {
        let gated = gate([item(.docker)], license: gatedStore)
        let label = gated[0].accessibilityLabel.lowercased()
        #expect(label.contains("pro"))
        #expect(label.contains(ProFeature.dockerTools.lockedExplanation.lowercased()))
    }

    /// Lisans etkinleştirilince kilit kalkar.
    @Test func alicenseUnlocksEverything() throws {
        let store = gatedStore
        let key = try LicenseKeyWriter(signingKey: signingKey)
            .key(License(licensee: "ada@example.com", expiresAt: nil))
        try store.activate(key)
        defer { try? store.deactivate() }

        for category in CommandPaletteCategory.allCases {
            #expect(gate([item(category)], license: store)[0].title == "Sample")
        }
    }

    /// Kategori → özellik eşlemesi brief'in Pro listesiyle aynı olmalı.
    @Test func everyProCategoryNamesTheFeatureItBelongsTo() {
        #expect(CommandPaletteCategory.workspaces.proFeature == .workspaces)
        #expect(CommandPaletteCategory.ssh.proFeature == .sshManager)
        #expect(CommandPaletteCategory.docker.proFeature == .dockerTools)
        #expect(CommandPaletteCategory.aiActions.proFeature == .aiAssistant)
        #expect(CommandPaletteCategory.actions.proFeature == nil)
    }
}
