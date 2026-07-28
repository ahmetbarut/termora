import Foundation

/// Kullanıcının AI bağlamına açıkça eklediği bir dosya (briefs/2 "Terminal Bağlamı").
///
/// Yalnız dosya ADI taşınır, tam yol DEĞİL: `/Users/ahmet/...` kullanıcı adını modele
/// gönderirdi ve bunun cevaba hiçbir katkısı yok.
///
/// İçerik burada HAM durur; maskeleme her zamanki yerinde, `AIContextBuilder`'da yapılır.
/// Ayrı bir maskeleme yolu açmak, `.env` eklemeyi sınırı atlatmanın yoluna çevirirdi.
struct AIFileAttachment: Identifiable, Equatable {
    let id: UUID
    let name: String
    let text: String

    init(id: UUID = UUID(), name: String, text: String) {
        self.id = id
        self.name = name
        self.text = text
    }

    /// Eklenen dosyaları tek bağlam bloğuna çevirir; hiç dosya yoksa nil (boş bir başlık
    /// bile gönderilmez).
    ///
    /// Her dosya ADIYLA başlar: model hangi içeriğin hangi dosyaya ait olduğunu bilmeli,
    /// yoksa iki dosya tek bir metne karışır.
    static func combinedText(of attachments: [AIFileAttachment]) -> String? {
        guard !attachments.isEmpty else { return nil }
        return attachments
            .map { "--- \($0.name) ---\n\($0.text)" }
            .joined(separator: "\n\n")
    }
}

/// Dosyayı okuyup eklenebilir bir parçaya çeviren tek kapı.
enum AIFileAttachmentLoader {

    /// Tek dosyadan okunacak en fazla bayt.
    ///
    /// Sınırsız okuma bir 2 GB'lık log dosyasında uygulamayı düşürürdü. Sınır aşıldığında
    /// dosya SESSİZCE KIRPILMAZ: eklenmez ve sebebi söylenir — kullanıcı yarısı gitmiş
    /// bir dosyayı gönderdiğini fark etmeyebilirdi.
    static let byteLimit = 256 * 1024

    /// Neden eklenemediği. Metin kullanıcıya olduğu gibi gösterilir.
    struct Failure: Equatable, Error {
        let message: String
    }

    static func load(name: String, data: Data) -> Result<AIFileAttachment, Failure> {
        guard data.count <= byteLimit else {
            let limit = ByteCountFormatter.string(fromByteCount: Int64(byteLimit), countStyle: .file)
            return .failure(Failure(message: "“\(name)” is too large to attach (limit \(limit))."))
        }
        // İkili dosya metin olarak gönderilemez: model için anlamsız, kullanıcı için ise
        // ne gittiğini göremediği bir yığın olurdu.
        guard let text = String(data: data, encoding: .utf8) else {
            return .failure(Failure(message: "“\(name)” is not a text file, so it cannot be attached."))
        }
        return .success(AIFileAttachment(name: name, text: text))
    }

    /// Diskten okur. `reading` dikiş: testler gerçek dosya sistemine dokunmaz.
    static func load(contentsOf url: URL,
                     reading: (URL) throws -> Data = { try Data(contentsOf: $0) })
        -> Result<AIFileAttachment, Failure> {
        let name = url.lastPathComponent
        do {
            return load(name: name, data: try reading(url))
        } catch {
            // Okunamayan dosya SESSİZCE yutulmaz: kullanıcı eklediğini sanıp göndermiş olurdu.
            return .failure(Failure(message: "“\(name)” could not be read."))
        }
    }
}
