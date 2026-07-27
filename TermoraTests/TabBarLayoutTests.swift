import CoreGraphics
import Testing
@testable import Termora

@MainActor
@Suite struct TabBarLayoutTests {

    @Test func zeroTabsHaveZeroWidth() {
        #expect(TabBarLayout.tabWidth(availableWidth: 800, tabCount: 0) == 0)
    }

    @Test func singleTabIsCappedAtMaxWidth() {
        #expect(TabBarLayout.tabWidth(availableWidth: 1000, tabCount: 1) == TabBarLayout.maxTabWidth)
    }

    @Test func tabsShareAvailableWidthEqually() {
        #expect(TabBarLayout.tabWidth(availableWidth: 1000, tabCount: 10) == 100)
        #expect(TabBarLayout.tabWidth(availableWidth: 600, tabCount: 4) == 150)
    }

    @Test func widthNeverDropsBelowMinimum() {
        #expect(TabBarLayout.tabWidth(availableWidth: 1000, tabCount: 40) == TabBarLayout.minTabWidth)
    }

    @Test func negativeAvailableWidthFallsBackToMinimum() {
        #expect(TabBarLayout.tabWidth(availableWidth: -120, tabCount: 3) == TabBarLayout.minTabWidth)
    }

    @Test func layoutConstantsAreConsistent() {
        #expect(TabBarLayout.minTabWidth < TabBarLayout.maxTabWidth)
        #expect(TabBarLayout.height > 0)
        #expect(TabBarLayout.newTabButtonWidth > 0)
    }

    // MARK: - Küçük pencere davranışı (brief 3)

    @Test func narrowTabsSwitchToTheCompactPresentation() {
        #expect(TabBarLayout.isCompact(tabWidth: TabBarLayout.minTabWidth))
        #expect(TabBarLayout.isCompact(tabWidth: TabBarLayout.maxTabWidth) == false)
        #expect(TabBarLayout.compactTabWidth > TabBarLayout.minTabWidth)
        #expect(TabBarLayout.compactTabWidth < TabBarLayout.maxTabWidth)
    }

    @Test func fittingTabCountCountsFullWidthTabsOnly() {
        // 720 - 28 = 692 kullanılabilir; 72 pt'lik sekmelerden 9 tanesi sığar.
        #expect(TabBarLayout.fittingTabCount(availableWidth: 720) == 9)
        #expect(TabBarLayout.fittingTabCount(availableWidth: 1000) == 13)
    }

    @Test func atLeastOneTabIsAlwaysReportedAsFitting() {
        #expect(TabBarLayout.fittingTabCount(availableWidth: 0) == 1)
        #expect(TabBarLayout.fittingTabCount(availableWidth: -400) == 1)
    }

    @Test func minimumWindowSizeMatchesTheBrief() {
        #expect(Double(WindowLayout.minWidth) == 720)
        #expect(Double(WindowLayout.minHeight) == 480)
    }

    @Test func minimumWindowStillFitsSeveralTabsAndTheTerminal() {
        // Sekme çubuğu sabit yükseklikte: terminal alanı daralmadan korunur.
        #expect(TabBarLayout.fittingTabCount(availableWidth: WindowLayout.minWidth) >= 8)
        #expect(Double(WindowLayout.minHeight - TabBarLayout.height) >= 400)
    }
}
