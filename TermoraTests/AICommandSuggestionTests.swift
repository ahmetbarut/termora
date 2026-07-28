import Foundation
import Testing
@testable import Termora

/// briefs/2 "Komut Üretme" + "Tehlikeli Komut Koruması", briefs/3 "AI Paneli".
///
/// İki kural burada kilitleniyor:
/// 1. AI komut ÜRETİR, çalıştırmaz. `Run` bile tek başına bir niyet beyanıdır.
/// 2. Riskli komut işaretlenir ve işaret RENKTEN bağımsızdır (etiket + simge + VoiceOver).
@Suite("AI komut önerileri")
@MainActor
struct AICommandSuggestionTests {

    // MARK: - Cevaptan komut çıkarma

    @Test func aFencedShellBlockBecomesARunnableSuggestion() throws {
        let reply = """
            Use find for that:

            ```bash
            find . -name '*.log' -mtime +30
            ```

            It only lists them.
            """
        let suggestions = AIReplyParser.suggestions(in: reply)
        let first = try #require(suggestions.first)
        #expect(suggestions.count == 1)
        #expect(first.command == "find . -name '*.log' -mtime +30")
        #expect(!first.isRisky)
    }

    @Test func aFenceWithoutALanguageStillCountsAsAShellCommand() throws {
        let suggestions = AIReplyParser.suggestions(in: "```\nls -la\n```")
        #expect(try #require(suggestions.first).command == "ls -la")
    }

    @Test func everyShellDialectTheBriefNamesIsAccepted() {
        for fence in ["sh", "zsh", "bash", "shell", "console", "terminal", "fish"] {
            let suggestions = AIReplyParser.suggestions(in: "```\(fence)\nls\n```")
            #expect(suggestions.count == 1, "kabul edilmeyen kabuk: \(fence)")
        }
    }

    /// `json`, `swift`, `yaml` blokları komut DEĞİLDİR; onlara Run düğmesi vermek
    /// kullanıcıyı bir dosya içeriğini terminale yapıştırmaya davet ederdi.
    @Test func aBlockInAnotherLanguageNeverGetsRunButtons() {
        #expect(AIReplyParser.suggestions(in: "```json\n{\"a\":1}\n```").isEmpty)
        #expect(AIReplyParser.suggestions(in: "```swift\nlet a = 1\n```").isEmpty)
    }

    @Test func severalBlocksBecomeSeveralSuggestionsInReplyOrder() {
        let reply = "first\n```sh\ngit status\n```\nthen\n```sh\ngit pull\n```"
        #expect(AIReplyParser.suggestions(in: reply).map(\.command) == ["git status", "git pull"])
    }

    @Test func anUnterminatedFenceIsIgnoredRatherThanSwallowingTheRestOfTheReply() {
        #expect(AIReplyParser.suggestions(in: "here you go:\n```sh\nrm -rf /").isEmpty)
    }

    @Test func anEmptyBlockProducesNothing() {
        #expect(AIReplyParser.suggestions(in: "```sh\n\n```").isEmpty)
    }

    /// Bir blokta birden çok satır varsa öneri BÜTÜN bloktur: satırlara bölmek
    /// birbirine bağlı adımları (cd + build) yanlış sırada çalıştırma daveti olurdu.
    @Test func aMultiLineBlockStaysOneSuggestion() throws {
        let suggestions = AIReplyParser.suggestions(in: "```sh\ncd build\nmake clean\n```")
        let first = try #require(suggestions.first)
        #expect(suggestions.count == 1)
        #expect(first.command == "cd build\nmake clean")
    }

    /// Çok satırlı blok terminale olduğu gibi yazılsaydı aradaki her satır sonu birer
    /// "çalıştır" olurdu — Insert sessizce Run'a dönüşürdü.
    @Test func aMultiLineSuggestionBecomesOneLineBeforeItTouchesTheTerminal() throws {
        let suggestions = AIReplyParser.suggestions(in: "```sh\ncd build\nmake clean\n```")
        let first = try #require(suggestions.first)
        #expect(first.terminalText == "cd build; make clean")
    }

    @Test func aSingleLineSuggestionIsTypedExactlyAsWritten() throws {
        let suggestions = AIReplyParser.suggestions(in: "```sh\nls -la\n```")
        #expect(try #require(suggestions.first).terminalText == "ls -la")
    }

    /// Kullanıcı onay penceresinde OKUDUĞU metni onaylar: gösterilen satır, terminale
    /// düşecek satırın aynısıdır.
    @Test func theConfirmationShowsTheLineThatWillActuallyBeTyped() {
        let message = AIRunPrompt.message(for: "cd build\nmake clean")
        #expect(message.contains("cd build; make clean"))
    }

    // MARK: - Riskli komut (briefs/2)

    @Test func aDestructiveSuggestionIsMarkedWithItsReason() throws {
        let suggestions = AIReplyParser.suggestions(in: "```sh\nrm -rf /\n```")
        let first = try #require(suggestions.first)
        #expect(first.isRisky)
        let warning = try #require(first.warning)
        #expect(warning.risk == .high)
        #expect(!warning.message.isEmpty)
    }

    /// Çok satırlı blokta EN AĞIR satır kazanır; zararsız ilk satır uyarıyı gizleyemez.
    @Test func theWorstLineOfAMultiLineBlockDecidesTheRisk() throws {
        let suggestions = AIReplyParser.suggestions(in: "```sh\necho hello\nrm -rf /\n```")
        let suggestion = try #require(suggestions.first)
        let warning = try #require(suggestion.warning)
        #expect(warning.risk == .high)
    }

    @Test func anEverydayCommandIsNotDressedUpAsDangerous() {
        let suggestions = AIReplyParser.suggestions(in: "```sh\nrm -rf build\n```")
        #expect(suggestions.first?.isRisky == false)
    }

    /// Uyarı YALNIZ renkle anlatılmaz: etiket, simge ve VoiceOver cümlesi de var.
    @Test func theRiskIsReadableWithoutSeeingAnyColour() throws {
        let suggestion = try #require(AIReplyParser.suggestions(in: "```sh\nrm -rf /\n```").first)
        #expect(suggestion.riskLabel == "High risk")
        #expect(suggestion.riskSymbolName == CommandRisk.high.symbolName)
        let spoken = try #require(suggestion.riskAccessibilityLabel)
        #expect(spoken.lowercased().contains("high risk"))
        #expect(spoken.contains(".") )
    }

    @Test func aSafeSuggestionHasNoRiskLabelToRead() {
        let suggestion = AIReplyParser.suggestions(in: "```sh\nls\n```").first
        #expect(suggestion?.riskLabel == nil)
        #expect(suggestion?.riskAccessibilityLabel == nil)
    }

    // MARK: - Eylemler (briefs/3 "AI Paneli")

    @Test func theActionsAreExactlyTheFourTheBriefLists() {
        #expect(AICommandAction.allCases.map(\.title) == ["Copy", "Insert", "Explain", "Run"])
    }

    /// briefs/3: "`Run` işlemi kullanıcı onayı olmadan çalışmamalıdır."
    @Test func runIsTheOnlyActionThatNeedsConfirmation() {
        for action in AICommandAction.allCases {
            #expect(action.needsConfirmation == (action == .run), "yanlış onay kuralı: \(action.title)")
        }
    }

    @Test func everyActionCarriesASymbolAndASpokenLabel() {
        for action in AICommandAction.allCases {
            #expect(!action.symbolName.isEmpty)
            #expect(action.accessibilityLabel.count > action.title.count,
                    "VoiceOver etiketi başlığın kopyası: \(action.title)")
        }
    }

    // MARK: - Onay metni

    @Test func theConfirmationNamesTheActionInsteadOfSayingOK() {
        #expect(AIRunPrompt.confirmTitle == "Run Command")
        #expect(AIRunPrompt.cancelTitle == "Cancel")
        #expect(!AIRunPrompt.allButtonTitles.contains { ["OK", "Yes", "Continue"].contains($0) })
    }

    @Test func theConfirmationShowsTheCommandItIsAboutToRun() {
        let message = AIRunPrompt.message(for: "ls -la")
        #expect(message.contains("ls -la"))
    }

    /// Riskli komutta onay metni sonucu da söyler — kullanıcı ne kaybedeceğini bilerek onaylar.
    @Test func aRiskyConfirmationSpellsOutWhatWillBeLost() throws {
        let message = AIRunPrompt.message(for: "rm -rf /")
        let warning = try #require(DangerousCommand.inspect("rm -rf /"))
        #expect(message.contains(warning.message))
        #expect(message.contains(AIRunPrompt.riskMarker))
    }

    // MARK: - Konuşma

    @Test func aFreshConversationHasAnHonestPlaceholderTitle() {
        #expect(AIConversation().title == AIConversation.untitled)
        #expect(AIConversation().messages.isEmpty)
    }

    @Test func theFirstQuestionBecomesTheConversationTitle() {
        var conversation = AIConversation()
        conversation.append(AIMessage(role: .user, text: "list log files older than 30 days"))
        #expect(conversation.title == "list log files older than 30 days")
    }

    @Test func aVeryLongFirstQuestionIsTrimmedInsteadOfStretchingThePanel() {
        var conversation = AIConversation()
        conversation.append(AIMessage(role: .user, text: String(repeating: "a", count: 200)))
        #expect(conversation.title.count <= AIConversation.titleLimit + 1)
        #expect(conversation.title.hasSuffix("…"))
    }

    @Test func laterQuestionsDoNotRenameTheConversation() {
        var conversation = AIConversation()
        conversation.append(AIMessage(role: .user, text: "first"))
        conversation.append(AIMessage(role: .assistant, text: "answer"))
        conversation.append(AIMessage(role: .user, text: "second"))
        #expect(conversation.title == "first")
    }

    @Test func historyForTheNextRequestLeavesOutTheSystemRole() {
        var conversation = AIConversation()
        conversation.append(AIMessage(role: .user, text: "one"))
        conversation.append(AIMessage(role: .assistant, text: "two"))
        #expect(conversation.history.map(\.role) == [.user, .assistant])
    }
}
