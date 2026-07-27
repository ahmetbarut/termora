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

// MARK: - Test helpers

/// Fresh store stack on an isolated UserDefaults suite so tests never see (or leave) real settings.
@MainActor
private func makeStack(escalationDelay: TimeInterval = 1.5) -> (settings: SettingsStore, manager: SessionManager) {
    // Swift Testing runs these tests in parallel by default, so the suite name must be unique
    // per call: a shared suite would let one test wipe another test's defaultShellPath.
    let suiteName = "TermoraTests.SessionManager.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let settings = SettingsStore(defaults: defaults)
    settings.settings.defaultShellPath = "/bin/zsh"

    let manager = SessionManager(
        settings: settings,
        themes: ThemeStore(),
        profiles: ProfileStore(defaults: defaults),
        escalationDelay: escalationDelay
    )
    return (settings, manager)
}

/// A profile whose ZDOTDIR points at an empty directory, so the developer's own ~/.zshrc
/// cannot make these PTY tests slow or flaky.
private func makeHermeticProfile() throws -> TerminalProfile {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("TermoraTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return TerminalProfile(
        name: "Hermetic",
        shellPath: "/bin/zsh",
        environment: ["ZDOTDIR": directory.path]
    )
}

/// Polls `condition` while yielding to the main run loop — SwiftTerm drains the PTY master
/// on the main queue, so a blocking sleep here would stall the shell and hang the test.
@MainActor
private func poll(timeout: Duration = .seconds(10), until condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(100))
    }
    return condition()
}

@MainActor
struct SessionManagerTests {

    @Test func createSessionRegistersBothTheSessionAndItsView() throws {
        let (_, manager) = makeStack()
        let session = manager.createSession(profile: try makeHermeticProfile(), workingDirectory: nil)
        defer { manager.terminateSession(id: session.id) }

        #expect(manager.session(id: session.id)?.shellPath == "/bin/zsh")
        #expect(manager.session(id: session.id)?.processState == .running)

        let view = try #require(manager.terminalView(for: session.id))
        #expect(view.sessionID == session.id)
        #expect(view.process.shellPid > 0)
        #expect(view.process.childfd >= 0)

        #expect(manager.terminalView(for: UUID()) == nil)
        #expect(manager.session(id: UUID()) == nil)
    }

    @Test func anIdleShellIsNotBusyButAForegroundCommandIs() async throws {
        let (_, manager) = makeStack()
        let session = manager.createSession(profile: try makeHermeticProfile(), workingDirectory: nil)
        defer { manager.terminateSession(id: session.id) }
        let view = try #require(manager.terminalView(for: session.id))

        let becameIdle = await poll { manager.hasRunningProcess(sessionID: session.id) == false }
        #expect(becameIdle, "an idle shell must not report a foreground job")

        view.send(txt: "sleep 5\n")

        let becameBusy = await poll { manager.hasRunningProcess(sessionID: session.id) }
        #expect(becameBusy, "`sleep 5` must show up as a foreground job")
    }

    @Test func terminateSessionKillsTheShellAndDropsItFromTheCache() async throws {
        let (_, manager) = makeStack(escalationDelay: 0.05)
        let session = manager.createSession(profile: try makeHermeticProfile(), workingDirectory: nil)
        let view = try #require(manager.terminalView(for: session.id))
        let pid = view.process.shellPid

        let started = await poll { ProcessProbe.isAlive(pid: pid) }
        #expect(started)

        manager.terminateSession(id: session.id)

        #expect(manager.terminalView(for: session.id) == nil)
        #expect(manager.session(id: session.id) == nil)
        #expect(manager.hasRunningProcess(sessionID: session.id) == false)

        let died = await poll { ProcessProbe.isAlive(pid: pid) == false }
        #expect(died, "SIGTERM/SIGKILL escalation must reap the shell")
    }

    @Test func terminatingAnUnknownSessionIsAHarmlessNoOp() {
        let (_, manager) = makeStack()
        manager.terminateSession(id: UUID())
    }

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
