import Foundation
import Testing
@testable import Termora

/// briefs/2 "Ayarlar Ekranı" + "Gizlilik", briefs/3 Settings bölüm listesi.
///
/// Gizlilik sayfasının değeri DÜRÜSTLÜĞÜNDEYDİ: var olmayan bir özellik "kapalı" diye
/// gösterilmiyordu. Artık AI VAR — o hâlde sayfanın "AI bağlı değil" demesi de aynı
/// ölçüde yanlış. Bu paket sayfayı gerçeğe bağlı tutar.
@Suite("AI ayarları ve gizlilik sayfasının gerçeğe uyması")
@MainActor
struct AISettingsContentTests {

    private var allStatements: [PrivacyStatement] {
        PrivacyContent.sections.flatMap(\.statements)
    }

    private var pageText: String {
        allStatements.map { "\($0.title) \($0.detail)" }.joined(separator: " ").lowercased()
    }

    // MARK: - Ayarlar sekmesi

    @Test func settingsHasAnAITab() {
        #expect(SettingsTab.allCases.contains(.ai))
        #expect(SettingsTab.ai.title == "AI")
        #expect(!SettingsTab.ai.symbolName.isEmpty)
    }

    /// briefs/2'nin listesindeki sıra: … SSH, AI, Keybindings, Privacy …
    @Test func theAITabSitsBetweenSSHAndPrivacy() throws {
        let order = SettingsTab.allCases
        let ssh = try #require(order.firstIndex(of: .ssh))
        let ai = try #require(order.firstIndex(of: .ai))
        let privacy = try #require(order.firstIndex(of: .privacy))
        #expect(ssh < ai)
        #expect(ai < privacy)
    }

    // MARK: - Gizlilik sayfası artık AI'ı YOK saymıyor

    @Test func thePageNoLongerClaimsTheAssistantIsMissing() {
        #expect(!pageText.contains("not connected"))
        #expect(!pageText.contains("no ai provider ships"))
        #expect(!PrivacyContent.notBuiltYetSection.statements.contains { $0.id == "no-ai" })
    }

    /// briefs/2 "Gizlilik": "AI yalnızca kullanıcı isteğiyle çağrılır."
    @Test func thePageSaysTheAssistantOnlyRunsWhenAsked() throws {
        let statement = try #require(
            PrivacyContent.defaultsSection.statements.first { $0.id == "ai-on-request" }
        )
        let text = "\(statement.title) \(statement.detail)".lowercased()
        #expect(text.contains("ollama"))
        #expect(text.contains("ask"))
        #expect(text.contains("this mac") || text.contains("local"))
    }

    /// briefs/2: "Gönderilecek AI bağlamı kullanıcıya gösterilir."
    @Test func thePageSaysTheContextIsShownBeforeItIsSent() {
        #expect(pageText.contains("before it is sent") || pageText.contains("before sending"))
    }

    /// Keychain maddesi hâlâ var ama artık bir SÖZ değil, bir GEREKÇE: Ollama yerel
    /// çalışır ve anahtar istemez, bu yüzden Termora hiçbir anahtar saklamaz.
    @Test func theKeychainStatementExplainsWhyThereIsNoKeyToStore() throws {
        let statement = try #require(allStatements.first { $0.id == "keychain" })
        let text = "\(statement.title) \(statement.detail)".lowercased()
        #expect(text.contains("keychain"))
        #expect(text.contains("ollama"))
        #expect(text.contains("no api key") || text.contains("no keys"))
    }

    /// Sayfa ne SAKLADIĞINI da güncellemeli: adres ve model kalıcı, konuşma değil.
    @Test func thePageSaysWhatTheAssistantStoresAndWhatItDoesNot() throws {
        let statement = try #require(
            PrivacyContent.storedDataSection.statements.first { $0.id == "stored-ai" }
        )
        let text = statement.detail.lowercased()
        #expect(text.contains("address") || text.contains("model"))
        #expect(text.contains("conversation"))
    }

    /// "Not built yet" bölümü boşalmadı: bulut sağlayıcılar ve telemetri hâlâ yok.
    @Test func whatIsStillMissingKeepsItsOwnHonestSection() {
        let section = PrivacyContent.notBuiltYetSection
        let text = section.statements.map { "\($0.title) \($0.detail)" }.joined(separator: " ").lowercased()
        #expect(text.contains("telemetry"))
        #expect(text.contains("cloud"))
        #expect(section.footer?.isEmpty == false)
    }

    // MARK: - AI ayar sayfasının metinleri

    @Test func theSettingsPageSaysWhyNoAPIKeyIsAsked() {
        let text = AISettingsContent.providerFooter.lowercased()
        #expect(text.contains("api key") || text.contains("key"))
        #expect(text.contains("ollama"))
        #expect(AISettingsContent.providerFooter.hasSuffix("."))
    }

    /// briefs/2: "Tüm terminal geçmişi varsayılan olarak AI'a gönderilmemelidir."
    /// Ayar sayfası bunu açıkça söylemeli; kullanıcı bir anahtar aramamalı.
    @Test func theContextSectionSaysTheWholeHistoryIsNeverSent() {
        let text = AISettingsContent.contextFooter.lowercased()
        #expect(text.contains("history") || text.contains("scrollback"))
        #expect(text.contains("never"))
        #expect(AISettingsContent.contextFooter.hasSuffix("."))
    }

    @Test func everySettingsStringIsAFinishedSentence() {
        for text in AISettingsContent.allProse {
            #expect(!text.isEmpty)
            #expect(text.hasSuffix("."), "cümle değil: \(text)")
        }
    }
}
