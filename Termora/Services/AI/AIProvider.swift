import Foundation

// MARK: - Sağlayıcı

/// Hangi sağlayıcı ailesi (briefs/2 "AI Asistanı": OpenAI, Anthropic, Ollama ve
/// OpenAI uyumlu özel API adresleri).
enum AIProviderKind: String, Codable, CaseIterable, Identifiable {
    case ollama
    case openAI
    case anthropic
    /// OpenAI ile aynı sözleşmeyi konuşan üçüncü taraf adresler (Groq, Together,
    /// LM Studio, vLLM…). Ayrı bir istemci değil, `OpenAIClient`'ın başka bir adresi.
    case openAICompatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama: "Ollama (local)"
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .openAICompatible: "OpenAI-compatible endpoint"
        }
    }

    /// Sağlayıcının API anahtarını sakladığı Keychain hesabı; anahtar istemeyen
    /// sağlayıcıda `nil`.
    ///
    /// Yerel Ollama'ya hesap açmak, olmayan bir sırrı varmış gibi gösterirdi —
    /// ayarlar ekranı da o yüzden ona anahtar alanı çizmez.
    var keychainAccount: String? {
        switch self {
        case .ollama: nil
        case .openAI: "ai.openai.apiKey"
        case .anthropic: "ai.anthropic.apiKey"
        case .openAICompatible: "ai.openAICompatible.apiKey"
        }
    }

    var requiresAPIKey: Bool { keychainAccount != nil }

    /// Kullanıcı adres girmediğinde kullanılacak resmî uç nokta. Özel adresli
    /// sağlayıcıda `nil` — orada adres kullanıcının kendisinden gelir.
    var defaultEndpoint: String? {
        switch self {
        case .ollama: OllamaEndpoint.defaultAddress
        case .openAI: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com/v1"
        case .openAICompatible: nil
        }
    }
}

/// Kurulu bir model.
struct AIModel: Identifiable, Equatable, Hashable {
    /// Sağlayıcıya gönderilen ad, ör. `llama3.2:latest`.
    let name: String
    /// Diskteki boyut; sağlayıcı söylemezse nil.
    let sizeBytes: Int64?

    var id: String { name }

    /// `llama3.2:latest` → `llama3.2`. Etiket bilgi taşımadığında listeyi sadeleştirir.
    var displayName: String {
        name.hasSuffix(":latest") ? String(name.dropLast(":latest".count)) : name
    }

    /// "2.0 GB" — modelin gerçekten indirilmiş olduğunu görünür kılar.
    var sizeDescription: String? {
        guard let sizeBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

/// Modelin tek seferlik cevabı.
struct AIReply: Equatable {
    let text: String
}

/// AI sağlayıcısının Termora'ya bakan yüzü.
///
/// Somut sınıflar `OllamaClient`, `OpenAIClient` ve `AnthropicClient`; panel ve testler
/// yalnız bu protokolü görür, testler sahte bir sağlayıcıyla koşar ve HİÇBİR gerçek ağ
/// isteği yapmaz.
@MainActor
protocol AIProviding: AnyObject {
    var kind: AIProviderKind { get }
    /// Kullanıcıya gösterilen adres; hata metinlerinde geçer.
    var endpointDescription: String { get }

    /// Kurulu modeller. Hiç model yoksa `AIProviderError.noModelsInstalled` FIRLATIR —
    /// boş dizi dönmez, çünkü boş liste kullanıcıya hiçbir şey anlatmaz.
    func availableModels() async throws -> [AIModel]

    func complete(_ request: AIRequest) async throws -> AIReply

    /// Cevabı PARÇA PARÇA verir. Yerel bir modelin ilk kelimesi ile son kelimesi arasında
    /// onlarca saniye olabiliyor; akış olmadan panel o süre boyunca boş durur.
    ///
    /// Varsayılan uygulama `complete`'e düşer: akış desteklemeyen bir sağlayıcı yazmak
    /// hiçbir ek iş gerektirmesin.
    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, any Error>
}

extension AIProviding {
    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    continuation.yield(try await complete(request).text)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Hatalar

/// briefs/3 "Error State": her hata dört soruyu cevaplar — ne başarısız oldu, muhtemel
/// sebep ne, kullanıcı ne yapabilir, teknik detay nedir.
enum AIProviderError: Error, Equatable {
    /// Ayarlardaki adres bir HTTP adresi değil.
    case invalidEndpoint(String)
    /// Sağlayıcı anahtar ister ama Keychain'de kayıt yok.
    case missingAPIKey(provider: AIProviderKind)
    /// Adres doğru ama kimse cevap vermiyor.
    case endpointUnreachable(endpoint: String)
    /// Ollama çalışıyor ama hiç model indirilmemiş — bu makinenin başlangıç durumu.
    case noModelsInstalled(endpoint: String)
    case modelNotFound(String)
    case requestFailed(status: Int, detail: String)
    case malformedResponse(String)

    /// Ne başarısız oldu.
    var title: String {
        switch self {
        case .invalidEndpoint: "That is not a valid Ollama address"
        case let .missingAPIKey(provider): "\(provider.displayName) needs an API key"
        case .endpointUnreachable: "Termora could not reach Ollama"
        case .noModelsInstalled: "Ollama has no models to answer with"
        case let .modelNotFound(model): "The model “\(model)” is not installed"
        case .requestFailed: "Ollama refused the request"
        case .malformedResponse: "Termora could not read Ollama's answer"
        }
    }

    /// Muhtemel sebep.
    var reason: String {
        switch self {
        case let .invalidEndpoint(raw):
            "“\(raw)” is not an http:// or https:// address."
        case let .missingAPIKey(provider):
            "Termora has no \(provider.displayName) key in the macOS Keychain, and this "
                + "provider refuses unauthenticated requests."
        case let .endpointUnreachable(endpoint):
            "Nothing answered at \(endpoint). Ollama is probably not running, or it listens "
                + "on a different address."
        case let .noModelsInstalled(endpoint):
            "Ollama is running at \(endpoint) and reports no models installed, so there is "
                + "nothing to send a question to."
        case let .modelNotFound(model):
            "Ollama does not have “\(model)”. It may have been removed since you chose it."
        case let .requestFailed(status, detail):
            "Ollama answered with HTTP \(status): \(detail)."
        case .malformedResponse:
            "The answer did not look like an Ollama response. The address may point at a "
                + "different server."
        }
    }

    /// Kullanıcı ne yapabilir. Somut, kopyalanabilir adım.
    var recovery: String {
        switch self {
        case .invalidEndpoint:
            "Enter an address such as http://localhost:11434 in Settings ▸ AI."
        case .missingAPIKey:
            "Paste the key in Settings ▸ AI. It is stored in the Keychain, never in "
                + "Termora's settings file."
        case .endpointUnreachable:
            "Start it with `ollama serve`, then try again, or change the address in Settings ▸ AI."
        case .noModelsInstalled:
            "Download one first, for example `ollama pull llama3.2`, then refresh the model list."
        case .modelNotFound:
            "Pick another model in Settings ▸ AI, or run `ollama pull` for this one."
        case .requestFailed:
            "Check the Ollama server log, then try again."
        case .malformedResponse:
            "Check that the address in Settings ▸ AI points at Ollama."
        }
    }

    /// Teknik detay (briefs/3: "Teknik detay nasıl görüntülenir?"). Panelde açılır bir
    /// alanda gösterilir; hiçbir zaman terminal çıktısı ya da sır taşımaz.
    var technicalDetail: String {
        switch self {
        case let .invalidEndpoint(raw): "invalidEndpoint(\(raw))"
        case let .missingAPIKey(provider): "missingAPIKey(\(provider.rawValue))"
        case let .endpointUnreachable(endpoint): "endpointUnreachable(\(endpoint))"
        case let .noModelsInstalled(endpoint): "noModelsInstalled(\(endpoint))"
        case let .modelNotFound(model): "modelNotFound(\(model))"
        case let .requestFailed(status, detail): "httpStatus(\(status)) \(detail)"
        case let .malformedResponse(detail): "malformedResponse(\(detail))"
        }
    }
}

// MARK: - Taşıma dikişi

/// Ağ katmanı. Tek amacı testlerin gerçek istek yapmadan koşabilmesidir; `URLSession`
/// doğrudan çağrılsaydı her test bir sunucuya bağımlı olurdu.
@MainActor
protocol AIHTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)

    /// Yanıtı bayt bayt verir (akış). Varsayılan uygulama `send`'e düşer ve tek parça
    /// yayar: akış desteklemeyen bir taşıma yazmak ek iş gerektirmesin.
    func stream(_ request: URLRequest) async throws -> (AsyncThrowingStream<Data, any Error>, HTTPURLResponse)
}

extension AIHTTPTransport {
    func stream(_ request: URLRequest) async throws -> (AsyncThrowingStream<Data, any Error>, HTTPURLResponse) {
        let (data, response) = try await send(request)
        return (AsyncThrowingStream { continuation in
            continuation.yield(data)
            continuation.finish()
        }, response)
    }
}

/// Üretimdeki taşıma.
///
/// Oturum uygulama genelindeki `URLSession.shared`'dan AYRIDIR: AI istekleri tek hedefe
/// gider ve kendi zaman aşımlarını taşır, paylaşılan oturumun ayarlarını değiştirmemeli.
@MainActor
struct URLSessionAITransport: AIHTTPTransport {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        // Yerel bir sunucu ya hemen cevap verir ya da hiç; uzun beklemek panelde sonsuz
        // spinner demektir (briefs/3 "Loading State").
        configuration.timeoutIntervalForRequest = 20
        // Bir modelin ilk cevabı dakikaları bulabilir (model diskten yükleniyor).
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIProviderError.malformedResponse("response was not HTTP")
        }
        return (data, http)
    }

    func stream(_ request: URLRequest) async throws -> (AsyncThrowingStream<Data, any Error>, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIProviderError.malformedResponse("response was not HTTP")
        }
        return (AsyncThrowingStream { continuation in
            Task {
                do {
                    // Satır satır toplanır: NDJSON'un doğal sınırı budur ve tek tek bayt
                    // yaymak her karakter için bir görev uyandırması demekti.
                    for try await line in bytes.lines {
                        continuation.yield(Data((line + "\n").utf8))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }, http)
    }
}
