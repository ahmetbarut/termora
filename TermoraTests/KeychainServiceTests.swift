import Foundation
import Testing
@testable import Termora

/// briefs/1 "Güvenlik": *API anahtarları ve parolalar UserDefaults içinde tutulmamalı;
/// hassas bilgiler Keychain'de saklanmalı.*
///
/// Testler GERÇEK Keychain'e yazar — sahte bir depo, "anahtar gerçekten Keychain'e
/// gitti mi" sorusunu yanıtlamaz ve bu issue'nun tek güvenlik iddiası tam olarak bu.
/// Her test kendi hesap adını kullanır ve arkasını temizler.
@Suite("Keychain", .serialized)
struct KeychainServiceTests {

    private func makeAccount(_ label: String) -> String {
        "test.\(label).\(UUID().uuidString)"
    }

    @Test func aStoredSecretComesBackVerbatim() throws {
        let keychain = KeychainService()
        let account = makeAccount("roundtrip")
        defer { try? keychain.removeSecret(account: account) }

        try keychain.setSecret("sk-ant-api03-abc123", account: account)

        #expect(try keychain.secret(account: account) == "sk-ant-api03-abc123")
    }

    @Test func anUnknownAccountHasNoSecret() throws {
        let keychain = KeychainService()
        #expect(try keychain.secret(account: makeAccount("missing")) == nil)
    }

    /// İkinci kayıt hata vermez, üstüne yazar. Kullanıcı anahtarını değiştirdiğinde
    /// önce silmesi gerekmemeli.
    @Test func writingTwiceReplacesTheSecret() throws {
        let keychain = KeychainService()
        let account = makeAccount("replace")
        defer { try? keychain.removeSecret(account: account) }

        try keychain.setSecret("first", account: account)
        try keychain.setSecret("second", account: account)

        #expect(try keychain.secret(account: account) == "second")
    }

    @Test func removingASecretMakesItUnreadable() throws {
        let keychain = KeychainService()
        let account = makeAccount("remove")

        try keychain.setSecret("gone soon", account: account)
        try keychain.removeSecret(account: account)

        #expect(try keychain.secret(account: account) == nil)
    }

    /// Olmayan bir kaydı silmek hata DEĞİLDİR: "bu anahtar artık durmasın" isteği,
    /// zaten durmuyorsa da yerine gelmiştir.
    @Test func removingAnAbsentSecretIsNotAnError() throws {
        let keychain = KeychainService()
        try keychain.removeSecret(account: makeAccount("never-existed"))
    }

    /// Boş dize "anahtar yok" demektir; kayıt bırakmak, boş bir anahtarla istek
    /// göndermeye çalışan bir sağlayıcı üretirdi.
    @Test func storingAnEmptyStringRemovesTheSecret() throws {
        let keychain = KeychainService()
        let account = makeAccount("empty")
        defer { try? keychain.removeSecret(account: account) }

        try keychain.setSecret("stored", account: account)
        try keychain.setSecret("", account: account)

        #expect(try keychain.secret(account: account) == nil)
    }

    /// Hesap adları sağlayıcı başına ayrışmalı: OpenAI anahtarını okumak Anthropic
    /// anahtarını döndürmemeli.
    @Test func eachProviderHasItsOwnAccountName() {
        let accounts = AIProviderKind.allCases.compactMap(\.keychainAccount)
        #expect(Set(accounts).count == accounts.count)
        // Yerel Ollama anahtar istemez; ona hesap açmak, olmayan bir sırrı
        // varmış gibi göstermek olurdu.
        #expect(AIProviderKind.ollama.keychainAccount == nil)
    }
}
