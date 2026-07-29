import Foundation
import Testing
@testable import Termora

/// briefs/2 "Lisanslama ve Planlar".
///
/// Brief'in en bağlayıcı cümlesi: *Temel terminal özellikleri ücret duvarının arkasına
/// konulmamalıdır. Kullanıcı uygulamayı ücretsiz olarak gerçek anlamda kullanabilmelidir.*
/// İlk test o cümledir.
@MainActor
@Suite("Lisanslama")
struct LicenseTests {

    @Test func everyFreeFeatureWorksWithoutALicense() {
        let free = LicenseState.free
        for feature in ProFeature.allCases where feature.isFreeTier {
            #expect(free.allows(feature), "\(feature) ücretsiz olmalı")
        }
    }

    /// briefs/2'nin Free listesi: sınırsız yerel terminal, sekmeler, split, temalar,
    /// arama, temel profiller. Bunlar KİLİTLENEMEZ.
    @Test func theFreeTierIsExactlyWhatTheBriefLists() {
        let freeFeatures = ProFeature.allCases.filter(\.isFreeTier).map(\.title)
        #expect(freeFeatures == [
            "Local terminals", "Tabs", "Split terminals", "Themes", "Search", "Profiles",
        ])
    }

    /// Pro listesi de brief'in listesi.
    @Test func theProTierIsExactlyWhatTheBriefLists() {
        let proFeatures = ProFeature.allCases.filter { !$0.isFreeTier }.map(\.title)
        #expect(proFeatures == [
            "Workspaces", "SSH manager", "AI assistant", "Docker tools",
            "Command blocks", "Session restore",
        ])
    }

    @Test func aProFeatureIsLockedWithoutALicenseAndOpenWithOne() {
        #expect(LicenseState.free.allows(.workspaces) == false)
        #expect(LicenseState.pro.allows(.workspaces))
    }

    /// Kilitli özellik GİZLENMEZ, kilitli görünür — kullanıcı neyi kaçırdığını
    /// bilmeli (briefs/3 "Sağ Tık Menüleri" ile aynı kural).
    @Test func alockedFeatureExplainsItselfInsteadOfDisappearing() {
        for feature in ProFeature.allCases where !feature.isFreeTier {
            #expect(!feature.lockedExplanation.isEmpty)
        }
    }

    /// briefs/1 "Güvenlik": lisans anahtarı UserDefaults'ta DEĞİL Keychain'de.
    @Test func theLicenseKeyLivesInTheKeychain() {
        #expect(LicenseState.keychainAccount.isEmpty == false)
        // Ayarlarda anahtar için alan YOK: sızmanın yapısal olarak yolu kapalı.
        let mirror = Mirror(reflecting: AppSettings())
        let fields = Set(mirror.children.compactMap(\.label))
        for forbidden in ["licenseKey", "license", "proKey"] {
            #expect(fields.contains(forbidden) == false)
        }
    }

    /// briefs/2: *İlk sürümde abonelik yerine tek seferlik lisans veya yıllık güncelleme
    /// modeli değerlendirilebilir.* Doğrulama internet bağlantısına bağlı OLMAMALI:
    /// çevrimdışı bir kullanıcı kendi satın aldığı özelliği kaybetmemeli.
    @Test func averificationNeverNeedsTheNetwork() {
        #expect(LicenseState.verificationIsOffline)
    }
}
