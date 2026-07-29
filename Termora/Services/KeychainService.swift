import Foundation
import Security

/// briefs/1 "Güvenlik": *API anahtarları ve parolalar UserDefaults içinde tutulmamalı;
/// hassas bilgiler Keychain'de saklanmalı.*
///
/// Tek sorumluluğu bu: hesap adına karşılık gelen bir dizeyi login keychain'ine yazmak,
/// okumak, silmek. Hangi anahtarın hangi hesaba ait olduğuna `AIProviderKind` karar verir.
struct KeychainService {

    /// Keychain'deki `kSecAttrService`. Uygulamanın bundle kimliğiyle aynı tutulur ki
    /// başka bir uygulamanın kayıtlarıyla karışmasın.
    static let service = "com.ahmetbarut.Termora"

    enum Failure: Error, Equatable {
        /// `SecItem*` çağrısı beklenmeyen bir OSStatus döndürdü.
        case unexpectedStatus(OSStatus)
        /// Keychain'deki veri UTF-8 değil — başka bir şey aynı hesaba yazmış demektir.
        case unreadableData
    }

    private let service: String

    init(service: String = KeychainService.service) {
        self.service = service
    }

    /// Sırrı yazar; aynı hesapta kayıt varsa ÜSTÜNE yazar.
    ///
    /// Boş dize "anahtar yok" demektir ve kaydı siler: boş bir anahtar bırakmak,
    /// sağlayıcının onunla istek göndermeyi denemesine yol açardı.
    func setSecret(_ secret: String, account: String) throws {
        guard !secret.isEmpty else {
            try removeSecret(account: account)
            return
        }
        let data = Data(secret.utf8)

        // Önce güncellemeyi dene: `SecItemAdd` var olan kayıtta errSecDuplicateItem verir.
        let update = SecItemUpdate(query(account: account) as CFDictionary,
                                   [kSecValueData: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw Failure.unexpectedStatus(update) }

        var attributes = query(account: account)
        attributes[kSecValueData] = data
        // Anahtar yalnız bu Mac'te ve yalnız kilit açıkken okunabilir olsun: iCloud
        // anahtar zincirine ya da yedeklere kopyalanmaz.
        attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let add = SecItemAdd(attributes as CFDictionary, nil)
        guard add == errSecSuccess else { throw Failure.unexpectedStatus(add) }
    }

    /// Kayıt yoksa `nil`; bu bir hata değildir (kullanıcı anahtarı henüz girmemiştir).
    func secret(account: String) throws -> String? {
        var lookup = query(account: account)
        lookup[kSecReturnData] = true
        lookup[kSecMatchLimit] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure.unexpectedStatus(status) }
        guard let data = item as? Data, let text = String(data: data, encoding: .utf8) else {
            throw Failure.unreadableData
        }
        return text
    }

    /// Olmayan kaydı silmek hata değildir: istenen son durum zaten sağlanmıştır.
    func removeSecret(account: String) throws {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure.unexpectedStatus(status)
        }
    }

    private func query(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }
}
