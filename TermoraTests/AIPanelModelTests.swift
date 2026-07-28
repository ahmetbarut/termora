import Foundation
import Testing
@testable import Termora

// MARK: - Sahte bağımlılıklar

/// Sahte sağlayıcı. Hiçbir test ağa çıkmaz.
@MainActor
final class FakeAIProvider: AIProviding {
    let kind: AIProviderKind = .ollama
    var endpointDescription = "http://localhost:11434"

    var modelsResult: Result<[AIModel], any Error> = .success([AIModel(name: "llama3.2", sizeBytes: nil)])
    var replyResult: Result<AIReply, any Error> = .success(AIReply(text: "ok"))

    private(set) var requests: [AIRequest] = []
    private(set) var modelQueries = 0

    func availableModels() async throws -> [AIModel] {
        modelQueries += 1
        return try modelsResult.get()
    }

    func complete(_ request: AIRequest) async throws -> AIReply {
        requests.append(request)
        return try replyResult.get()
    }
}

/// Sahte terminal köprüsü: NE eklendiğini ve NE çalıştırıldığını kaydeder.
@MainActor
final class FakeAITerminalBridge: AITerminalBridging {
    var snapshot = AIContextSnapshot()
    private(set) var inserted: [String] = []
    private(set) var ran: [String] = []

    func captureContext() -> AIContextSnapshot { snapshot }
    func insert(_ text: String) { inserted.append(text) }
    func run(_ command: String) { ran.append(command) }
}

// MARK: - Testler

/// briefs/3 "AI Paneli" + briefs/2 "AI Asistanı".
///
/// Panelin sözü şudur: hiçbir şey kullanıcı istemeden olmaz ve hiçbir durum belirsiz
/// bırakılmaz. Sonsuz spinner ve boş açılır liste bu paketin kırdığı iki şeydir.
@Suite("AI paneli modeli")
@MainActor
struct AIPanelModelTests {

    private func makeSettings() -> (SettingsStore, String) {
        let suiteName = "AIPanelModelTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return (SettingsStore(defaults: .standard), suiteName)
        }
        return (SettingsStore(defaults: defaults), suiteName)
    }

    /// `@MainActor` bir tipin varsayılan argüman ifadesi NONISOLATED bağlamda değerlendirilir
    /// ve derlenmez; bu yüzden varsayılanlar `nil` ve gövdede kuruluyor.
    private func makeModel(provider: FakeAIProvider? = nil,
                           bridge: FakeAITerminalBridge? = nil)
        -> (AIPanelModel, FakeAIProvider, FakeAITerminalBridge, String) {
        let provider = provider ?? FakeAIProvider()
        let bridge = bridge ?? FakeAITerminalBridge()
        let (settings, suiteName) = makeSettings()
        let model = AIPanelModel(provider: provider, settings: settings)
        model.bridge = bridge
        return (model, provider, bridge, suiteName)
    }

    private func clean(_ suiteName: String) {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    // MARK: - Model listesi durumları

    @Test func thePanelStartsWithoutHavingAskedAnything() {
        let (model, provider, _, suite) = makeModel()
        defer { clean(suite) }
        #expect(model.availability == .idle)
        #expect(provider.modelQueries == 0, "panel açılmadan sunucuya soruldu")
    }

    @Test func refreshingEndsInATerminalStateSoTheSpinnerCannotRunForever() async {
        let (model, _, _, suite) = makeModel()
        defer { clean(suite) }
        await model.refreshModels()
        #expect(model.availability != .loading)
        #expect(model.availability != .idle)
    }

    @Test func aReadyProviderFillsTheModelPickerAndPicksTheFirstModel() async {
        let provider = FakeAIProvider()
        provider.modelsResult = .success([AIModel(name: "llama3.2", sizeBytes: 2_000_000_000),
                                          AIModel(name: "qwen2.5-coder:7b", sizeBytes: nil)])
        let (model, _, _, suite) = makeModel(provider: provider)
        defer { clean(suite) }

        await model.refreshModels()
        #expect(model.availability == .ready([AIModel(name: "llama3.2", sizeBytes: 2_000_000_000),
                                              AIModel(name: "qwen2.5-coder:7b", sizeBytes: nil)]))
        #expect(model.selectedModel == "llama3.2")
    }

    @Test func aModelTheUserAlreadyChoseIsKeptWhenItIsStillInstalled() async {
        let provider = FakeAIProvider()
        provider.modelsResult = .success([AIModel(name: "a", sizeBytes: nil), AIModel(name: "b", sizeBytes: nil)])
        let (model, _, _, suite) = makeModel(provider: provider)
        defer { clean(suite) }
        model.selectedModel = "b"

        await model.refreshModels()
        #expect(model.selectedModel == "b")
    }

    /// Kullanıcının seçtiği model silinmişse seçim SESSİZCE korunmaz: kurulu olana düşer,
    /// yoksa istek 404 ile patlardı ve sebebi görünmezdi.
    @Test func aModelThatDisappearedIsReplacedByAnInstalledOne() async {
        let provider = FakeAIProvider()
        provider.modelsResult = .success([AIModel(name: "a", sizeBytes: nil)])
        let (model, _, _, suite) = makeModel(provider: provider)
        defer { clean(suite) }
        model.selectedModel = "deleted-model"

        await model.refreshModels()
        #expect(model.selectedModel == "a")
    }

    // MARK: - Model YOKKEN dürüst durum (bu makinenin gerçek hâli)

    @Test func noModelsInstalledIsExplainedWithTheCommandThatFixesIt() async throws {
        let provider = FakeAIProvider()
        provider.modelsResult = .failure(AIProviderError.noModelsInstalled(endpoint: "http://localhost:11434"))
        let (model, _, _, suite) = makeModel(provider: provider)
        defer { clean(suite) }

        await model.refreshModels()

        let status = try #require(model.status)
        #expect(status.title == AIProviderError.noModelsInstalled(endpoint: "x").title)
        #expect(status.reason.lowercased().contains("no models"))
        #expect(status.recovery.contains("ollama pull"))
        #expect(!status.technicalDetail.isEmpty)
        // Boş açılır liste YOK: seçilebilir model de yok, gönderim de kapalı.
        #expect(model.installedModels.isEmpty)
        #expect(!model.canSend)
    }

    @Test func anUnreachableEndpointIsExplainedRatherThanLeftBlank() async throws {
        let provider = FakeAIProvider()
        provider.modelsResult = .failure(AIProviderError.endpointUnreachable(endpoint: "http://localhost:11434"))
        let (model, _, _, suite) = makeModel(provider: provider)
        defer { clean(suite) }

        await model.refreshModels()
        let status = try #require(model.status)
        #expect(status.reason.contains("http://localhost:11434"))
        #expect(!status.recovery.isEmpty)
    }

    /// Sağlayıcıdan gelmeyen bir hata (ör. beklenmedik bir tür) da yutulmaz.
    @Test func anUnexpectedFailureStillProducesAReadableStatus() async throws {
        struct Boom: Error {}
        let provider = FakeAIProvider()
        provider.modelsResult = .failure(Boom())
        let (model, _, _, suite) = makeModel(provider: provider)
        defer { clean(suite) }

        await model.refreshModels()
        let status = try #require(model.status)
        #expect(!status.title.isEmpty)
        #expect(!status.recovery.isEmpty)
    }

    @Test func aWorkingProviderShowsNoErrorBanner() async {
        let (model, _, _, suite) = makeModel()
        defer { clean(suite) }
        await model.refreshModels()
        #expect(model.status == nil)
    }

    // MARK: - Gönderim

    @Test func sendingIsBlockedUntilThereIsBothAModelAndAQuestion() async {
        let (model, provider, _, suite) = makeModel()
        defer { clean(suite) }
        await model.refreshModels()

        model.prompt = "   "
        #expect(!model.canSend)
        #expect(model.sendDisabledReason != nil)

        model.prompt = "list logs"
        #expect(model.canSend)
        #expect(model.sendDisabledReason == nil)
        #expect(provider.requests.isEmpty, "soru sorulmadan istek gitti")
    }

    @Test func sendingAppendsBothSidesOfTheExchangeAndClearsTheField() async {
        let provider = FakeAIProvider()
        provider.replyResult = .success(AIReply(text: "run `ls`"))
        let (model, _, _, suite) = makeModel(provider: provider)
        defer { clean(suite) }
        await model.refreshModels()

        model.prompt = "how do I list files"
        await model.send()

        #expect(model.conversation.messages.map(\.role) == [.user, .assistant])
        #expect(model.conversation.messages.last?.text == "run `ls`")
        #expect(model.prompt.isEmpty)
        #expect(model.sendState == .idle)
    }

    @Test func aFailedRequestKeepsTheQuestionSoItCanBeRetried() async {
        let provider = FakeAIProvider()
        provider.replyResult = .failure(AIProviderError.endpointUnreachable(endpoint: "http://localhost:11434"))
        let (model, _, _, suite) = makeModel(provider: provider)
        defer { clean(suite) }
        await model.refreshModels()

        model.prompt = "why"
        await model.send()

        #expect(model.sendState == .failed(.endpointUnreachable(endpoint: "http://localhost:11434")))
        #expect(model.status?.recovery.isEmpty == false)
        // Kullanıcının yazdığı kaybolmaz.
        #expect(model.prompt == "why")
        #expect(model.conversation.messages.isEmpty)
    }

    /// Gönderilen istek, kullanıcının panelde İNCELEDİĞİ bağlamı taşır — ne fazlası ne azı.
    @Test func theRequestCarriesExactlyTheContextThePanelShowed() async throws {
        let bridge = FakeAITerminalBridge()
        bridge.snapshot = AIContextSnapshot([.workingDirectory: "/Users/dev/pinro", .shell: "zsh"])
        let (model, provider, _, suite) = makeModel(bridge: bridge)
        defer { clean(suite) }
        await model.refreshModels()
        model.refreshContext()

        model.prompt = "where am I"
        await model.send()

        let request = try #require(provider.requests.first)
        let system = try #require(request.messages.first)
        #expect(system.content.text.contains(model.preparedContext.previewText))
        #expect(model.preparedContext.previewText.contains("/Users/dev/pinro"))
    }

    @Test func aContextKindTurnedOffInSettingsNeverReachesTheRequest() async throws {
        let bridge = FakeAITerminalBridge()
        bridge.snapshot = AIContextSnapshot([.workingDirectory: "/Users/dev/pinro", .shell: "zsh"])
        let (model, provider, _, suite) = makeModel(bridge: bridge)
        defer { clean(suite) }
        model.settings.settings.aiContext.setIncludes(.workingDirectory, false)
        await model.refreshModels()
        model.refreshContext()

        model.prompt = "where am I"
        await model.send()

        let request = try #require(provider.requests.first)
        for text in request.outgoingTexts {
            #expect(!text.contains("/Users/dev/pinro"))
        }
    }

    @Test func theContextIndicatorSaysHowMuchIsGoingAndWhatWasHidden() {
        let bridge = FakeAITerminalBridge()
        bridge.snapshot = AIContextSnapshot([
            .shell: "zsh",
            .selectedOutput: "API_TOKEN=abcdef123456",
        ])
        let (model, _, _, suite) = makeModel(bridge: bridge)
        defer { clean(suite) }
        model.refreshContext()

        #expect(model.contextSummary.contains("2"))
        #expect(model.preparedContext.didFindSecrets)
        #expect(model.contextSummary.contains("hidden"))
    }

    @Test func anEmptyContextSaysNothingIsBeingSentInsteadOfShowingAnEmptyBox() {
        let (model, _, _, suite) = makeModel()
        defer { clean(suite) }
        model.refreshContext()
        #expect(model.preparedContext.isEmpty)
        #expect(model.contextSummary == AIPanelModel.emptyContextSummary)
    }

    // MARK: - Run onayı (briefs/2'nin kırmızı çizgisi)

    @Test func askingToRunOnlyOpensTheConfirmationAndTouchesNothing() {
        let (model, _, bridge, suite) = makeModel()
        defer { clean(suite) }
        let suggestion = AICommandSuggestion(command: "rm -rf /")

        model.requestRun(suggestion)

        #expect(model.pendingRun == suggestion)
        #expect(bridge.ran.isEmpty, "onay beklenmeden komut çalıştı")
        #expect(bridge.inserted.isEmpty)
    }

    @Test func confirmingRunsTheCommandExactlyOnceAndClosesTheConfirmation() {
        let (model, _, bridge, suite) = makeModel()
        defer { clean(suite) }
        model.requestRun(AICommandSuggestion(command: "ls -la"))

        model.confirmRun()

        #expect(bridge.ran == ["ls -la"])
        #expect(model.pendingRun == nil)
    }

    @Test func cancellingLeavesTheTerminalUntouched() {
        let (model, _, bridge, suite) = makeModel()
        defer { clean(suite) }
        model.requestRun(AICommandSuggestion(command: "rm -rf /"))

        model.cancelRun()

        #expect(bridge.ran.isEmpty)
        #expect(model.pendingRun == nil)
    }

    /// Onay penceresi kapandıktan sonra ikinci bir `confirmRun` komutu TEKRAR çalıştırmaz.
    @Test func confirmingWithNothingPendingRunsNothing() {
        let (model, _, bridge, suite) = makeModel()
        defer { clean(suite) }
        model.confirmRun()
        #expect(bridge.ran.isEmpty)
    }

    /// briefs/2: "AI tarafından üretilen riskli komutlar hiçbir koşulda otomatik
    /// çalıştırılmamalıdır." Cevap komut içeriyor diye hiçbir şey çalışmaz.
    @Test func areplyFullOfCommandsRunsNothingOnItsOwn() async {
        let provider = FakeAIProvider()
        provider.replyResult = .success(AIReply(text: "```sh\nrm -rf /\n```"))
        let (model, _, bridge, suite) = makeModel(provider: provider)
        defer { clean(suite) }
        await model.refreshModels()

        model.prompt = "clean everything"
        await model.send()

        #expect(bridge.ran.isEmpty)
        #expect(bridge.inserted.isEmpty)
    }

    // MARK: - Insert ve Copy

    @Test func insertTypesTheCommandWithoutPressingReturn() {
        let (model, _, bridge, suite) = makeModel()
        defer { clean(suite) }
        model.insert(AICommandSuggestion(command: "git status"))
        #expect(bridge.inserted == ["git status"])
        #expect(bridge.ran.isEmpty)
    }

    @Test func copyHandsTheCommandToWhoeverOwnsTheClipboard() {
        let (model, _, _, suite) = makeModel()
        defer { clean(suite) }
        var copied: [String] = []
        model.copyToClipboard = { copied.append($0) }

        model.copy(AICommandSuggestion(command: "git status"))
        #expect(copied == ["git status"])
    }

    // MARK: - Explain (briefs/2 "Hata Açıklama")

    @Test func explainAsksAboutThatCommandWithoutTheUserTypingAnything() async throws {
        let (model, provider, _, suite) = makeModel()
        defer { clean(suite) }
        await model.refreshModels()

        await model.explain(AICommandSuggestion(command: "chmod -R 777 /etc"))

        let request = try #require(provider.requests.first)
        let last = try #require(request.messages.last)
        #expect(last.content.text.contains("chmod -R 777 /etc"))
        #expect(last.role == .user)
    }

    /// Başarısız bir komut seçildiğinde brief üç şey ister: olası neden, ilgili satırlar,
    /// güvenli çözüm adımları.
    @Test func explainingASelectionAsksForCauseAndSafeSteps() async throws {
        let bridge = FakeAITerminalBridge()
        bridge.snapshot = AIContextSnapshot([
            .selectedOutput: "fatal: not a git repository",
            .selectedCommand: "git status",
        ])
        let (model, provider, _, suite) = makeModel(bridge: bridge)
        defer { clean(suite) }
        await model.refreshModels()
        model.refreshContext()

        #expect(model.canExplainSelection)
        await model.explainSelection()

        let request = try #require(provider.requests.first)
        let last = try #require(request.messages.last)
        #expect(last.content.text.lowercased().contains("cause"))
        #expect(last.content.text.lowercased().contains("safe"))
    }

    @Test func explainingWithNothingSelectedIsOfferedAsDisabledNotAsAnEmptyQuestion() async {
        let (model, provider, _, suite) = makeModel()
        defer { clean(suite) }
        await model.refreshModels()
        model.refreshContext()

        #expect(!model.canExplainSelection)
        await model.explainSelection()
        #expect(provider.requests.isEmpty)
    }

    // MARK: - Panel terminali engellemez (briefs/3)

    @Test func thePanelWidthStaysInsideTheBriefsRange() {
        #expect(AIPanelLayout.defaultWidth >= 360)
        #expect(AIPanelLayout.defaultWidth <= 420)
        #expect(AIPanelLayout.minWidth == 360)
        #expect(AIPanelLayout.maxWidth == 420)
    }

    @Test func openingThePanelDoesNotTouchTheTerminal() {
        let (model, _, bridge, suite) = makeModel()
        defer { clean(suite) }
        model.isPresented = true
        #expect(bridge.ran.isEmpty)
        #expect(bridge.inserted.isEmpty)
    }
}
