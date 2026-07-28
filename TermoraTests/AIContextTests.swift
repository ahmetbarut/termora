import Foundation
import Testing
@testable import Termora

/// briefs/2 "Terminal Bağlamı" + "Secret Maskeleme".
///
/// Bu paketin işi TEK bir cümleyi kanıtlamaktır: **maskelenmemiş metin AI istemcisine
/// ULAŞAMAZ.** Kanıt bir sözleşme testinden ibaret değildir — `MaskedPayload`'ın
/// başlatıcısı özeldir ve tek giriş kapısı `SecretMasker`'dır, bu yüzden ihlal
/// derlenmez. Testler o kapının açık kaldığını doğrular.
@Suite("AI bağlamı ve maskeleme sınırı")
@MainActor
struct AIContextTests {

    private let placeholder = SecretMasker.placeholder

    // MARK: - Hangi bağlamlar var

    /// briefs/2'nin saydığı bağlamlar; "tüm terminal geçmişi" LİSTEDE YOKTUR.
    @Test func theContextKindsAreExactlyTheOnesTheBriefLists() {
        #expect(AIContextKind.allCases == [
            .selectedCommand, .selectedOutput, .workingDirectory,
            .operatingSystem, .shell, .gitBranch,
        ])
    }

    @Test func everyContextKindNamesItselfAndSaysWhyItWouldBeSent() {
        for kind in AIContextKind.allCases {
            #expect(!kind.title.isEmpty)
            #expect(kind.purpose.count > 20, "gerekçesiz bağlam: \(kind.title)")
            #expect(kind.purpose.hasSuffix("."), "cümle değil: \(kind.title)")
        }
        let titles = AIContextKind.allCases.map(\.title)
        #expect(Set(titles).count == titles.count)
    }

    // MARK: - Varsayılanlar

    /// briefs/2: "Tüm terminal geçmişi varsayılan olarak AI'a gönderilmemelidir."
    /// Termora bunu bir anahtarla değil, YOKLUKLA garanti eder: geçmişi toplayan bir
    /// bağlam türü hiç yoktur.
    @Test func thereIsNoWayToAskForTheWholeScrollback() {
        let names = AIContextKind.allCases.map { $0.rawValue.lowercased() }
        for forbidden in ["scrollback", "history", "buffer", "everything"] {
            #expect(!names.contains { $0.contains(forbidden) },
                    "geçmişi gönderen bağlam türü eklenmiş: \(forbidden)")
        }
    }

    @Test func selectionIsOptInSizedButEnvironmentFactsComeAlongByDefault() {
        let defaults = AIContextPreferences()
        // Seçim kullanıcının kendi eylemidir: seçtiyse gönderilsin.
        #expect(defaults.includes(.selectedCommand))
        #expect(defaults.includes(.selectedOutput))
        // Ortam bilgisi tek satırlıktır ve cevabın doğruluğunu belirler.
        #expect(defaults.includes(.workingDirectory))
        #expect(defaults.includes(.operatingSystem))
        #expect(defaults.includes(.shell))
        #expect(defaults.includes(.gitBranch))
    }

    @Test func turningAKindOffKeepsItOutOfThePreparedContext() {
        var preferences = AIContextPreferences()
        preferences.setIncludes(.workingDirectory, false)
        #expect(!preferences.includes(.workingDirectory))

        let snapshot = AIContextSnapshot([
            .workingDirectory: "/Users/dev/pinro",
            .shell: "zsh",
        ])
        let prepared = AIContextBuilder.prepare(snapshot, preferences: preferences)
        #expect(prepared.entries.map(\.kind) == [.shell])
        #expect(!prepared.previewText.contains("/Users/dev/pinro"))
    }

    @Test func aKindWithNothingToSayIsNotSentAsAnEmptyLine() {
        let snapshot = AIContextSnapshot([.workingDirectory: "   ", .shell: "zsh"])
        let prepared = AIContextBuilder.prepare(snapshot, preferences: AIContextPreferences())
        #expect(prepared.entries.map(\.kind) == [.shell])
    }

    /// ⌘A bütün scrollback'i seçer. Sınır olmasaydı brief'in "tüm geçmiş gönderilmez"
    /// yasağı TEK kısayolla delinirdi; bu yüzden kesme güvenlik sınırında yapılır.
    @Test func aHugeSelectionIsCutDownBeforeItCanBecomeTheWholeHistory() throws {
        let huge = String(repeating: "x", count: AIContextBuilder.selectionCharacterLimit * 3)
        let snapshot = AIContextSnapshot([.selectedOutput: huge])
        let prepared = AIContextBuilder.prepare(snapshot, preferences: AIContextPreferences())
        let entry = try #require(prepared.entries.first)
        #expect(entry.value.count < huge.count)
        #expect(entry.value.contains(AIContextBuilder.truncationMarker))
    }

    /// Sondan kesilir: bir komut başarısız olduğunda anlamlı satırlar SONDADIR.
    @Test func truncationKeepsTheEndWhereTheErrorLives() throws {
        let filler = String(repeating: "a\n", count: AIContextBuilder.selectionCharacterLimit)
        let snapshot = AIContextSnapshot([.selectedOutput: filler + "fatal: permission denied"])
        let prepared = AIContextBuilder.prepare(snapshot, preferences: AIContextPreferences())
        let entry = try #require(prepared.entries.first)
        #expect(entry.value.hasSuffix("fatal: permission denied"))
    }

    @Test func aSelectionThatFitsIsSentUntouched() throws {
        let snapshot = AIContextSnapshot([.selectedOutput: "fatal: not a git repository"])
        let prepared = AIContextBuilder.prepare(snapshot, preferences: AIContextPreferences())
        let entry = try #require(prepared.entries.first)
        #expect(entry.value == "fatal: not a git repository")
    }

    @Test func preferencesSurviveAFutureVersionThatAddedMoreKeys() throws {
        let future = Data(#"{"includesShell":false,"includesTelepathy":true}"#.utf8)
        let decoded = try JSONDecoder().decode(AIContextPreferences.self, from: future)
        #expect(!decoded.includes(.shell))
        // Eksik anahtarlar varsayılana düşer, TÜM blob çöpe gitmez.
        #expect(decoded.includes(.workingDirectory))
    }

    @Test func preferencesRoundTrip() throws {
        var preferences = AIContextPreferences()
        preferences.setIncludes(.selectedOutput, false)
        preferences.setIncludes(.gitBranch, false)
        let data = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(AIContextPreferences.self, from: data)
        #expect(decoded == preferences)
    }

    // MARK: - Maskeleme sınırı (briefs/2'nin kritik maddesi)

    @Test func contextValuesAreMaskedBeforeTheyEverBecomeAnEntry() throws {
        let snapshot = AIContextSnapshot([
            .selectedOutput: "Authorization: Bearer sk-proj-1234567890",
        ])
        let prepared = AIContextBuilder.prepare(snapshot, preferences: AIContextPreferences())
        let entry = try #require(prepared.entries.first)
        #expect(entry.value.contains(placeholder))
        #expect(!entry.value.contains("sk-proj-1234567890"))
        #expect(!prepared.previewText.contains("sk-proj-1234567890"))
    }

    /// Kullanıcının kendi yazdığı istem de dışarı giden metindir; orada da sır olabilir.
    @Test func theUsersOwnPromptIsMaskedToo() {
        let request = AIRequestBuilder.build(
            model: "llama3.2",
            prompt: "why does AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMIabcdEFGHijkLMNoPQRstuVWxyz1 fail?",
            context: PreparedAIContext.empty,
            history: []
        )
        #expect(!request.outgoingTexts.contains { $0.contains("wJalrXUtnFEMIabcdEFGHijkLMNoPQRstuVWxyz1") })
        #expect(request.outgoingTexts.contains { $0.contains(placeholder) })
    }

    /// Sözleşmenin kendisi: istekteki HİÇBİR metin parçasında ham sır bulunamaz.
    @Test func noPieceOfAnOutgoingRequestCanCarryAnUnmaskedSecret() {
        let secret = "ghp_abcdefghijklmnopqrstuvwxyz0123456789"
        let snapshot = AIContextSnapshot([
            .selectedCommand: "git push https://user:hunter2@example.com/repo.git",
            .selectedOutput: "remote: token \(secret) rejected",
            .workingDirectory: "/Users/dev/pinro",
        ])
        let prepared = AIContextBuilder.prepare(snapshot, preferences: AIContextPreferences())
        let request = AIRequestBuilder.build(
            model: "llama3.2",
            prompt: "explain this",
            context: prepared,
            history: [AIMessage(role: .assistant, text: "earlier reply mentioning \(secret)")]
        )

        for text in request.outgoingTexts {
            #expect(!text.contains(secret), "istek ham sır taşıyor: \(text)")
            #expect(!text.contains("hunter2"), "istek ham parola taşıyor: \(text)")
        }
    }

    /// Kullanıcı NE saklandığını görebilmeli (briefs/2: "maskelenen şeyler özetlenmeli").
    @Test func thePreparedContextSummarisesWhatItHid() {
        let snapshot = AIContextSnapshot([.selectedOutput: "API_TOKEN=abc123def456"])
        let prepared = AIContextBuilder.prepare(snapshot, preferences: AIContextPreferences())
        #expect(prepared.didFindSecrets)
        #expect(prepared.maskingSummary.contains("hidden"))
    }

    @Test func aCleanContextSaysSoInsteadOfStayingSilent() {
        let snapshot = AIContextSnapshot([.shell: "zsh"])
        let prepared = AIContextBuilder.prepare(snapshot, preferences: AIContextPreferences())
        #expect(!prepared.didFindSecrets)
        #expect(prepared.maskingSummary == SecretMasker.noSecretsSummary)
    }

    // MARK: - Gönderilecek son içerik incelenebilir

    /// briefs/2: "Kullanıcı gönderilecek son içeriği AI isteğinden önce inceleyebilmelidir."
    /// Önizleme metni SÜSLEME değildir: isteğin içine giren metnin BİREBİR aynısıdır.
    @Test func thePreviewIsTheExactTextThatGoesIntoTheRequest() throws {
        let snapshot = AIContextSnapshot([
            .workingDirectory: "/Users/dev/pinro",
            .shell: "zsh",
            .gitBranch: "main",
        ])
        let prepared = AIContextBuilder.prepare(snapshot, preferences: AIContextPreferences())
        let request = AIRequestBuilder.build(model: "llama3.2",
                                             prompt: "list old logs",
                                             context: prepared,
                                             history: [])
        let contextMessage = try #require(
            request.messages.first { $0.content.text.contains(prepared.previewText) }
        )
        #expect(contextMessage.content.text.contains("/Users/dev/pinro"))
        #expect(prepared.previewText.contains(AIContextKind.gitBranch.title))
    }

    @Test func anEmptyContextProducesNoContextMessageAtAll() {
        let request = AIRequestBuilder.build(model: "llama3.2",
                                             prompt: "hello",
                                             context: PreparedAIContext.empty,
                                             history: [])
        #expect(request.messages.filter { $0.role == .system }.count == 1)
        #expect(PreparedAIContext.empty.isEmpty)
    }

    @Test func historyIsSentOldestFirstAndThePromptComesLast() throws {
        let history = [
            AIMessage(role: .user, text: "first question"),
            AIMessage(role: .assistant, text: "first answer"),
        ]
        let request = AIRequestBuilder.build(model: "llama3.2",
                                             prompt: "second question",
                                             context: PreparedAIContext.empty,
                                             history: history)
        let roles = request.messages.map(\.role)
        #expect(roles == [.system, .user, .assistant, .user])
        let last = try #require(request.messages.last)
        #expect(last.content.text == "second question")
    }
}
