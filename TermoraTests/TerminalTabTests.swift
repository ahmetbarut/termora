import Foundation
import Testing
@testable import Termora

@MainActor
@Suite struct TerminalTabTests {

    private func makeTab() -> TerminalTab {
        let paneID = UUID()
        return TerminalTab(root: .leaf(paneID: paneID, sessionID: UUID()), activePaneID: paneID)
    }

    @Test func displayTitleFallsBackToTerminalWhenEverythingIsEmpty() {
        let tab = makeTab()
        #expect(tab.customTitle == nil)
        #expect(tab.automaticTitle.isEmpty)
        #expect(tab.displayTitle == "Terminal")
    }

    @Test func displayTitleUsesAutomaticTitleWhenThereIsNoCustomTitle() {
        let tab = makeTab()
        tab.automaticTitle = "~/code — zsh"
        #expect(tab.displayTitle == "~/code — zsh")
    }

    @Test func customTitleWinsOverAutomaticTitle() {
        let tab = makeTab()
        tab.automaticTitle = "~/code — zsh"
        tab.customTitle = "Build"
        #expect(tab.displayTitle == "Build")
    }

    @Test func emptyCustomTitleIsIgnored() {
        let tab = makeTab()
        tab.automaticTitle = "zsh"
        tab.customTitle = ""
        #expect(tab.displayTitle == "zsh")
    }

    @Test func activePaneAndRootAreStoredAsGiven() {
        let paneID = UUID()
        let sessionID = UUID()
        let tab = TerminalTab(root: .leaf(paneID: paneID, sessionID: sessionID), activePaneID: paneID)
        #expect(tab.activePaneID == paneID)
        #expect(tab.root.sessionID(ofPane: paneID) == sessionID)
        #expect(tab.isSearchVisible == false)
    }
}