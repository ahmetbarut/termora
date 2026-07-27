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
}
