import Foundation

/// Anthropic Messages API istemcisi (briefs/2 "AI Asistanı").
///
/// Anthropic'in sözleşmesi OpenAI'ninkinden iki noktada ayrılır ve ikisi de sessiz
/// değil, 4xx'le patlayan farklardır:
///
/// 1. Kimlik `x-api-key` başlığıyla taşınır, `Authorization: Bearer` ile değil.
/// 2. Sistem yönergesi `messages` listesinde DEĞİL, gövdenin `system` alanındadır.
///
/// Ayrıca `anthropic-version` ve `max_tokens` zorunludur.
@MainActor
final class AnthropicClient: AIProviding {

    let kind: AIProviderKind = .anthropic

    /// Sürüm başlığı sabittir: API'nin biçimi bu tarihe göre dondurulmuştur ve
    /// yükseltme, cevabı okuyan kodun da gözden geçirilmesi demektir.
    static let apiVersion = "2023-06-01"

    /// Anthropic `max_tokens`'ı zorunlu kılar. Terminal cevapları kısa; bu sınır
    /// kaçak bir cevabın faturayı şişirmesini de engeller.
    static let maxTokens = 4096

    private let endpoint: () -> String
    private let apiKey: () -> String?
    private let transport: any AIHTTPTransport

    init(endpoint: @escaping () -> String,
         apiKey: @escaping () -> String?,
         transport: any AIHTTPTransport) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.transport = transport
    }

    var endpointDescription: String { endpoint() }

    /// Anthropic model listesi sunucudan okunmaz: `/v1/models` yalnız hesabın
    /// erişebildiklerini döner ve anahtar yokken çağrılamaz. Katalog sabit tutulur;
    /// kullanıcı listede olmayan bir model adını elle de yazabilir.
    func availableModels() async throws -> [AIModel] {
        AnthropicModels.catalog.map { AIModel(name: $0, sizeBytes: nil) }
    }

    func complete(_ request: AIRequest) async throws -> AIReply {
        let httpRequest = try makeRequest(request, streaming: false)
        let data = try await perform(httpRequest)

        let decoded: MessageResponse
        do {
            decoded = try JSONDecoder().decode(MessageResponse.self, from: data)
        } catch {
            throw AIProviderError.malformedResponse("content dizisi çözülemedi")
        }
        // Cevap birden çok metin bloğuna bölünebilir; yalnız ilkini almak cevabın
        // gerisini sessizce düşürürdü.
        let text = decoded.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return AIReply(text: text)
    }

    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                do {
                    let httpRequest = try makeRequest(request, streaming: true)
                    let (bytes, response) = try await transport.stream(httpRequest)
                    guard (200...299).contains(response.statusCode) else {
                        var body = Data()
                        for try await chunk in bytes { body.append(chunk) }
                        throw Self.error(status: response.statusCode, body: body)
                    }

                    var decoder = ServerSentEventDecoder()
                    for try await chunk in bytes {
                        for event in decoder.consume(chunk) {
                            if let text = Self.deltaText(from: event) {
                                continuation.yield(text)
                            }
                        }
                    }
                    continuation.finish()
                } catch let error as AIProviderError {
                    continuation.finish(throwing: error)
                } catch let error as URLError {
                    continuation.finish(throwing: AIProviderError.endpointUnreachable(
                        endpoint: endpoint()
                    ) as any Error)
                    _ = error
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// `content_block_delta` olayının metni; başka her olay (ping, message_start,
    /// message_stop) yok sayılır.
    private static func deltaText(from event: ServerSentEvent) -> String? {
        guard let data = event.data.data(using: .utf8),
              let frame = try? JSONDecoder().decode(StreamFrame.self, from: data),
              frame.type == "content_block_delta",
              let text = frame.delta?.text, !text.isEmpty else { return nil }
        return text
    }

    private func makeRequest(_ request: AIRequest, streaming: Bool) throws -> URLRequest {
        guard let key = apiKey(), !key.isEmpty else {
            // briefs/1 "Güvenlik": anahtarsız istek HİÇ kurulmaz. Boş anahtarla gitmek
            // kullanıcıya 401'i sağlayıcının hatası gibi gösterirdi.
            throw AIProviderError.missingAPIKey(provider: .anthropic)
        }
        guard let base = RemoteEndpoint.url(from: endpoint()) else {
            throw AIProviderError.invalidEndpoint(endpoint())
        }

        var httpRequest = URLRequest(url: base.appendingPathComponent("messages"))
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.setValue(key, forHTTPHeaderField: "x-api-key")
        httpRequest.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")

        // Sistem yönergesi mesaj listesinden ÇIKARILIR: Anthropic onu ayrı alanda bekler.
        let system = request.messages.first { $0.role == .system }?.content.text
        let conversation = request.messages
            .filter { $0.role != .system }
            .map { Payload.Message(role: $0.role.rawValue, content: $0.content.text) }

        let body = Payload(model: request.model,
                           maxTokens: Self.maxTokens,
                           system: system,
                           messages: conversation,
                           stream: streaming ? true : nil)
        httpRequest.httpBody = try JSONEncoder().encode(body)
        return httpRequest
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as AIProviderError {
            throw error
        } catch {
            throw AIProviderError.endpointUnreachable(endpoint: endpoint())
        }
        guard (200...299).contains(response.statusCode) else {
            throw Self.error(status: response.statusCode, body: data)
        }
        return data
    }

    /// Sağlayıcının kendi cümlesi korunur: "HTTP 401" tek başına hangi anahtarın
    /// yanlış olduğunu söylemez (briefs/3 "Error State").
    private static func error(status: Int, body: Data) -> AIProviderError {
        .requestFailed(status: status, detail: RemoteEndpoint.serverMessage(from: body))
    }

    // MARK: - Tel biçimi

    private struct Payload: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        let model: String
        let maxTokens: Int
        let system: String?
        let messages: [Message]
        let stream: Bool?

        enum CodingKeys: String, CodingKey {
            case model
            case maxTokens = "max_tokens"
            case system, messages, stream
        }
    }

    private struct MessageResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
    }

    private struct StreamFrame: Decodable {
        struct Delta: Decodable { let text: String? }
        let type: String?
        let delta: Delta?
    }
}

/// Anthropic model kimlikleri. Sunucudan okunmaz (bkz. `availableModels`), bu yüzden
/// yeni model çıktığında burası güncellenir; kullanıcı listede olmayan bir adı elle
/// de yazabilir.
enum AnthropicModels {
    static let catalog = [
        "claude-opus-5",
        "claude-sonnet-5",
        "claude-haiku-4-5",
    ]
}
