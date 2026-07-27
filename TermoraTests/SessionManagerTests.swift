//
//  SessionManagerTests.swift
//  TermoraTests
//

import AppKit
import Darwin
import Foundation
import SwiftTerm
import Testing
@testable import Termora

@MainActor
struct SessionManagerTests {

    @Test func fontResolutionFallsBackToTheMonospacedSystemFont() {
        let expectedFallback = NSFont.monospacedSystemFont(ofSize: 17, weight: .regular)

        let noName = SessionManager.resolveFont(name: nil, size: 13)
        #expect(noName.pointSize == 13)
        #expect(noName.fontName == NSFont.monospacedSystemFont(ofSize: 13, weight: .regular).fontName)

        let emptyName = SessionManager.resolveFont(name: "", size: 17)
        #expect(emptyName.fontName == expectedFallback.fontName)

        let unknownName = SessionManager.resolveFont(name: "ThereIsNoSuchFont-42", size: 17)
        #expect(unknownName.fontName == expectedFallback.fontName)
        #expect(unknownName.pointSize == 17)
    }

    @Test func fontResolutionHonoursAnInstalledFont() {
        let menlo = SessionManager.resolveFont(name: "Menlo-Regular", size: 15)

        #expect(menlo.fontName == "Menlo-Regular")
        #expect(menlo.pointSize == 15)
    }

    @Test func hostDirectoryReportsAreParsedIntoPlainPaths() {
        #expect(SessionManager.workingDirectory(fromHostReport: "file:///private/tmp") == "/private/tmp")
        #expect(SessionManager.workingDirectory(fromHostReport: "file://localhost/usr/local") == "/usr/local")
        #expect(SessionManager.workingDirectory(fromHostReport: "/Users/test/dev") == "/Users/test/dev")
    }

    @Test func unusableHostDirectoryReportsAreIgnored() {
        #expect(SessionManager.workingDirectory(fromHostReport: nil) == nil)
        #expect(SessionManager.workingDirectory(fromHostReport: "") == nil)
        #expect(SessionManager.workingDirectory(fromHostReport: "http://example.com/x") == nil)
    }
}
