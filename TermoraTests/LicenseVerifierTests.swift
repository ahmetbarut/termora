import CryptoKit
import Foundation
import Testing
@testable import Termora

/// briefs/2 "Lisanslama": *Lisans anahtarı doğrulama* ve *doğrulama internet bağlantısına
/// bağımlı kalmasın.*
///
/// Doğrulama imzayla yapılır: anahtar, satıcının özel anahtarıyla imzalanmış küçük bir
/// yükü taşır ve uygulama içindeki AÇIK anahtarla yerinde doğrulanır. Ağa çıkılmaz —
/// terminal uygulaması tam olarak ağın olmadığı yerlerde kullanılır.
@Suite("Lisans doğrulama")
struct LicenseVerifierTests {

    /// Testin kendi anahtar çifti: özel anahtar depoda DURMAZ, her koşuda üretilir.
    private let signingKey = Curve25519.Signing.PrivateKey()

    private var verifier: LicenseVerifier { LicenseVerifier(publicKey: signingKey.publicKey) }

    private func key(licensee: String = "ada@example.com",
                     expiresAt: Date? = nil,
                     signedBy signer: Curve25519.Signing.PrivateKey? = nil) throws -> String {
        try LicenseKeyWriter(signingKey: signer ?? signingKey)
            .key(License(licensee: licensee, expiresAt: expiresAt))
    }

    @Test func avalidKeyUnlocksPro() throws {
        let license = try #require(verifier.license(from: key(), now: .now))
        #expect(license.licensee == "ada@example.com")
        #expect(LicenseState(license: license) == .pro)
    }

    /// Yükü kurcalamak imzayı bozar.
    @Test func atamperedKeyIsRejected() throws {
        var text = try key()
        // Yükün son karakterini değiştir: imza artık tutmaz.
        let index = text.index(text.startIndex, offsetBy: text.count / 2)
        text.replaceSubrange(index...index, with: text[index] == "A" ? "B" : "A")

        #expect(verifier.license(from: text, now: .now) == nil)
    }

    /// Başkasının imzaladığı anahtar geçmez — aksi hâlde herkes kendi lisansını basardı.
    @Test func akeySignedByAnotherKeypairIsRejected() throws {
        let stranger = Curve25519.Signing.PrivateKey()
        #expect(verifier.license(from: try key(signedBy: stranger), now: .now) == nil)
    }

    @Test func garbageIsRejectedWithoutCrashing() {
        for text in ["", "TERMORA", "TERMORA-...", "hello world", "TERMORA-abc.def"] {
            #expect(verifier.license(from: text, now: .now) == nil)
        }
    }

    /// briefs/2: *abonelik yerine tek seferlik lisans veya yıllık güncelleme modeli.*
    /// Süresiz anahtarda bitiş yoktur ve hiçbir tarihte düşmez.
    @Test func aperpetualKeyNeverExpires() throws {
        let distantFuture = Date(timeIntervalSinceNow: 60 * 60 * 24 * 365 * 50)
        #expect(verifier.license(from: try key(expiresAt: nil), now: distantFuture) != nil)
    }

    @Test func anexpiredKeyFallsBackToFree() throws {
        let yesterday = Date(timeIntervalSinceNow: -86_400)
        #expect(verifier.license(from: try key(expiresAt: yesterday), now: .now) == nil)
    }

    /// Açık anahtar yoksa doğrulama BAŞARISIZ kapanır: imzasız bir yapıda her anahtar
    /// geçerli sayılsaydı lisans denetimi hiç olmamış gibi olurdu.
    @Test func withoutApublicKeyEverythingStaysFree() throws {
        #expect(LicenseVerifier(publicKey: nil).license(from: try key(), now: .now) == nil)
    }

    /// Saat geriye alınarak süresi geçmiş anahtar diriltilemesin diye bitiş tarihi
    /// yükün İÇİNDE ve imzalı: kullanıcı tarihi değiştirebilir ama imzayı değiştiremez.
    @Test func theExpiryDateIsPartOfTheSignedPayload() throws {
        let text = try key(expiresAt: Date(timeIntervalSince1970: 1_800_000_000))
        let license = try #require(verifier.license(from: text, now: Date(timeIntervalSince1970: 1)))
        #expect(license.expiresAt == Date(timeIntervalSince1970: 1_800_000_000))
    }
}
