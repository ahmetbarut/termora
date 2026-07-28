import AppKit
import Foundation
import Testing
@testable import Termora

@Suite("CommandPaletteModel")
@MainActor
struct CommandPaletteModelTests {

    private func makeModel() -> (CommandPaletteModel, UserDefaults) {
        let suiteName = "termora.palette.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (CommandPaletteModel(defaults: defaults), defaults)
    }

    private func result(_ id: String, action: @escaping @MainActor () -> Void = {}) -> CommandPaletteResult {
        CommandPaletteResult(
            item: CommandPaletteItem(id: id,
                                     title: id,
                                     category: .actions,
                                     symbolName: "circle",
                                     shortcut: nil,
                                     action: action),
            matchedIndices: [])
    }

    // MARK: - Açılma / kapanma

    @Test func startsHidden() {
        let (model, _) = makeModel()
        #expect(model.isPresented == false)
    }

    @Test func presentingResetsQueryAndSelection() {
        let (model, _) = makeModel()
        model.query = "old text"
        model.moveSelection(by: 2, resultCount: 10)

        model.present()

        #expect(model.isPresented)
        #expect(model.query.isEmpty)
        #expect(model.selectedIndex == 0)
    }

    @Test func togglingOpensThenCloses() {
        let (model, _) = makeModel()
        model.toggle()
        #expect(model.isPresented)
        model.toggle()
        #expect(model.isPresented == false)
    }

    // MARK: - Klavye gezinmesi

    @Test func selectionMovesWithinBounds() {
        let (model, _) = makeModel()
        model.moveSelection(by: 1, resultCount: 3)
        #expect(model.selectedIndex == 1)
        model.moveSelection(by: 1, resultCount: 3)
        #expect(model.selectedIndex == 2)
    }

    @Test func selectionStopsAtTheEnds() {
        let (model, _) = makeModel()
        model.moveSelection(by: -1, resultCount: 3)
        #expect(model.selectedIndex == 0)
        model.moveSelection(by: 5, resultCount: 3)
        #expect(model.selectedIndex == 2)
    }

    @Test func selectionStaysAtZeroWithoutResults() {
        let (model, _) = makeModel()
        model.moveSelection(by: 1, resultCount: 0)
        #expect(model.selectedIndex == 0)
    }

    @Test func selectionIsClampedWhenTheResultListShrinks() {
        let (model, _) = makeModel()
        model.moveSelection(by: 4, resultCount: 8)
        #expect(model.selectedIndex == 4)
        model.clampSelection(resultCount: 2)
        #expect(model.selectedIndex == 1)
        model.clampSelection(resultCount: 0)
        #expect(model.selectedIndex == 0)
    }

    @Test func hoverSelectionIgnoresOutOfRangeIndices() {
        let (model, _) = makeModel()
        model.select(index: 3, resultCount: 2)
        #expect(model.selectedIndex == 0)
        model.select(index: 1, resultCount: 2)
        #expect(model.selectedIndex == 1)
    }

    // MARK: - Çalıştırma ve son kullanılanlar

    @Test func runningAnItemClosesThePaletteAndInvokesTheAction() {
        let (model, _) = makeModel()
        var runCount = 0
        model.present()

        model.run(result("action.newTab") { runCount += 1 })

        #expect(runCount == 1)
        #expect(model.isPresented == false)
        #expect(model.recentIDs == ["action.newTab"])
    }

    @Test func mostRecentItemMovesToTheFrontWithoutDuplicates() {
        let (model, _) = makeModel()
        model.run(result("a"))
        model.run(result("b"))
        model.run(result("a"))
        #expect(model.recentIDs == ["a", "b"])
    }

    @Test func recentListIsCapped() {
        let (model, _) = makeModel()
        for index in 0..<(CommandPaletteModel.recentLimit + 3) {
            model.run(result("item.\(index)"))
        }
        #expect(model.recentIDs.count == CommandPaletteModel.recentLimit)
        #expect(model.recentIDs.first == "item.\(CommandPaletteModel.recentLimit + 2)")
        #expect(model.recentIDs.contains("item.0") == false)
    }

    @Test func recentItemsSurviveANewModelOverTheSameStorage() {
        let (model, defaults) = makeModel()
        model.run(result("action.splitVertically"))

        let reloaded = CommandPaletteModel(defaults: defaults)
        #expect(reloaded.recentIDs == ["action.splitVertically"])
    }

    // MARK: - Alternatif kısayol (⌘⇧P)

    @Test func alternateShortcutRecognisesCommandShiftP() {
        #expect(CommandPaletteHotkey.isAlternateShortcut(characters: "P", modifiers: [.command, .shift]))
        #expect(CommandPaletteHotkey.isAlternateShortcut(characters: "p", modifiers: [.command, .shift]))
    }

    @Test func alternateShortcutIgnoresOtherKeyCombinations() {
        #expect(CommandPaletteHotkey.isAlternateShortcut(characters: "p", modifiers: [.command]) == false)
        #expect(CommandPaletteHotkey.isAlternateShortcut(characters: "k", modifiers: [.command, .shift]) == false)
        #expect(CommandPaletteHotkey.isAlternateShortcut(characters: nil, modifiers: [.command, .shift]) == false)
        // Fazladan değiştirici tuş varsa kısayol sayılmaz.
        #expect(CommandPaletteHotkey.isAlternateShortcut(
            characters: "p", modifiers: [.command, .shift, .option]) == false)
    }

    @Test func alternateShortcutIgnoresCapsLockAndNumericPadNoise() {
        // Sistem, olayların üzerine .capsLock/.function gibi bayraklar ekleyebilir.
        #expect(CommandPaletteHotkey.isAlternateShortcut(
            characters: "p", modifiers: [.command, .shift, .capsLock]))
    }
}
