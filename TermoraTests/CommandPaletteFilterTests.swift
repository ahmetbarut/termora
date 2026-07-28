import Foundation
import Testing
@testable import Termora

@MainActor
private func makeItem(_ id: String,
                      _ title: String,
                      category: CommandPaletteCategory = .actions,
                      action: @escaping @MainActor () -> Void = {}) -> CommandPaletteItem {
    CommandPaletteItem(id: id,
                       title: title,
                       category: category,
                       symbolName: "circle",
                       shortcut: nil,
                       action: action)
}

@Suite("CommandPaletteFilter")
@MainActor
struct CommandPaletteFilterTests {

    private var sample: [CommandPaletteItem] {
        [
            makeItem("action.newTab", "New Tab"),
            makeItem("action.closeTab", "Close Tab"),
            makeItem("action.splitVertically", "Split Vertically"),
            makeItem("settings.open", "Open Settings", category: .settings),
            makeItem("theme.dracula", "Dracula", category: .themes),
        ]
    }

    // MARK: - Boş sorgu

    @Test func emptyQueryKeepsEveryItemInDeclarationOrder() {
        let results = CommandPaletteFilter.results(items: sample, query: "", recentIDs: [])
        #expect(results.map(\.id) == sample.map(\.id))
        #expect(results.allSatisfy { $0.matchedIndices.isEmpty })
    }

    @Test func emptyQueryListsRecentItemsFirstInRecencyOrder() {
        let results = CommandPaletteFilter.results(
            items: sample, query: "", recentIDs: ["theme.dracula", "action.closeTab"])
        #expect(results.prefix(2).map(\.id) == ["theme.dracula", "action.closeTab"])
        // Kalanlar bildirim sırasını korur ve hiçbir öğe iki kez listelenmez.
        #expect(results.map(\.id) == ["theme.dracula", "action.closeTab",
                                      "action.newTab", "action.splitVertically", "settings.open"])
    }

    @Test func unknownRecentIdentifiersAreIgnored() {
        let results = CommandPaletteFilter.results(
            items: sample, query: "", recentIDs: ["gone.forever", "action.newTab"])
        #expect(results.map(\.id) == ["action.newTab", "action.closeTab",
                                      "action.splitVertically", "settings.open", "theme.dracula"])
    }

    // MARK: - Sorgulu arama

    @Test func dropsItemsThatDoNotMatch() {
        let results = CommandPaletteFilter.results(items: sample, query: "zzz", recentIDs: [])
        #expect(results.isEmpty)
    }

    @Test func ranksTheBestTitleMatchFirst() throws {
        let results = CommandPaletteFilter.results(items: sample, query: "nt", recentIDs: [])
        #expect(results.first?.id == "action.newTab")
    }

    @Test func carriesMatchedIndicesForHighlighting() throws {
        let results = CommandPaletteFilter.results(items: sample, query: "spl", recentIDs: [])
        let first = try #require(results.first)
        #expect(first.id == "action.splitVertically")
        #expect(first.matchedIndices == [0, 1, 2])
    }

    @Test func categoryNameMatchesRankBelowTitleMatches() throws {
        let items = [makeItem("theme.dracula", "Dracula", category: .themes),
                     makeItem("action.themeReport", "Theme Report")]
        let results = CommandPaletteFilter.results(items: items, query: "theme", recentIDs: [])
        #expect(results.map(\.id) == ["action.themeReport", "theme.dracula"])
        // Kategori üzerinden eşleşen satırda başlıkta vurgulanacak karakter yoktur.
        #expect(results.last?.matchedIndices.isEmpty == true)
    }

    @Test func recentItemsWinTiesAgainstEquallyScoredItems() throws {
        let items = [makeItem("a", "Close Pane"), makeItem("b", "Close Pane")]
        let neutral = CommandPaletteFilter.results(items: items, query: "cp", recentIDs: [])
        #expect(neutral.map(\.id) == ["a", "b"])

        let recent = CommandPaletteFilter.results(items: items, query: "cp", recentIDs: ["b"])
        #expect(recent.map(\.id) == ["b", "a"])
    }

    @Test func recencyDoesNotOverrideAClearlyBetterMatch() throws {
        let items = [makeItem("a", "New Tab"), makeItem("b", "Renew Wide")]
        let results = CommandPaletteFilter.results(items: items, query: "new", recentIDs: ["b"])
        #expect(results.first?.id == "a")
    }

    @Test func orderingIsStableForIdenticalScores() {
        let items = [makeItem("a", "Close Pane"), makeItem("b", "Close Pane"), makeItem("c", "Close Pane")]
        let first = CommandPaletteFilter.results(items: items, query: "close", recentIDs: [])
        let second = CommandPaletteFilter.results(items: items, query: "close", recentIDs: [])
        #expect(first.map(\.id) == ["a", "b", "c"])
        #expect(first.map(\.id) == second.map(\.id))
    }

    // MARK: - Bölümler

    @Test func emptyQueryGroupsRecentItemsAndCategories() {
        let results = CommandPaletteFilter.results(
            items: sample, query: "", recentIDs: ["theme.dracula"])
        let sections = CommandPaletteFilter.sections(for: results, query: "")
        // "Dracula" son kullanılanlara taşındığı için Themes bölümü hiç çizilmez.
        #expect(sections.map(\.title) == ["Recently Used", "Actions", "Settings"])
        #expect(sections.first?.results.map(\.id) == ["theme.dracula"])
        #expect(sections.last?.results.map(\.id) == ["settings.open"])
    }

    @Test func searchResultsAreShownAsOneRankedSection() {
        let results = CommandPaletteFilter.results(items: sample, query: "t", recentIDs: [])
        let sections = CommandPaletteFilter.sections(for: results, query: "t")
        #expect(sections.count == 1)
        #expect(sections.first?.title == "Results")
        #expect(sections.first?.results.map(\.id) == results.map(\.id))
    }

    @Test func sectionsCoverEveryResultExactlyOnce() {
        let results = CommandPaletteFilter.results(items: sample, query: "", recentIDs: ["settings.open"])
        let sections = CommandPaletteFilter.sections(for: results, query: "")
        #expect(sections.flatMap { $0.results.map(\.id) } == results.map(\.id))
    }

    @Test func noSectionsWhenThereAreNoResults() {
        #expect(CommandPaletteFilter.sections(for: [], query: "zzz").isEmpty)
        #expect(CommandPaletteFilter.sections(for: [], query: "").isEmpty)
    }
}
