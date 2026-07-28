import Foundation
import Testing
@testable import Termora

/// briefs/2 "Komut Paleti → AI komut alanını açma" + briefs/3 "Sonuç kategorileri: AI Actions".
///
/// Paletin AI satırları hiçbir soru SORMAZ ve hiçbir komut ÇALIŞTIRMAZ: paneli açar,
/// komut alanına odaklanır, ya da seçili çıktı için açıklama ister. Model seçimi,
/// maskeleme ve onay hep panelin kendi kurallarına tabidir.
@MainActor
@Suite("Komut paletinde AI Actions kategorisi")
struct AIPaletteCommandsTests {

    private struct Subject {
        let workspace: WorkspaceViewModel
        let settings: SettingsStore
        let themes: ThemeStore
        let ai: AIPanelModel
        let provider: FakeAIProvider
    }

    private func makeSubject() throws -> Subject {
        let suiteName = "AIPalette.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let settings = SettingsStore(defaults: defaults)
        let workspace = WorkspaceViewModel(sessionManager: MockSessionManager(),
                                           settings: settings,
                                           profiles: ProfileStore(defaults: defaults))
        workspace.newTab()
        let provider = FakeAIProvider()
        let ai = AIPanelModel(provider: provider,
                              settings: settings,
                              catalog: AIModelCatalog(provider: provider, settings: settings))
        return Subject(workspace: workspace,
                       settings: settings,
                       themes: ThemeStore(bundle: .main),
                       ai: ai,
                       provider: provider)
    }

    private func items(_ subject: Subject, ai: AIPanelModel?) -> [CommandPaletteItem] {
        CommandPaletteCatalog.items(workspace: subject.workspace,
                                    settings: subject.settings,
                                    themes: subject.themes,
                                    ai: ai,
                                    openSettings: {})
    }

    private func aiItem(_ id: String, _ subject: Subject) throws -> CommandPaletteItem {
        let all = items(subject, ai: subject.ai)
        return try #require(all.first { $0.id == id }, "\(id) katalogda yok")
    }

    // MARK: - Kategorinin varlığı

    /// Panel bağlı değilse kategori HİÇ çizilmez — diğer isteğe bağlı kategorilerle aynı
    /// kural. Tıklanınca hiçbir şey yapmayan bir satır bırakmak yalan olurdu.
    @Test func withoutAPanelThereIsNoAICategory() throws {
        let subject = try makeSubject()
        #expect(items(subject, ai: nil).contains { $0.category == .aiActions } == false)
    }

    @Test func thePanelBringsTheCategory() throws {
        let subject = try makeSubject()
        let aiItems = items(subject, ai: subject.ai).filter { $0.category == .aiActions }
        #expect(aiItems.isEmpty == false)
        #expect(CommandPaletteCategory.aiActions.title == "AI Actions")
    }

    // MARK: - Komut alanını açma (briefs/2)

    /// Brief "AI komut alanını açma" diyor — paneli açmak yetmez, imleç yazılacak yere
    /// gitmeli. Aksi hâlde kullanıcı paleti klavyeyle açıp fareye uzanmak zorunda kalır.
    @Test func openingTheAssistantFocusesThePromptField() throws {
        let subject = try makeSubject()
        #expect(subject.ai.isPresented == false)
        #expect(subject.ai.promptFocusRequest == nil)

        try aiItem("ai.openPrompt", subject).action()

        #expect(subject.ai.isPresented)
        #expect(subject.ai.promptFocusRequest != nil)
    }

    /// Panel zaten açıkken komut YİNE odak ister: ikinci kez çağırmak kullanıcıyı yazma
    /// alanına götürmeliydi, sessizce hiçbir şey yapmamalı değil.
    @Test func askingAgainWhileOpenStillMovesTheCursorToThePrompt() throws {
        let subject = try makeSubject()
        try aiItem("ai.openPrompt", subject).action()
        let first = try #require(subject.ai.promptFocusRequest)

        try aiItem("ai.openPrompt", subject).action()

        #expect(subject.ai.isPresented)
        #expect(subject.ai.promptFocusRequest != first)
    }

    /// Paleti açmak sunucuya HİÇBİR ŞEY sormaz: model listesi panelin kendi işidir.
    @Test func listingThePaletteAsksTheProviderNothing() throws {
        let subject = try makeSubject()
        _ = items(subject, ai: subject.ai)
        #expect(subject.provider.modelQueries == 0)
    }

    // MARK: - Explain Selection

    /// Palet satırı doğrudan soru SORMAZ; panelin kendi yolunu çağırır. Seçim yoksa panel
    /// zaten sessiz kalır (AIPanelModelTests), yani burada sağlayıcıya istek gitmemeli.
    @Test func explainSelectionWithNothingSelectedSendsNoRequest() async throws {
        let subject = try makeSubject()

        try aiItem("ai.explainSelection", subject).action()
        // Eylem bir Task açıyor; onun bitmesini bekle.
        await Task.yield()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(subject.ai.isPresented)
        #expect(subject.provider.requests.isEmpty)
    }

    // MARK: - Katalog kuralları

    @Test func identifiersAreStableAndUnique() throws {
        let subject = try makeSubject()
        let all = items(subject, ai: subject.ai)
        let ids = all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.contains("ai.openPrompt"))
        #expect(ids.contains("ai.explainSelection"))
    }

    @Test func everyAIItemHasATitleAndASymbol() throws {
        let subject = try makeSubject()
        for item in items(subject, ai: subject.ai).filter({ $0.category == .aiActions }) {
            #expect(!item.title.isEmpty)
            #expect(!item.symbolName.isEmpty)
        }
    }
}
