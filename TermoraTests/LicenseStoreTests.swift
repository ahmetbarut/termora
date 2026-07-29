import CryptoKit
import Foundation
import Testing
@testable import Termora

/// briefs/2 "Lisanslama" ▸ *Lisans anahtarı ... Keychain'de saklama.*
///
/// Testler GERÇEK Keychain'e yazar (kendi servis adlarıyla, arkalarını temizleyerek).
/// Sahte bir depo, bu issue'nun tek güvenlik iddiasını — anahtarın diske düz metin
/// yazılmadığını — hiç sınamazdı.
@MainActor
@Suite("Lisans deposu", .serialized)
struct LicenseStoreTests {

    private let signingKey = Curve25519.Signing.PrivateKey()

    private func makeStore(service: String) -> LicenseStore {
        LicenseStore(keychain: KeychainService(service: service),
                     verifier: LicenseVerifier(publicKey: signingKey.publicKey))
    }

    private func key(expiresAt: Date? = nil) throws -> String {
        try LicenseKeyWriter(signingKey: signingKey)
            .key(License(licensee: "ada@example.com", expiresAt: expiresAt))
    }

    private func service(_ label: String) -> String { "test.license.\(label).\(UUID().uuidString)" }

    @Test func afreshInstallIsFree() {
        let store = makeStore(service: service("fresh"))
        #expect(store.state == .free)
        #expect(store.license == nil)
    }

    @Test func avalidKeyActivatesProAndSurvivesArelaunch() throws {
        let service = service("activate")
        let keychain = KeychainService(service: service)
        defer { try? keychain.removeSecret(account: LicenseState.keychainAccount) }

        let store = makeStore(service: service)
        try store.activate(key())

        #expect(store.state == .pro)
        #expect(store.license?.licensee == "ada@example.com")
        // Anahtar Keychain'de: yeni bir depo onu ağa çıkmadan geri okur.
        #expect(try keychain.secret(account: LicenseState.keychainAccount) != nil)
        #expect(makeStore(service: service).state == .pro)
    }

    /// Geçersiz anahtar SAKLANMAZ: yanlış yapıştırılmış bir metin Keychain'de kalırsa
    /// kullanıcı her açılışta aynı sessiz hatayı taşır.
    @Test func aninvalidKeyIsRejectedAndNotStored() throws {
        let service = service("invalid")
        let keychain = KeychainService(service: service)
        defer { try? keychain.removeSecret(account: LicenseState.keychainAccount) }

        let store = makeStore(service: service)
        #expect(throws: LicenseStore.Failure.invalidKey) { try store.activate("TERMORA-nope.nope") }

        #expect(store.state == .free)
        #expect(try keychain.secret(account: LicenseState.keychainAccount) == nil)
    }

    /// Geçerli bir anahtarı geçersizle DEĞİŞTİRMEK de mevcut lisansı düşürmemeli.
    @Test func abadPasteDoesNotDestroyTheLicenseAlreadyInstalled() throws {
        let service = service("replace")
        let keychain = KeychainService(service: service)
        defer { try? keychain.removeSecret(account: LicenseState.keychainAccount) }

        let store = makeStore(service: service)
        try store.activate(key())
        #expect(throws: LicenseStore.Failure.invalidKey) { try store.activate("garbage") }

        #expect(store.state == .pro)
        #expect(try keychain.secret(account: LicenseState.keychainAccount) != nil)
    }

    @Test func deactivatingRemovesTheKeyFromTheKeychain() throws {
        let service = service("deactivate")
        let keychain = KeychainService(service: service)
        defer { try? keychain.removeSecret(account: LicenseState.keychainAccount) }

        let store = makeStore(service: service)
        try store.activate(key())
        try store.deactivate()

        #expect(store.state == .free)
        #expect(store.license == nil)
        #expect(try keychain.secret(account: LicenseState.keychainAccount) == nil)
    }

    /// Süresi geçmiş anahtar Keychain'de dursa bile Free'ye düşer — ve uygulama
    /// AÇILIR: briefs/2 *İnternet olmadan uygulama açılıp Free olarak kullanılabiliyor.*
    @Test func anexpiredKeyLeavesTheAppUsableAsFree() throws {
        let service = service("expired")
        let keychain = KeychainService(service: service)
        defer { try? keychain.removeSecret(account: LicenseState.keychainAccount) }
        try keychain.setSecret(key(expiresAt: Date(timeIntervalSinceNow: -86_400)),
                               account: LicenseState.keychainAccount)

        let store = makeStore(service: service)

        #expect(store.state == .free)
        for feature in ProFeature.allCases where feature.isFreeTier {
            #expect(store.allows(feature))
        }
    }
}
