import Foundation
import Testing
@testable import Termora

@Suite("SearchSummaryFormatter")
@MainActor
struct SearchSummaryFormatterTests {

    @Test func formatsActiveMatchOverTotal() {
        #expect(SearchSummaryFormatter.text(SearchSummary(index: 2, total: 14)) == "2/14")
        #expect(SearchSummaryFormatter.text(SearchSummary(index: 1, total: 1)) == "1/1")
    }

    @Test func formatsNoMatchesAsZeroZero() {
        #expect(SearchSummaryFormatter.text(SearchSummary(index: 0, total: 0)) == "0/0")
        #expect(SearchSummaryFormatter.text(.empty) == "0/0")
    }

    @Test func showsZeroIndexWhenThereIsNoActiveMatch() {
        // SwiftTerm searchMatchSummary, aktif eşleşme yoksa (0, total) döner.
        #expect(SearchSummaryFormatter.text(SearchSummary(index: 0, total: 14)) == "0/14")
    }

    @Test func clampsOutOfRangeIndex() {
        #expect(SearchSummaryFormatter.text(SearchSummary(index: -3, total: 5)) == "0/5")
        #expect(SearchSummaryFormatter.text(SearchSummary(index: 9, total: 5)) == "5/5")
    }
}
