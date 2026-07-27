//
//  TerminalSessionTests.swift
//  TermoraTests
//

import Foundation
import Testing
@testable import Termora

@MainActor
struct TerminalSessionTests {

    @Test func initialisesWithRunningStateAndEmptyTitle() {
        let session = TerminalSession(shellPath: "/bin/zsh")

        #expect(session.shellPath == "/bin/zsh")
        #expect(session.profileID == nil)
        #expect(session.workingDirectory == nil)
        #expect(session.title == "")
        #expect(session.processState == .running)
        #expect(session.launchFailure == nil)
    }

    @Test func keepsTheIdentityAndOptionalArgumentsItWasGiven() {
        let id = UUID()
        let profileID = UUID()
        let session = TerminalSession(
            id: id,
            shellPath: "/bin/bash",
            profileID: profileID,
            workingDirectory: "/tmp"
        )

        #expect(session.id == id)
        #expect(session.shellPath == "/bin/bash")
        #expect(session.profileID == profileID)
        #expect(session.workingDirectory == "/tmp")
    }

    @Test func exitedStateCarriesADecodedExitStatus() {
        let session = TerminalSession(shellPath: "/bin/zsh")

        session.processState = .exited(ExitStatus(rawStatus: 256))

        #expect(session.processState == .exited(ExitStatus(rawStatus: 256)))
        #expect(session.processState != .running)

        guard case .exited(let status) = session.processState else {
            Issue.record("processState should be .exited")
            return
        }
        #expect(status.exitCode == 1)
        #expect(status.signal == nil)
    }

    @Test func signalledExitIsDistinguishableFromANormalExit() {
        let session = TerminalSession(shellPath: "/bin/zsh")

        session.processState = .exited(ExitStatus(rawStatus: SIGKILL))

        guard case .exited(let status) = session.processState else {
            Issue.record("processState should be .exited")
            return
        }
        #expect(status.signal == SIGKILL)
        #expect(status.exitCode == nil)
    }
}
