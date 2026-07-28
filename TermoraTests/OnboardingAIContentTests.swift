import Foundation
import Testing
@testable import Termora

/// briefs/2 Onboarding "Adım 3 — İsteğe Bağlı Özellikler": AI sağlayıcısı bağlantısı.
///
/// Kural briefs/3'ten geliyor: "AI kurulumu ilk açılış için zorunlu olmamalıdır."
/// Bu yüzden ekran bir KURULUM ADIMI değil, bir DURUM satırıdır: ne bulunduğunu söyler,
/// bulunmadıysa uygulamanın yine de çalıştığını söyler ve hiçbir şey beklemez.
@Suite("Onboarding AI satırı")
struct OnboardingAIContentTests {

    private let provider = "Ollama"

    private func allSummaries() -> [String] {
        [
            OnboardingAIContent.summary(for: .idle, providerName: provider),
            OnboardingAIContent.summary(for: .loading, providerName: provider),
            OnboardingAIContent.summary(for: .ready([AIModel(name: "llama3.2", sizeBytes: nil)]),
                                        providerName: provider),
            OnboardingAIContent.summary(for: .ready([]), providerName: provider),
            OnboardingAIContent.summary(for: .unavailable(.endpointUnreachable(endpoint: "http://localhost:11434")),
                                        providerName: provider),
            OnboardingAIContent.summary(for: .unavailable(.noModelsInstalled(endpoint: "http://localhost:11434")),
                                        providerName: provider),
        ]
    }

    // MARK: - Zorunlu olmama

    /// Brief'in tek sert kuralı: ilk açılışta AI kurulumu ZORUNLU değildir. Satır bunu
    /// kullanıcıya da söyler — yoksa boş bir "bağlan" satırı bir engel gibi okunur.
    @Test func theRowSaysItIsOptionalAndWhereToDoItLater() {
        #expect(OnboardingAIContent.optionalNote.lowercased().contains("optional"))
        #expect(OnboardingAIContent.optionalNote.contains("Settings"))
    }

    @Test func theRowHasATitle() {
        #expect(!OnboardingAIContent.title.isEmpty)
    }

    // MARK: - Her durum bitmiş bir cümle

    /// Hiçbir durum boş kutu bırakmaz; hepsi noktayla biten bir cümledir
    /// (briefs/3 "Uygulama Metin Dili").
    @Test func everyStateProducesAFinishedSentence() {
        for summary in allSummaries() {
            #expect(!summary.isEmpty)
            #expect(summary.hasSuffix(".") || summary.hasSuffix("…"),
                    "bitmemiş cümle: \(summary)")
        }
    }

    /// Bekleme durumu başarı da başarısızlık da İDDİA ETMEZ; onboarding bir cevabı
    /// beklemek zorunda kalmasın diye bu durum ekranda görünebilir olmalı.
    @Test func whileCheckingItClaimsNeitherSuccessNorFailure() {
        let checking = OnboardingAIContent.summary(for: .loading, providerName: provider)
        #expect(checking.lowercased().contains("check"))
        #expect(!checking.lowercased().contains("ready"))
    }

    // MARK: - Bulunduğunda

    @Test func aReadyProviderIsNamedWithHowManyModelsAreInstalled() {
        let one = OnboardingAIContent.summary(for: .ready([AIModel(name: "llama3.2", sizeBytes: nil)]),
                                              providerName: provider)
        #expect(one.contains("Ollama"))
        #expect(one.contains("1 model"))
        #expect(!one.contains("1 models"))

        let two = OnboardingAIContent.summary(for: .ready([AIModel(name: "a", sizeBytes: nil),
                                                           AIModel(name: "b", sizeBytes: nil)]),
                                              providerName: provider)
        #expect(two.contains("2 models"))
    }

    /// `ready` ama liste BOŞ: sağlayıcı ayakta, indirilmiş model yok. "Hazır" demek yalan
    /// olurdu — soru sorulacak bir model yok.
    @Test func aRunningProviderWithNoModelsIsNotCalledReady() {
        let empty = OnboardingAIContent.summary(for: .ready([]), providerName: provider)
        #expect(empty.lowercased().contains("no model"))
    }

    // MARK: - Bulunamadığında

    /// Sağlayıcı yoksa satır SUÇLAMAZ ve engel çıkarmaz: uygulamanın çalıştığını söyler.
    @Test func anUnreachableProviderStillSaysTermoraWorks() {
        let missing = OnboardingAIContent.summary(for: .unavailable(.endpointUnreachable(endpoint: "http://localhost:11434")),
                                                  providerName: provider)
        #expect(missing.contains("Ollama"))
        #expect(missing.lowercased().contains("without it"))
    }

    /// Sağlayıcı ayakta ama model yoksa çözüm KOMUTLA söylenir — panelin ve Ayarlar'ın
    /// kullandığı cümlenin aynısı.
    @Test func noModelsInstalledNamesTheCommandThatFixesIt() {
        let none = OnboardingAIContent.summary(for: .unavailable(.noModelsInstalled(endpoint: "http://localhost:11434")),
                                               providerName: provider)
        #expect(none.contains("ollama pull"))
    }
}
