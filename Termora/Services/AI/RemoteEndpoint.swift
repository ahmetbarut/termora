import Foundation

/// Uzak sağlayıcıların ortak adres ve hata-gövdesi işleri.
///
/// Ollama'nın adres kuralları (şema tahmini yok, sondaki `/` atılır) uzak sağlayıcılar
/// için de aynen geçerli — ikinci bir kopya yazmak, birinde düzeltilen bir hatanın
/// diğerinde yaşamaya devam etmesi demekti.
enum RemoteEndpoint {

    static func url(from raw: String) -> URL? {
        OllamaEndpoint.url(from: raw)
    }

    /// Sağlayıcının hata gövdesinden okunabilir bir cümle çıkarır.
    ///
    /// OpenAI ve Anthropic hatayı `{"error":{"message":"…"}}` biçiminde döner; Ollama
    /// düz `{"error":"…"}`. İkisi de denenir, hiçbiri tutmazsa ham gövdenin başı
    /// gösterilir — "HTTP 401" tek başına hangi anahtarın yanlış olduğunu söylemez
    /// (briefs/3 "Error State").
    static func serverMessage(from data: Data) -> String {
        if let nested = try? JSONDecoder().decode(NestedError.self, from: data),
           let message = nested.error.message {
            return message
        }
        if let flat = try? JSONDecoder().decode(FlatError.self, from: data) {
            return flat.error
        }
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "no details" : String(raw.prefix(200))
    }

    private struct NestedError: Decodable {
        struct Body: Decodable { let message: String? }
        let error: Body
    }

    private struct FlatError: Decodable {
        let error: String
    }
}
