//
//  TermoraTerminalViewTests.swift
//  TermoraTests
//

import AppKit
import Foundation
import Testing
@testable import Termora

@MainActor
struct TermoraTerminalViewTests {

    private func makeView(sessionID: UUID = UUID()) -> TermoraTerminalView {
        TermoraTerminalView(
            sessionID: sessionID,
            frame: CGRect(x: 0, y: 0, width: 400, height: 240)
        )
    }

    @Test func remembersItsSessionIdentifier() {
        let id = UUID()
        #expect(makeView(sessionID: id).sessionID == id)
    }

    @Test func swallowsZeroSizedLayoutPasses() {
        let view = makeView()

        view.setFrameSize(NSSize(width: 0, height: 240))
        #expect(view.frame.size == NSSize(width: 400, height: 240))

        view.setFrameSize(NSSize(width: 400, height: 0))
        #expect(view.frame.size == NSSize(width: 400, height: 240))

        view.setFrameSize(NSSize(width: 0, height: 0))
        #expect(view.frame.size == NSSize(width: 400, height: 240))
    }

    @Test func swallowsNegativeSizedLayoutPasses() {
        let view = makeView()

        view.setFrameSize(NSSize(width: -10, height: -10))

        #expect(view.frame.size == NSSize(width: 400, height: 240))
    }

    @Test func acceptsPositiveSizes() {
        let view = makeView()

        view.setFrameSize(NSSize(width: 320, height: 180))

        #expect(view.frame.size == NSSize(width: 320, height: 180))
    }

    @Test func commandShortcutsAreLeftToTheMenu() throws {
        // Spec §7: application shortcuts must not be swallowed by the terminal.
        let view = makeView()
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "t",
            charactersIgnoringModifiers: "t",
            isARepeat: false,
            keyCode: 17
        ))

        #expect(view.performKeyEquivalent(with: event) == false)
    }
}
