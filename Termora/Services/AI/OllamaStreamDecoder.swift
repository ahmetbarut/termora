import Foundation

/// Ollama'nın `stream: true` yanıtını (NDJSON) parça parça çözen SAF durum makinesi.
///
/// Ayrı ve saf bir tip: akışın en kırılgan yeri ağ paketlerinin satır sınırında GELMEMESİ,
/// ve bunu gerçek bir sunucuyla sınamak imkânsıza yakın. Burada tampon mantığı düz metinle
/// test edilebiliyor.
struct OllamaStreamDecoder {

    enum Event: Equatable {
        /// Cevaba eklenecek metin parçası.
        case delta(String)
        /// Model cevabı bitirdi.
        case done
    }

    /// Sunucunun akışın İÇİNDE bildirdiği hata; yoksa nil.
    /// Ayrı tutulur çünkü bir hata satırı `done` DEĞİLDİR — akış eksik bitmiştir.
    private(set) var failure: String?

    /// Satır sınırında bölünmüş baytlar. Tamponlanmazsa JSON çözümü düşer ve cevabın
    /// ortası SESSİZCE kaybolurdu.
    private var buffer = Data()

    private static let newline = UInt8(ascii: "\n")

    mutating func consume(_ chunk: Data) -> [Event] {
        buffer.append(chunk)
        var events: [Event] = []
        while let index = buffer.firstIndex(of: Self.newline) {
            let line = buffer[buffer.startIndex..<index]
            buffer = buffer[buffer.index(after: index)...]
            if let event = decode(line) { events.append(event) }
        }
        return events
    }

    /// Bozuk bir satır o satırı ATLAR ama gelmiş metni atmaz: yarısı gelmiş bir cevabı
    /// silmek kullanıcıya hiçbir şey kazandırmaz.
    private mutating func decode(_ line: Data) -> Event? {
        guard !line.isEmpty, let frame = try? JSONDecoder().decode(Frame.self, from: line) else {
            return nil
        }
        if let error = frame.error {
            failure = error
            return nil
        }
        if let content = frame.message?.content, !content.isEmpty {
            return .delta(content)
        }
        return frame.done == true ? .done : nil
    }

    /// Bilinmeyen alanlar yok sayılır: Ollama sürümleri arasında alan ekleniyor ve tek
    /// biçime bağlanmak akışı sessizce boşaltırdı.
    private struct Frame: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message?
        let done: Bool?
        let error: String?
    }
}
