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
        #expect(sections.first?.map(\.command) == [.copy, .paste, .selectAll])
        #expect(sections.dropFirst().first?.map(\.command) == [.clearScreen])
        #expect(sections.last?.map(\.command) == [.splitRight, .splitDown])
    }

    @Test("basliklar Ingilizce ve tek anlamli")
    func titles() {
        let items = flat(TerminalContextMenu.sections(hasSelection: true, canPaste: true, canSplit: true))
        #expect(items.map(\.title) == ["Copy", "Paste", "Select All", "Clear Screen", "Split Right", "Split Down"])
    }

    @Test("secim yokken Copy gizlenmez, disabled olur")
    func copyDisabledWithoutSelection() {
        let items = flat(TerminalContextMenu.sections(hasSelection: false, canPaste: true, canSplit: true))
        let copy = items.first { $0.command == .copy }
        #expect(copy?.isEnabled == false)
        #expect(items.count == 6)
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

    /// Ctrl-L PTY'ye gider: shell (readline/zle) ekrani temizleyip promptu YENIDEN CIZER.
    /// Emulatore dogrudan ESC[2J beslemek promptu ekrandan silip bos ekran birakirdi.
    @Test("Clear Screen shell'e Ctrl-L gonderir")
    func clearScreenSendsFormFeed() {
        #expect(TerminalContextMenu.clearScreenInput == "\u{0C}")
    }
}
