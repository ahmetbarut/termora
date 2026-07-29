import CryptoKit
import Foundation

/// Bir lisansın taşıdığı her şey.
///
/// Alanlar bilerek İKİ tane: kime verildiği ve ne zamana kadar geçerli olduğu. Lisans
/// yükü kullanıcının makinesinde durur ve gerektiğinde ekranda gösterilir — oraya
/// konulan her ek alan, kullanıcı hakkında saklanan bir veri daha demektir.
nonisolated struct License: Equatable, Sendable, Codable {
    /// Lisansın kime verildiği (satın alma e-postası). Ayarlarda gösterilir ki
    /// kullanıcı hangi lisansın kurulu olduğunu görebilsin.
    var licensee: String
    /// Süresiz lisansta `nil`. briefs/2 abonelik İSTEMİYOR; bu alan "yıllık güncelleme"
    /// modelini mümkün kılmak için var, zorunlu kılmak için değil.
    var expiresAt: Date?

    private enum CodingKeys: String, CodingKey {
        case licensee
        case expiresAt
    }
}

/// Anahtar metninin biçimi. Tek yerde tanımlı: yazan ve okuyan aynı sabitleri kullanır,
/// yoksa iki tanım zamanla birbirinden ayrılır.
nonisolated enum LicenseKeyFormat {
    /// Kullanıcı anahtarı bir e-postadan kopyalar; önek onun ne olduğunu söyler.
    static let prefix = "TERMORA-"
    /// Yük ile imzayı ayıran nokta.
    static let separator: Character = "."

    /// Base64url (dolgusuz): anahtar e-postada satır sonuna denk gelirse `+` ve `/`
    /// karakterleri sarılırken bozulabilir, `-` ve `_` bozulmaz.
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: some StringProtocol) -> Data? {
        var base64 = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Dolgu geri konur: `Data(base64Encoded:)` eksik dolguyu kabul etmez.
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: base64)
    }
}

/// Anahtarı üreten taraf — yani biz, uygulama değil.
///
/// Uygulamanın içinde durmasının tek sebebi var: yazan ve okuyan kod yan yana olsun ki
/// biçim bir gün sessizce ayrışmasın. Özel anahtar burada YOK; bu tip onsuz hiçbir işe
/// yaramaz, dolayısıyla uygulamada bulunması bir risk taşımaz.
nonisolated struct LicenseKeyWriter {
    private let signingKey: Curve25519.Signing.PrivateKey

    init(signingKey: Curve25519.Signing.PrivateKey) {
        self.signingKey = signingKey
    }

    func key(_ license: License) throws -> String {
        let payload = try LicenseCoder.encoder.encode(license)
        let signature = try signingKey.signature(for: payload)
        return LicenseKeyFormat.prefix
            + LicenseKeyFormat.encode(payload)
            + String(LicenseKeyFormat.separator)
            + LicenseKeyFormat.encode(signature)
    }
}

/// Anahtarı ÇEVRİMDIŞI doğrular.
///
/// briefs/2: *Çevrimdışı kullanılabilirlik: doğrulama internet bağlantısına bağımlı
/// kalmasın.* Sunucuya soran bir doğrulama, uçakta ya da güvenlik duvarı ardındaki bir
/// kullanıcının satın aldığı özelliği kaybetmesi demektir — ve bir terminal uygulaması
/// tam olarak o ortamlarda kullanılır. İmza doğrulaması ağ gerektirmez.
nonisolated struct LicenseVerifier: Sendable {
    /// Ham gösterimi tutulur (`Data`), tipin kendisi değil: `Sendable` sorusunu ortadan
    /// kaldırır ve Info.plist'ten okunan değerle aynı biçimdir.
    private let publicKeyRepresentation: Data?

    init(publicKey: Curve25519.Signing.PublicKey?) {
        self.publicKeyRepresentation = publicKey?.rawRepresentation
    }

    /// Uygulamanın kendi doğrulayıcısı. Açık anahtar Info.plist'ten (`TermoraLicensePublicKey`,
    /// base64) gelir — kaynağa gömülmez ki sürüm başına değiştirilebilsin.
    ///
    /// Anahtar yoksa doğrulayıcı hiçbir şeyi kabul etmez: imzasız bir yapıda her metni
    /// geçerli saymak, lisans denetimini hiç yapmamakla aynı şey olurdu.
    static var production: LicenseVerifier {
        guard let base64 = Bundle.main.object(forInfoDictionaryKey: "TermoraLicensePublicKey") as? String,
              let data = Data(base64Encoded: base64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: data)
        else { return LicenseVerifier(publicKey: nil) }
        return LicenseVerifier(publicKey: key)
    }

    /// Doğrulayıcı bir açık anahtar taşıyor mu? Taşımıyorsa hiçbir anahtar geçmez.
    var isConfigured: Bool { publicKeyRepresentation != nil }

    /// Geçerliyse lisans, değilse `nil`. Bozuk metin bir HATA değildir: kullanıcı
    /// anahtarı yanlış yapıştırmış olabilir ve bu, uygulamanın çalışmasını engellememeli.
    func license(from text: String, now: Date) -> License? {
        guard let publicKeyRepresentation,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyRepresentation)
        else { return nil }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(LicenseKeyFormat.prefix) else { return nil }
        let body = trimmed.dropFirst(LicenseKeyFormat.prefix.count)

        let parts = body.split(separator: LicenseKeyFormat.separator, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let payload = LicenseKeyFormat.decode(parts[0]),
              let signature = LicenseKeyFormat.decode(parts[1]),
              key.isValidSignature(signature, for: payload),
              let license = try? LicenseCoder.decoder.decode(License.self, from: payload)
        else { return nil }

        // Bitiş tarihi imzalı yükün İÇİNDE: kullanıcı sistem saatini geri alabilir ama
        // yükü değiştiremez — geri alınan saat lisansı uzatmaz, yalnızca kendi
        // makinesinde erken düşürür.
        if let expiresAt = license.expiresAt, expiresAt < now { return nil }
        return license
    }
}

/// Yük hem yazılırken hem okunurken AYNI kurallarla kodlanmalı; tarihin gösterimi
/// değişirse imza tutmaz.
nonisolated enum LicenseCoder {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        // Alan sırası sabit: imza baytların üzerinde, sıra değişirse imza da değişir.
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
