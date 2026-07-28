import Foundation
import Testing
@testable import Termora

/// Brief 3 "Sag Tik Menuleri": terminal baglam menusu. Kullanilamayan ogeler
/// gizlenmek yerine disabled gosterilir.
@Suite("Terminal baglam menusu")
struct TerminalContextMenuTests {

    private func flat(_ sections: [[TerminalContextMenuItem]]) -> [TerminalContextMenuItem] {
        sections.flatMap { $0 }
    }

    @Test("bolumler ve sira: duzenleme / ekran / bolme")
    func sectionOrder() {
        let sections = TerminalContextMenu.sections(hasSelection: true, canPaste: true, canSplit: true)

        #expect(sections.count == 3)
        #expect(sections.first?.map(\.command) == [.copy, .paste, .selectAll, .searchSelection, .explainWithAI])
        #expect(sections.dropFirst().first?.map(\.command) == [.clearScreen])
        #expect(sections.last?.map(\.command) == [.splitRight, .splitDown])
    }

    @Test("basliklar Ingilizce ve tek anlamli")
    func titles() {
        let items = flat(TerminalContextMenu.sections(hasSelection: true, canPaste: true, canSplit: true))
        #expect(items.map(\.title) == ["Copy", "Paste", "Select All", "Search Selection",
                                       "Explain with AI", "Clear Screen", "Split Right", "Split Down"])
    }

    @Test("secim yokken Copy gizlenmez, disabled olur")
    func copyDisabledWithoutSelection() {
        let items = flat(TerminalContextMenu.sections(hasSelection: false, canPaste: true, canSplit: true))
        let copy = items.first { $0.command == .copy }
        #expect(copy?.isEnabled == false)
        #expect(items.count == 8)
    }

    @Test("pano bosken Paste disabled")
    func pasteDisabledWithEmptyClipboard() {
        let items = flat(TerminalContextMenu.sections(hasSelection: true, canPaste: false, canSplit: true))
        #expect(items.first { $0.command == .paste }?.isEnabled == false)
        #expect(items.first { $0.command == .copy }?.isEnabled == true)
    }

    @Test("bolme eylemi bagli degilse Split ogeleri disabled")
    func splitDisabledWhenUnavailable() {
        let items = flat(TerminalContextMenu.sections(hasSelection: true, canPaste: true, canSplit: false))
        #expect(items.first { $0.command == .splitRight }?.isEnabled == false)
        #expect(items.first { $0.command == .splitDown }?.isEnabled == false)
        #expect(items.first { $0.command == .clearScreen }?.isEnabled == true)
        #expect(items.first { $0.command == .selectAll }?.isEnabled == true)
    }

    // MARK: - Explain with AI (briefs/3 "Sag Tik Menuleri")

    /// Brief menuye "Explain with AI" koyuyor. Secilen metin AI panelinin baglamina
    /// girdigi icin oge SECIM olmadan anlamsizdir; brief geregi gizlenmez, disabled olur.
    @Test("secim yokken Explain with AI gizlenmez, disabled olur")
    func explainDisabledWithoutSelection() {
        let items = flat(TerminalContextMenu.sections(hasSelection: false, canPaste: true, canSplit: true))
        let explain = items.first { $0.command == .explainWithAI }
        #expect(explain?.isEnabled == false)
        #expect(explain?.title == "Explain with AI")
    }

    /// Arama tek satirda calisir; secim yoksa aranacak bir sey de yok.
    @Test("secim yokken Search Selection gizlenmez, disabled olur")
    func searchSelectionDisabledWithoutSelection() {
        let items = flat(TerminalContextMenu.sections(hasSelection: false, canPaste: true, canSplit: true))
        let search = items.first { $0.command == .searchSelection }
        #expect(search?.isEnabled == false)
        #expect(search?.title == "Search Selection")
    }

    @Test("secim varken Explain with AI etkin")
    func explainEnabledWithSelection() {
        let items = flat(TerminalContextMenu.sections(hasSelection: true, canPaste: true, canSplit: true))
        #expect(items.first { $0.command == .explainWithAI }?.isEnabled == true)
    }

    /// Menu ogesi AI'a HICBIR SEY sormaz: yalnizca bir istek jetonu birakir. Panel o jetonu
    /// gorunce acilir ve sorar. Menunun dogrudan istek atmasi, AI panelinin hic kurulmadigi
    /// bir baglamda (onizleme) sessiz bir cokme ya da bos bir soru olurdu.
    @MainActor
    @Test("Explain istegi bir jeton birakir, kendisi soru sormaz")
    func explainRequestOnlyRaisesAToken() throws {
        let suiteName = "termora.explain.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let workspace = WorkspaceViewModel(sessionManager: MockSessionManager(),
                                           settings: SettingsStore(defaults: defaults),
                                           profiles: ProfileStore(defaults: defaults))
        workspace.newTab()

        #expect(workspace.explainSelectionRequest == nil)

        workspace.requestExplainSelection()
        let first = try #require(workspace.explainSelectionRequest)

        // Ikinci istek YENI bir jeton uretir; aksi halde ayni secim icin ikinci kez
        // "Explain" demek hicbir sey yapmazdi (onChange ayni degerde uyanmaz).
        workspace.requestExplainSelection()
        #expect(workspace.explainSelectionRequest != first)
    }

    /// Ctrl-L PTY'ye gider: shell (readline/zle) ekrani temizleyip promptu YENIDEN CIZER.
    /// Emulatore dogrudan ESC[2J beslemek promptu ekrandan silip bos ekran birakirdi.
    @Test("Clear Screen shell'e Ctrl-L gonderir")
    func clearScreenSendsFormFeed() {
        #expect(TerminalContextMenu.clearScreenInput == "\u{0C}")
    }
}
