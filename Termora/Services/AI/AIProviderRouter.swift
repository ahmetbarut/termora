import Foundation

/// Seçili sağlayıcıya delege eden `AIProviding`.
///
/// Panel, model kataloğu ve komut paleti tek bir sağlayıcı referansı tutar ve o referans
/// uygulama ömrü boyunca değişmez. Kullanıcı Ayarlar ▸ AI'da sağlayıcıyı değiştirdiğinde
/// bunların hepsini yeniden kurmak yerine yönlendirici hedefini değiştirir.
///
/// briefs/1 "Güvenlik": API anahtarları Keychain'den okunur, ayar dosyasından değil.
/// Anahtar burada da SAKLANMAZ — her istekte Keychain'e sorulur, böylece kullanıcı
/// anahtarı sildiğinde bir sonraki istek gerçekten anahtarsız kalır.
@MainActor
final class AIProviderRouter: AIProviding {

    private let settings: SettingsStore
    private let keychain: KeychainService
    private let transport: any AIHTTPTransport

    /// Sağlayıcı başına tek örnek: her istekte yeni istemci kurmak, bir gün eklenecek
    /// bağlantı havuzu ya da önbelleği de her seferinde atardı.
    private var clients: [AIProviderKind: any AIProviding] = [:]

    init(settings: SettingsStore, keychain: KeychainService, transport: any AIHTTPTransport) {
        self.settings = settings
        self.keychain = keychain
        self.transport = transport
    }

    var kind: AIProviderKind { settings.settings.aiProviderKind }

    var endpointDescription: String { active.endpointDescription }

    func availableModels() async throws -> [AIModel] {
        try await active.availableModels()
    }

    func complete(_ request: AIRequest) async throws -> AIReply {
        try await active.complete(request)
    }

    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, any Error> {
        active.stream(request)
    }

    /// Sağlayıcının Keychain'deki anahtarı; anahtar istemeyen sağlayıcıda ve kayıt
    /// yokken `nil`.
    ///
    /// Keychain hatası da `nil` sayılır: okunamayan bir anahtar, olmayan bir anahtarla
    /// aynı sonucu doğurur (istek kurulmaz) ve kullanıcıya gösterilecek mesaj zaten
    /// `AIProviderError.missingAPIKey`'dir.
    func apiKey(for kind: AIProviderKind) -> String? {
        guard let account = kind.keychainAccount else { return nil }
        return try? keychain.secret(account: account)
    }

    private var active: any AIProviding {
        let kind = self.kind
        if let existing = clients[kind] { return existing }
        let client = makeClient(for: kind)
        clients[kind] = client
        return client
    }

    /// Adres bir KAPANIŞ olarak verilir, dize olarak değil: kullanıcı Ayarlar'da adresi
    /// değiştirdiğinde istemcinin yeniden kurulması gerekmez.
    private func makeClient(for kind: AIProviderKind) -> any AIProviding {
        let endpoint: () -> String = { [settings] in settings.settings.aiEndpoint(for: kind) }
        let key: () -> String? = { [weak self] in self?.apiKey(for: kind) }

        switch kind {
        case .ollama:
            return OllamaClient(endpoint: endpoint, transport: transport)
        case .anthropic:
            return AnthropicClient(endpoint: endpoint, apiKey: key, transport: transport)
        case .openAI, .openAICompatible:
            return OpenAIClient(kind: kind, endpoint: endpoint, apiKey: key, transport: transport)
        }
    }
}
