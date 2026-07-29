import Foundation

/// Tek bir Server-Sent Event.
struct ServerSentEvent: Equatable {
    /// `event:` satırı; sunucu göndermediyse nil.
    let name: String?
    /// `data:` satırlarının satırbaşıyla birleşmiş hâli.
    let data: String
}

/// SSE akışını parça parça çözen SAF durum makinesi.
///
/// Hem OpenAI hem Anthropic cevaplarını bu biçimde akıtır. Ayrı ve saf bir tip: akışın en
/// kırılgan yeri ağ paketlerinin olay sınırında GELMEMESİ, ve bunu gerçek bir sunucuyla
/// sınamak imkânsıza yakın. Burada tampon mantığı düz metinle test edilebiliyor.
struct ServerSentEventDecoder {

    /// Olay sınırında bölünmüş baytlar. Tamponlanmazsa cevabın ortası SESSİZCE kaybolur.
    private var buffer = ""

    mutating func consume(_ chunk: Data) -> [ServerSentEvent] {
        // Geçersiz UTF-8 baytları atılır, akış devam eder: yarısı gelmiş bir cevabı
        // tek bozuk bayt yüzünden silmek kullanıcıya hiçbir şey kazandırmaz.
        buffer += String(decoding: chunk, as: UTF8.self)

        var events: [ServerSentEvent] = []
        // Olay sınırı boş satırdır. CRLF gönderen sunucular için \r önce temizlenir.
        buffer = buffer.replacingOccurrences(of: "\r\n", with: "\n")
        while let range = buffer.range(of: "\n\n") {
            let block = String(buffer[buffer.startIndex..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])
            if let event = parse(block) { events.append(event) }
        }
        return events
    }

    /// Veri taşımayan olay yutulur: çağıranın çözecek bir şeyi yoktur ve boş bir parça
    /// cevaba eklenirse akış bozulmuş görünür.
    private func parse(_ block: String) -> ServerSentEvent? {
        var name: String?
        var dataLines: [String] = []

        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            // ":" ile başlayan satır yorumdur — sunucular bağlantıyı canlı tutmak için yollar.
            if line.hasPrefix(":") { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let field = String(line[line.startIndex..<colon])
            // Alan adından sonraki TEK boşluk biçimin parçasıdır, verinin değil.
            var value = String(line[line.index(after: colon)...])
            if value.hasPrefix(" ") { value.removeFirst() }

            switch field {
            case "event": name = value
            case "data": dataLines.append(value)
            default: continue
            }
        }

        guard !dataLines.isEmpty else { return nil }
        return ServerSentEvent(name: name, data: dataLines.joined(separator: "\n"))
    }
}
