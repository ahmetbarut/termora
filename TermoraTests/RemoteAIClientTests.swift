import Foundation
import Testing
@testable import Termora

/// briefs/2 "AI Asistanı": OpenAI, Anthropic ve OpenAI uyumlu özel API adresleri.
///
/// Hiçbir test gerçek istek yapmaz — `FakeAIHTTPTransport` ile koşar. Ölçülen şey
/// istemcinin ürettiği İSTEK (adres, başlıklar, gövde) ve okuduğu CEVAP; ikisi de
/// sağlayıcının yayımlanmış sözleşmesidir.
@MainActor
@Suite("Uzak AI sağlayıcıları")
struct RemoteAIClientTests {

    /// `MaskedPayload` yalnız maskeleyiciden çıkar — bu bilinçli: maskelemeden geçmemiş
    /// bir metin isteğe giremesin diye initializer kapalı. Testler de aynı kapıdan geçer.
    private func request(model: String = "test-model") -> AIRequest {
        AIRequest(model: model, messages: [
            .init(role: .system, content: MaskedPayload.masking("You are Termora.")),
            .init(role: .user, content: MaskedPayload.masking("list files")),
        ])
    }

    private func header(_ name: String, in transport: FakeAIHTTPTransport) -> String? {
        transport.sent.last?.value(forHTTPHeaderField: name)
    }

    // MARK: - Anthropic

    /// Anthropic anahtarı `x-api-key` ile taşır ve sürüm başlığını ZORUNLU kılar;
    /// `Authorization: Bearer` ile gönderilen istek 401 döner.
    @Test func anthropicSendsItsOwnAuthAndVersionHeaders() async throws {
        let transport = FakeAIHTTPTransport(json: """
            {"content":[{"type":"text","text":"ls -la"}]}
            """)
        let client = AnthropicClient(endpoint: { "https://api.anthropic.com/v1" },
                                     apiKey: { "sk-ant-test" },
                                     transport: transport)

        _ = try await client.complete(request())

        #expect(header("x-api-key", in: transport) == "sk-ant-test")
        #expect(header("anthropic-version", in: transport) == "2023-06-01")
        #expect(header("Authorization", in: transport) == nil)
        #expect(transport.sent.last?.url?.absoluteString == "https://api.anthropic.com/v1/messages")
    }

    /// Anthropic sistem yönergesini `messages` içinde DEĞİL, ayrı bir `system` alanında
    /// bekler. Mesajlar arasına konursa API 400 döner.
    @Test func anthropicLiftsTheSystemPromptOutOfTheMessageList() async throws {
        let transport = FakeAIHTTPTransport(json: #"{"content":[{"type":"text","text":"ok"}]}"#)
        let client = AnthropicClient(endpoint: { "https://api.anthropic.com/v1" },
                                     apiKey: { "sk-ant-test" },
                                     transport: transport)

        _ = try await client.complete(request())

        let body = try #require(transport.lastBodyText)
        #expect(body.contains("\"system\":\"You are Termora.\""))
        #expect(body.contains("\"role\":\"system\"") == false)
        // max_tokens Anthropic'te zorunludur; yollamayan istek 400 alır.
        #expect(body.contains("\"max_tokens\""))
    }

    @Test func anthropicJoinsEveryTextBlockOfTheAnswer() async throws {
        let transport = FakeAIHTTPTransport(json: """
            {"content":[{"type":"text","text":"first"},{"type":"text","text":" second"}]}
            """)
        let client = AnthropicClient(endpoint: { "https://api.anthropic.com/v1" },
                                     apiKey: { "sk-ant-test" },
                                     transport: transport)

        #expect(try await client.complete(request()).text == "first second")
    }

    /// briefs/1 "Güvenlik": anahtar yoksa istek HİÇ kurulmamalı — boş bir anahtarla
    /// sunucuya gitmek, kullanıcıya 401'i sağlayıcının hatası gibi gösterirdi.
    @Test func anthropicRefusesToSendWithoutAnAPIKey() async throws {
        let transport = FakeAIHTTPTransport(json: "{}")
        let client = AnthropicClient(endpoint: { "https://api.anthropic.com/v1" },
                                     apiKey: { nil },
                                     transport: transport)

        await #expect(throws: AIProviderError.missingAPIKey(provider: .anthropic)) {
            try await client.complete(request())
        }
        #expect(transport.sent.isEmpty)
    }

    // MARK: - OpenAI

    @Test func openAISendsABearerToken() async throws {
        let transport = FakeAIHTTPTransport(json: """
            {"choices":[{"message":{"content":"ls -la"}}]}
            """)
        let client = OpenAIClient(kind: .openAI,
                                  endpoint: { "https://api.openai.com/v1" },
                                  apiKey: { "sk-openai-test" },
                                  transport: transport)

        #expect(try await client.complete(request()).text == "ls -la")
        #expect(header("Authorization", in: transport) == "Bearer sk-openai-test")
        #expect(transport.sent.last?.url?.absoluteString
                == "https://api.openai.com/v1/chat/completions")
    }

    /// OpenAI sistem yönergesini mesaj listesinde bekler — Anthropic'in tam tersi.
    @Test func openAIKeepsTheSystemPromptInTheMessageList() async throws {
        let transport = FakeAIHTTPTransport(json: #"{"choices":[{"message":{"content":"ok"}}]}"#)
        let client = OpenAIClient(kind: .openAI,
                                  endpoint: { "https://api.openai.com/v1" },
                                  apiKey: { "sk-openai-test" },
                                  transport: transport)

        _ = try await client.complete(request())

        let body = try #require(transport.lastBodyText)
        #expect(body.contains("\"role\":\"system\""))
        #expect(body.contains("\"system\":") == false)
    }

    /// Özel adresli sağlayıcı ayrı bir istemci DEĞİLDİR: aynı sözleşme, başka adres.
    /// Yerel sunucular (LM Studio, vLLM) çoğu zaman anahtar istemez.
    @Test func anOpenAICompatibleEndpointWorksWithoutAKey() async throws {
        let transport = FakeAIHTTPTransport(json: #"{"choices":[{"message":{"content":"hi"}}]}"#)
        let client = OpenAIClient(kind: .openAICompatible,
                                  endpoint: { "http://localhost:1234/v1" },
                                  apiKey: { nil },
                                  transport: transport)

        #expect(try await client.complete(request()).text == "hi")
        #expect(header("Authorization", in: transport) == nil)
        #expect(transport.sent.last?.url?.absoluteString
                == "http://localhost:1234/v1/chat/completions")
    }

    @Test func openAIReportsAnEmptyModelListAsNoModelsInstalled() async throws {
        let transport = FakeAIHTTPTransport(json: #"{"data":[]}"#)
        let client = OpenAIClient(kind: .openAI,
                                  endpoint: { "https://api.openai.com/v1" },
                                  apiKey: { "sk-openai-test" },
                                  transport: transport)

        await #expect(throws: AIProviderError.self) {
            _ = try await client.availableModels()
        }
    }

    @Test func openAIListsTheModelsTheServerReports() async throws {
        let transport = FakeAIHTTPTransport(json: """
            {"data":[{"id":"gpt-4o"},{"id":"gpt-4o-mini"}]}
            """)
        let client = OpenAIClient(kind: .openAI,
                                  endpoint: { "https://api.openai.com/v1" },
                                  apiKey: { "sk-openai-test" },
                                  transport: transport)

        #expect(try await client.availableModels().map(\.name) == ["gpt-4o", "gpt-4o-mini"])
    }

    // MARK: - Hata gövdesi

    /// Sağlayıcının kendi hata cümlesi kullanıcıya ULAŞMALI: "HTTP 401" tek başına
    /// hangi anahtarın yanlış olduğunu söylemez (briefs/3 "Error State").
    @Test func theProvidersOwnErrorMessageSurvives() async throws {
        let transport = FakeAIHTTPTransport(
            json: #"{"error":{"message":"Incorrect API key provided"}}"#, status: 401
        )
        let client = OpenAIClient(kind: .openAI,
                                  endpoint: { "https://api.openai.com/v1" },
                                  apiKey: { "sk-wrong" },
                                  transport: transport)

        do {
            _ = try await client.complete(request())
            Issue.record("hata bekleniyordu")
        } catch let error as AIProviderError {
            #expect(error.technicalDetail.contains("Incorrect API key provided"))
        }
    }
}
