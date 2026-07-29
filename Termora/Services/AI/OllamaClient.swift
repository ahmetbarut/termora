import Foundation

/// Ayarlardaki adresin çözümlenmesi. Saf; ağ yok.
enum OllamaEndpoint {

    /// Ollama'nın kendi varsayılanı.
    ///
    /// `nonisolated`: varsayılan argüman ve özellik başlatıcı ifadelerinden okunuyor;
    /// onlar yalıtımsız bağlamda değerlendirilir (bkz. `SWIFT_DEFAULT_ACTOR_ISOLATION`).
    nonisolated static let defaultAddress = "http://localhost:11434"

    /// Kullanıcının yazdığı adresi kullanılabilir bir taban URL'ine çevirir.
    ///
    /// Kurallar:
    /// - Şema yazılmamışsa `http://` varsayılır (`localhost:11434` çalışsın).
    /// - Yalnız `http`/`https` kabul edilir. `file://` gibi şemalar TAHMİN EDİLMEZ,
    ///   reddedilir: bir yazım hatası yüzünden istek başka bir yere gitmemeli.
    /// - Sondaki `/` atılır; yollar `\(base)/api/tags` diye kurulur ve çift `//` olmaz.
    static func url(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(where: { $0.isWhitespace }) else { return nil }

        let withScheme: String
        if let separator = trimmed.range(of: "://") {
            let scheme = trimmed[trimmed.startIndex..<separator.lowerBound].lowercased()
            guard scheme == "http" || scheme == "https" else { return nil }
            withScheme = trimmed
        } else {
            withScheme = "http://" + trimmed
        }

        var normalized = withScheme
        while normalized.hasSuffix("/") { normalized.removeLast() }

        guard let url = URL(string: normalized), url.host?.isEmpty == false else { return nil }
        return url
    }
}

/// briefs/2 "AI Asistanı" — Ollama sağlayıcısı (yerel, API anahtarsız).
///
/// # Tasarım
///
/// **Uç nokta her istekte yeniden okunur.** `endpoint` bir kapanıştır, sabit bir dize
/// değil: kullanıcı Ayarlar ▸ AI'da adresi değiştirdiğinde panelin istemciyi yeniden
/// kurması gerekmez.
///
/// **Boş model listesi bir HATADIR.** `/api/tags` boş dizi döndüğünde istemci
/// `noModelsInstalled` fırlatır. Bu makinede Ollama kurulu ama hiç model yok; yani bu
/// "kenar durum" değil, İLK karşılaşılan durumdur ve panelin ona söyleyecek somut bir
/// sözü olmalı (`ollama pull …`).
///
/// **Akış AÇIK ama sınırlı.** `stream(_:)` cevabı parça parça verir — yerel bir modelin
/// ilk ve son kelimesi arasında onlarca saniye olabiliyor. Parçalar yalnız CANLI METİN
/// olarak gösterilir; komut önerileri hâlâ yalnız TAMAMLANMIŞ cevaptan çıkarılır, çünkü
/// yarım bir kod bloğu çalıştırılabilir görünen eksik bir komut üretir. `complete(_:)`
/// tek parça yolu olarak duruyor ve model listesi gibi kısa çağrılarda kullanılıyor.
@MainActor
final class OllamaClient: AIProviding {

    let kind: AIProviderKind = .ollama

    private let endpoint: () -> String
    private let transport: any AIHTTPTransport

    init(endpoint: @escaping () -> String, transport: any AIHTTPTransport) {
        self.endpoint = endpoint
        self.transport = transport
    }

    var endpointDescription: String {
        OllamaEndpoint.url(from: endpoint())?.absoluteString ?? endpoint()
    }

    // MARK: - Modeller

    func availableModels() async throws -> [AIModel] {
        let base = try baseURL()
        var request = URLRequest(url: base.appendingPathComponent("api/tags"))
        request.httpMethod = "GET"
        // Liste sorgusu kullanıcı bir menü açarken koşar; uzun beklemez.
        request.timeoutInterval = 10

        let data = try await perform(request, base: base, model: nil)
        let decoded: TagsResponse
        do {
            decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
        } catch {
            throw AIProviderError.malformedResponse("/api/tags: \(error.localizedDescription)")
        }
        let models = decoded.models.map { AIModel(name: $0.name, sizeBytes: $0.size) }
        guard !models.isEmpty else {
            throw AIProviderError.noModelsInstalled(endpoint: base.absoluteString)
        }
        return models
    }

    // MARK: - Sohbet

    func complete(_ request: AIRequest) async throws -> AIReply {
        let base = try baseURL()
        var httpRequest = URLRequest(url: base.appendingPathComponent("api/chat"))
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Model diskten ilk kez yükleniyorsa ilk cevap uzun sürebilir.
        httpRequest.timeoutInterval = 180
        httpRequest.httpBody = try encode(request)

        let data = try await perform(httpRequest, base: base, model: request.model)
        let decoded: ChatResponse
        do {
            decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw AIProviderError.malformedResponse("/api/chat: \(error.localizedDescription)")
        }
        let text = decoded.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AIProviderError.malformedResponse("the model returned an empty answer")
        }
        return AIReply(text: text)
    }

    /// Akışlı cevap. Aynı uç nokta, `stream: true`.
    ///
    /// Hata yolu `complete` ile AYNI: HTTP durum kodu ve ağ hataları aynı `AIProviderError`
    /// üyelerine çevrilir, böylece panelin gösterdiği dört soruluk durum değişmez.
    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                do {
                    let base = try baseURL()
                    var httpRequest = URLRequest(url: base.appendingPathComponent("api/chat"))
                    httpRequest.httpMethod = "POST"
                    httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    httpRequest.timeoutInterval = 180
                    httpRequest.httpBody = try encode(request, streaming: true)

                    let (bytes, response) = try await transport.stream(httpRequest)
                    guard (200..<300).contains(response.statusCode) else {
                        // Akışta gövde okunmadan durum bilinir; hata gövdesi tek parçadır.
                        var body = Data()
                        for try await chunk in bytes { body.append(chunk) }
                        let detail = Self.serverMessage(from: body)
                        if response.statusCode == 404, detail.lowercased().contains("not found") {
                            throw AIProviderError.modelNotFound(request.model)
                        }
                        throw AIProviderError.requestFailed(status: response.statusCode, detail: detail)
                    }

                    var decoder = OllamaStreamDecoder()
                    for try await chunk in bytes {
                        for case let .delta(text) in decoder.consume(chunk) {
                            continuation.yield(text)
                        }
                    }
                    // Sunucu akışın İÇİNDE hata bildirdiyse akış başarıyla bitmiş SAYILMAZ.
                    if let failure = decoder.failure {
                        throw AIProviderError.malformedResponse(failure)
                    }
                    continuation.finish()
                } catch let error as AIProviderError {
                    continuation.finish(throwing: error)
                } catch let error as URLError {
                    continuation.finish(throwing: Self.map(error, endpoint: self.endpoint()))
                } catch {
                    continuation.finish(throwing:
                        AIProviderError.malformedResponse(error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Ortak yol

    private func baseURL() throws -> URL {
        let raw = endpoint()
        guard let url = OllamaEndpoint.url(from: raw) else {
            throw AIProviderError.invalidEndpoint(raw)
        }
        return url
    }

    /// İsteği gönderir ve HTTP durumunu Termora'nın hata diline çevirir.
    ///
    /// `URLError` OLDUĞU GİBİ yukarı verilmez: "The operation couldn't be completed"
    /// kullanıcıya hiçbir şey anlatmaz (briefs/2 "Hatalar sessizce yutulmamalı" —
    /// yutulmuyor, ama anlaşılır bir dile çevriliyor).
    private func perform(_ request: URLRequest, base: URL, model: String?) async throws -> Data {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as AIProviderError {
            throw error
        } catch let error as URLError {
            throw Self.map(error, endpoint: base.absoluteString)
        } catch {
            throw AIProviderError.malformedResponse(error.localizedDescription)
        }

        guard (200..<300).contains(response.statusCode) else {
            let detail = Self.serverMessage(from: data)
            // Ollama indirilmemiş bir model için 404 + "model … not found" döner.
            if response.statusCode == 404, let model, detail.lowercased().contains("not found") {
                throw AIProviderError.modelNotFound(model)
            }
            throw AIProviderError.requestFailed(status: response.statusCode, detail: detail)
        }
        return data
    }

    private static func map(_ error: URLError, endpoint: String) -> AIProviderError {
        switch error.code {
        case .cannotConnectToHost, .cannotFindHost, .timedOut, .networkConnectionLost,
             .notConnectedToInternet, .dnsLookupFailed, .secureConnectionFailed:
            return .endpointUnreachable(endpoint: endpoint)
        case .unsupportedURL, .badURL:
            return .invalidEndpoint(endpoint)
        default:
            return .malformedResponse(error.localizedDescription)
        }
    }

    /// Ollama hatayı `{"error":"…"}` olarak döner; gövde başka bir şeyse ham metne düşülür.
    private static func serverMessage(from data: Data) -> String {
        if let decoded = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            return decoded.error
        }
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "no details" : String(raw.prefix(200))
    }

    private func encode(_ request: AIRequest, streaming: Bool = false) throws -> Data {
        let body = ChatRequestBody(
            model: request.model,
            // Yalnız `MaskedPayload.text` tele düşer; ham metin bu tipe hiç girmez.
            messages: request.messages.map {
                ChatRequestBody.Message(role: $0.role.rawValue, content: $0.content.text)
            },
            stream: streaming
        )
        do {
            return try JSONEncoder().encode(body)
        } catch {
            throw AIProviderError.malformedResponse("request could not be encoded")
        }
    }

    // MARK: - Tel biçimleri

    private struct TagsResponse: Decodable {
        struct Entry: Decodable {
            let name: String
            let size: Int64?
        }
        let models: [Entry]
    }

    private struct ChatResponse: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }

    private struct ErrorResponse: Decodable {
        let error: String
    }

    private struct ChatRequestBody: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        let model: String
        let messages: [Message]
        let stream: Bool
    }
}
