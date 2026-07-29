import Foundation
import Testing
@testable import Termora

/// Sağlayıcı seçimi ayardan gelir ve ÇALIŞMA ANINDA değişir. Panel, katalog ve komut
/// paleti tek bir `AIProviding` referansı tutar; onları yeniden kurmak yerine
/// yönlendirici seçili sağlayıcıya delege eder.
@MainActor
@Suite("AI sağlayıcı yönlendirici")
struct AIProviderRouterTests {

    private func makeSettings() -> SettingsStore {
        let suite = "termora.router.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(defaults: defaults)
    }

    @Test func theDefaultProviderIsTheLocalOne() {
        // briefs/2 "Gizlilik": yerel Ollama desteklenir ve varsayılandır — yeni kullanıcı
        // hiçbir anahtar girmeden, hiçbir veri dışarı çıkmadan başlar.
        #expect(AppSettings().aiProviderKind == .ollama)
    }

    @Test func theRouterFollowsTheSettingWithoutBeingRebuilt() {
        let settings = makeSettings()
        let router = AIProviderRouter(settings: settings, keychain: KeychainService(),
                                      transport: FakeAIHTTPTransport())

        #expect(router.kind == .ollama)
        settings.settings.aiProviderKind = .anthropic
        #expect(router.kind == .anthropic)
    }

    /// Her sağlayıcı kendi adresini hatırlar: OpenAI'ye geçip geri dönen kullanıcı
    /// Ollama adresini yeniden yazmak zorunda kalmamalı.
    @Test func eachProviderKeepsItsOwnEndpoint() {
        var settings = AppSettings()
        settings.aiEndpoint(for: .ollama, is: "http://localhost:11434")
        settings.aiEndpoint(for: .openAI, is: "https://api.openai.com/v1")

        #expect(settings.aiEndpoint(for: .ollama) == "http://localhost:11434")
        #expect(settings.aiEndpoint(for: .openAI) == "https://api.openai.com/v1")
    }

    /// Kullanıcı adres girmediyse sağlayıcının resmî adresi kullanılır — boş adresle
    /// istek kurup "geçersiz adres" hatası göstermek gereksiz bir tur olurdu.
    @Test func anUnsetEndpointFallsBackToTheProvidersDefault() {
        let settings = AppSettings()
        #expect(settings.aiEndpoint(for: .anthropic) == "https://api.anthropic.com/v1")
        #expect(settings.aiEndpoint(for: .ollama) == OllamaEndpoint.defaultAddress)
        // Özel adresli sağlayıcının varsayılanı yoktur: adres kullanıcıdan gelir.
        #expect(settings.aiEndpoint(for: .openAICompatible).isEmpty)
    }

    @Test func eachProviderKeepsItsOwnSelectedModel() {
        var settings = AppSettings()
        settings.aiModel(for: .ollama, is: "llama3.2")
        settings.aiModel(for: .anthropic, is: "claude-opus-5")

        #expect(settings.aiModel(for: .ollama) == "llama3.2")
        #expect(settings.aiModel(for: .anthropic) == "claude-opus-5")
        #expect(settings.aiModel(for: .openAI) == nil)
    }

    /// Tek sağlayıcılı sürümden gelen kullanıcının adresi ve modeli KAYBOLMAMALI:
    /// eski alanlar Ollama'nın kaydı sayılır. Aksi hâlde güncelleme, kullanıcının
    /// ayarını sessizce sıfırlardı.
    @Test func settingsFromTheSingleProviderVersionMigrateToOllama() throws {
        let legacy = Data("""
            {"aiEndpoint":"http://192.168.1.9:11434","aiModel":"llama3.2"}
            """.utf8)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacy)

        #expect(decoded.aiProviderKind == .ollama)
        #expect(decoded.aiEndpoint(for: .ollama) == "http://192.168.1.9:11434")
        #expect(decoded.aiModel(for: .ollama) == "llama3.2")
    }

    /// Göç YALNIZ boşluğu doldurur: sağlayıcı başına kayıt varsa eski alan onu ezmez.
    @Test func theMigrationDoesNotOverwriteNewerPerProviderValues() throws {
        let mixed = Data("""
            {"aiEndpoint":"http://old","aiEndpointsByProvider":{"ollama":"http://new"}}
            """.utf8)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: mixed)

        #expect(decoded.aiEndpoint(for: .ollama) == "http://new")
    }

    /// briefs/1 "Güvenlik": anahtar Keychain'den okunur, ayar dosyasından DEĞİL.
    /// Ayarlar diske düz JSON olarak yazılır; anahtarın oraya düşmesi sızıntı olurdu.
    @Test func theRouterReadsKeysFromTheKeychainNotFromSettings() throws {
        let settings = makeSettings()
        let keychain = KeychainService(service: "termora.router.test.\(UUID().uuidString)")
        let account = try #require(AIProviderKind.anthropic.keychainAccount)
        defer { try? keychain.removeSecret(account: account) }

        try keychain.setSecret("sk-ant-secret", account: account)
        let router = AIProviderRouter(settings: settings, keychain: keychain,
                                      transport: FakeAIHTTPTransport())

        #expect(router.apiKey(for: .anthropic) == "sk-ant-secret")
        #expect(router.apiKey(for: .openAI) == nil)
        // Anahtar hiçbir ayar alanında görünmemeli.
        let encoded = try JSONEncoder().encode(settings.settings)
        #expect(String(decoding: encoded, as: UTF8.self).contains("sk-ant-secret") == false)
    }
}
