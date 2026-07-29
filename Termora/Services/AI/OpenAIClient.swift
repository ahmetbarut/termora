import Foundation

/// OpenAI Chat Completions istemcisi — ve aynı sözleşmeyi konuşan her adres
/// (briefs/2 "AI Asistanı": *OpenAI uyumlu özel API adresleri*).
///
/// Özel adres için AYRI bir istemci yazılmadı: fark yalnızca adres ve anahtarın
/// zorunlu olup olmadığı. İkinci bir kopya, birinde düzeltilen bir hatanın
/// diğerinde yaşamaya devam etmesi demekti.
@MainActor
final class OpenAIClient: AIProviding {

    let kind: AIProviderKind

    private let endpoint: () -> String
    private let apiKey: () -> String?
    private let transport: any AIHTTPTransport

    init(kind: AIProviderKind,
         endpoint: @escaping () -> String,
         apiKey: @escaping () -> String?,
         transport: any AIHTTPTransport) {
        self.kind = kind
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.transport = transport
    }

    var endpointDescription: String { endpoint() }

    func availableModels() async throws -> [AIModel] {
        let request = try makeRequest(path: "models", method: "GET")
        let data = try await perform(request)

        let decoded: ModelsResponse
        do {
            decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        } catch {
            throw AIProviderError.malformedResponse("model listesi çözülemedi")
        }
        let models = decoded.data.map { AIModel(name: $0.id, sizeBytes: nil) }
        guard !models.isEmpty else {
            // Boş dizi kullanıcıya hiçbir şey anlatmaz; hata cümlesi anlatır.
            throw AIProviderError.noModelsInstalled(endpoint: endpoint())
        }
        return models
    }

    func complete(_ request: AIRequest) async throws -> AIReply {
        var httpRequest = try makeRequest(path: "chat/completions", method: "POST")
        httpRequest.httpBody = try JSONEncoder().encode(body(for: request, streaming: false))
        let data = try await perform(httpRequest)

        let decoded: ChatResponse
        do {
            decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw AIProviderError.malformedResponse("choices dizisi çözülemedi")
        }
        let text = (decoded.choices.first?.message.content ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return AIReply(text: text)
    }

    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                do {
                    var httpRequest = try makeRequest(path: "chat/completions", method: "POST")
                    httpRequest.httpBody = try JSONEncoder()
                        .encode(body(for: request, streaming: true))

                    let (bytes, response) = try await transport.stream(httpRequest)
                    guard (200...299).contains(response.statusCode) else {
                        var body = Data()
                        for try await chunk in bytes { body.append(chunk) }
                        throw Self.error(status: response.statusCode, body: body)
                    }

                    var decoder = ServerSentEventDecoder()
                    for try await chunk in bytes {
                        for event in decoder.consume(chunk) {
                            // OpenAI akışı "[DONE]" nöbetçisiyle biter; JSON değildir.
                            if event.data == "[DONE]" {
                                continuation.finish()
                                return
                            }
                            if let text = Self.deltaText(from: event) {
                                continuation.yield(text)
                            }
                        }
                    }
                    continuation.finish()
                } catch let error as AIProviderError {
                    continuation.finish(throwing: error)
                } catch is URLError {
                    continuation.finish(throwing: AIProviderError.endpointUnreachable(
                        endpoint: endpoint()
                    ) as any Error)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static func deltaText(from event: ServerSentEvent) -> String? {
        guard let data = event.data.data(using: .utf8),
              let frame = try? JSONDecoder().decode(StreamFrame.self, from: data),
              let text = frame.choices.first?.delta.content, !text.isEmpty else { return nil }
        return text
    }

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        // Anahtar yalnız GEREKTİĞİNDE zorunlu: yerel OpenAI-uyumlu sunucular
        // (LM Studio, vLLM) çoğu zaman anahtarsız çalışır.
        let key = apiKey()
        if kind == .openAI, key?.isEmpty != false {
            throw AIProviderError.missingAPIKey(provider: kind)
        }
        guard let base = RemoteEndpoint.url(from: endpoint()) else {
            throw AIProviderError.invalidEndpoint(endpoint())
        }

        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Sistem yönergesi mesaj listesinde KALIR — Anthropic'in tam tersi.
    private func body(for request: AIRequest, streaming: Bool) -> Payload {
        Payload(model: request.model,
                messages: request.messages.map {
                    Payload.Message(role: $0.role.rawValue, content: $0.content.text)
                },
                stream: streaming ? true : nil)
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
        let messages: [Message]
        let stream: Bool?
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    private struct ModelsResponse: Decodable {
        struct Entry: Decodable { let id: String }
        let data: [Entry]
    }

    private struct StreamFrame: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta
        }
        let choices: [Choice]
    }
}
