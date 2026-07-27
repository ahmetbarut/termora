//
//  TerminalHostViewTests.swift
//  TermoraTests
//

import Foundation
import Testing
@testable import Termora

@MainActor
struct TerminalHostViewTests {

    @Test func asksForFocusOnceWhileActive() {
        let coordinator = TerminalHostView.Coordinator()
        let sessionID = UUID()

        #expect(coordinator.shouldRequestFocus(sessionID: sessionID, isActive: true) == true)
        #expect(coordinator.shouldRequestFocus(sessionID: sessionID, isActive: true) == false)
        #expect(coordinator.shouldRequestFocus(sessionID: sessionID, isActive: true) == false)
    }

    @Test func neverAsksForFocusWhileInactive() {
        let coordinator = TerminalHostView.Coordinator()

        #expect(coordinator.shouldRequestFocus(sessionID: UUID(), isActive: false) == false)
    }

    @Test func asksAgainWhenTheHostedSessionChanges() {
        let coordinator = TerminalHostView.Coordinator()

        #expect(coordinator.shouldRequestFocus(sessionID: UUID(), isActive: true) == true)
        #expect(coordinator.shouldRequestFocus(sessionID: UUID(), isActive: true) == true)
    }

    @Test func asksAgainAfterFocusTrackingIsReset() {
        let coordinator = TerminalHostView.Coordinator()
        let sessionID = UUID()

        #expect(coordinator.shouldRequestFocus(sessionID: sessionID, isActive: true) == true)
        coordinator.resignFocusTracking()
        #expect(coordinator.shouldRequestFocus(sessionID: sessionID, isActive: true) == true)
    }
}