import Foundation
import Testing
@testable import Termora

/// briefs/2 "Gizlilik" + briefs/3 Settings bölüm listesi.
///
/// Gizlilik sayfasının değeri DÜRÜSTLÜĞÜNDEDİR: var olmayan bir özellik "açık/kapalı"
/// diye gösterilirse sayfa kullanıcıyı yanıltır. Bu yüzden sayfa anahtar değil METİN
/// taşır ve henüz yapılmamış olanlar ayrı bir bölümde, sebebiyle birlikte durur.
@Suite("Gizlilik sayfası içeriği")
@MainActor
struct PrivacySettingsContentTests {

    private var allStatements: [PrivacyStatement] {
        PrivacyContent.sections.flatMap(\.statements)
    }

    // MARK: - Biçim

    @Test func everySectionCarriesAtLeastOneStatement() {
        #expect(!PrivacyContent.sections.isEmpty)
        for section in PrivacyContent.sections {
            #expect(!section.title.isEmpty)
            #expect(!section.statements.isEmpty, "boş bölüm: \(section.title)")
        }
    }

    @Test func everyStatementIsAReadableSentenceWithItsOwnIdentity() {
        for statement in allStatements {
            #expect(!statement.title.isEmpty)
            #expect(!statement.symbolName.isEmpty, "simgesiz madde: \(statement.title)")
            #expect(statement.detail.count > 40, "açıklama çok kısa: \(statement.title)")
            #expect(statement.detail.hasSuffix("."), "cümle değil: \(statement.title)")
        }
        let ids = allStatements.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    // MARK: - Brief'in varsayılanları eksiksiz anlatılıyor mu

    @Test func theBriefDefaultsAreAllStatedSomewhere() {
        let text = allStatements.map { "\($0.title) \($0.detail)" }.joined(separator: " ").lowercased()
        for expected in ["account", "terminal output", "telemetry", "keychain", "ollama", "ask"] {
            #expect(text.contains(expected), "anlatılmayan varsayılan: \(expected)")
        }
    }

    /// briefs/2: "Gizlilik sayfasında hangi verinin neden işlendiği açık şekilde
    /// anlatılmalıdır" — sayfada ne saklandığını anlatan bir bölüm bulunmalı.
    @Test func thePageExplainsWhatIsStoredAndWhy() {
        let stored = PrivacyContent.storedDataSection
        #expect(!stored.statements.isEmpty)
        let text = stored.statements.map(\.detail).joined(separator: " ").lowercased()
        #expect(text.contains("this mac"))
    }

    // MARK: - Var olmayan özellik "kapalı" diye gösterilmez

    @Test func featuresThatDoNotExistYetLiveInTheirOwnSectionWithAReason() {
        let section = PrivacyContent.notBuiltYetSection
        let text = section.statements.map { "\($0.title) \($0.detail)" }.joined(separator: " ").lowercased()
        #expect(text.contains("ai"))
        #expect(text.contains("telemetry"))
        // Bölüm neden anahtar TAŞIMADIĞINI söylemeli.
        #expect(section.footer?.isEmpty == false)
        #expect((section.footer ?? "").lowercased().contains("switch"))
    }

    @Test func nothingOnThePagePromisesASwitchTheUserCannotFlip() {
        for statement in allStatements {
            let lowered = statement.title.lowercased()
            #expect(!lowered.hasPrefix("enable "), "anahtar gibi başlık: \(statement.title)")
            #expect(!lowered.hasPrefix("turn on"), "anahtar gibi başlık: \(statement.title)")
        }
    }

    // MARK: - Ayarlar sekmesi

    @Test func settingsHasAPrivacyTab() {
        #expect(SettingsTab.allCases.contains(.privacy))
        #expect(SettingsTab.privacy.title == "Privacy")
    }

    @Test func everyTabNamesItselfOnceAndCarriesASymbol() {
        let titles = SettingsTab.allCases.map(\.title)
        #expect(Set(titles).count == titles.count)
        for tab in SettingsTab.allCases {
            #expect(!tab.title.isEmpty)
            #expect(!tab.symbolName.isEmpty)
        }
    }

    /// Sekme adları briefs/2'nin "Ayarlar Ekranı" listesinden gelir; uydurma bölüm yok.
    @Test func everyTabComesFromTheBriefsSectionList() {
        let allowed: Set<String> = [
            "General", "Appearance", "Terminal", "Profiles", "Workspaces",
            "SSH", "AI", "Keybindings", "Privacy", "Updates", "About",
        ]
        for tab in SettingsTab.allCases {
            #expect(allowed.contains(tab.title), "brief'te olmayan bölüm: \(tab.title)")
        }
    }

    @Test func privacyIsTheLastTabSoTheEverydaySectionsComeFirst() {
        #expect(SettingsTab.allCases.last == .privacy)
    }
}
