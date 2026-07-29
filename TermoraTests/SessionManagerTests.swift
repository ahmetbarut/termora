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

/// Koşul sağlanana kadar girdiyi TEKRAR gönderir.
///
/// Tek seferlik gönderim kırılgandı: kabuk istemi çizmeden gelen girdi yutuluyor ve
/// tam paket koşusunda (aynı anda başka testler de kabuk açarken) bu gerçekten oluyordu.
private func pollSending(timeout: Duration = .seconds(15),
                         _ send: () -> Void,
                         until condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        send()
        // Gönderimden sonra kısa bir aralıkla birkaç kez bakılır; her turda yeniden
        // göndermek gereksiz yere onlarca süreç başlatırdı.
        for _ in 0..<10 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
    return condition()
}

@MainActor
struct SessionManagerTests {

    /// Spec: "Yeni terminal açıldığında kullanıcının home dizininden başlat".
    /// Finder'dan açılan bir GUI uygulamasının cwd'si `/` olduğundan, dizin belirtilmezse
    /// shell onu miras alır ve kullanıcı kendini `/` içinde bulur.
    @Test func aSessionWithoutAConfiguredDirectoryStartsInTheHomeDirectory() async throws {
        let (_, manager) = makeStack()
        let session = manager.createSession(profile: try makeHermeticProfile(), workingDirectory: nil)
        defer { manager.terminateSession(id: session.id) }

        #expect(session.workingDirectory == NSHomeDirectory())

        let view = try #require(manager.terminalView(for: session.id))
        let shellPID = view.process.shellPid
        let reachedHome = await poll {
            ProcessProbe.currentWorkingDirectory(pid: shellPID) == NSHomeDirectory()
        }
        #expect(reachedHome, "shell home dizininde başlamadı")
    }

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

        // Girdi, kabuk istemini çizmeden gönderilirse YUTULUR ve komut hiç çalışmaz.
        // "İstem hazır" durumunu dışarıdan güvenilir biçimde gözlemenin bir yolu yok
        // (`hasRunningProcess` yalnız önplanda iş olup olmadığını söyler, kabuğun okumaya
        // hazır olduğunu değil), bu yüzden gönderim tekrarlanır. `sleep` birden çok kez
        // çalışsa da test aynı şeyi ölçer.
        let becameBusy = await pollSending(
            { view.send(txt: "sleep 5\n") },
            until: { manager.hasRunningProcess(sessionID: session.id) }
        )
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

    @Test func delegateCallbacksAreRoutedByTheViewsSessionIdentifier() throws {
        let (_, manager) = makeStack()
        let session = manager.createSession(profile: try makeHermeticProfile(), workingDirectory: nil)
        defer { manager.terminateSession(id: session.id) }

        // A detached view proves routing goes through `sessionID`, not object identity.
        let detached = TermoraTerminalView(
            sessionID: session.id,
            frame: CGRect(x: 0, y: 0, width: 400, height: 240)
        )

        manager.setTerminalTitle(source: detached, title: "make build")
        #expect(session.title == "make build")

        manager.hostCurrentDirectoryUpdate(source: detached, directory: "file:///private/tmp")
        #expect(session.workingDirectory == "/private/tmp")

        manager.hostCurrentDirectoryUpdate(source: detached, directory: nil)
        #expect(session.workingDirectory == "/private/tmp", "an empty OSC 7 report must not clear the cwd")

        manager.processTerminated(source: detached, exitCode: 256)
        #expect(session.processState == .exited(ExitStatus(rawStatus: 256)))
    }

    @Test func delegateCallbacksFromForeignViewsAreIgnored() throws {
        let (_, manager) = makeStack()
        let session = manager.createSession(profile: try makeHermeticProfile(), workingDirectory: nil)
        defer { manager.terminateSession(id: session.id) }

        let stranger = TermoraTerminalView(
            sessionID: UUID(),
            frame: CGRect(x: 0, y: 0, width: 400, height: 240)
        )

        manager.setTerminalTitle(source: stranger, title: "not mine")
        manager.processTerminated(source: stranger, exitCode: 9)

        #expect(session.title == "")
        #expect(session.processState == .running)
    }

    @Test func appearanceSettingsReachEveryOpenTerminal() throws {
        let (settings, manager) = makeStack()
        let session = manager.createSession(profile: try makeHermeticProfile(), workingDirectory: nil)
        defer { manager.terminateSession(id: session.id) }
        let view = try #require(manager.terminalView(for: session.id))

        settings.settings.fontName = "Menlo-Regular"
        settings.settings.fontSize = 18
        settings.settings.lineSpacing = 1.4
        settings.settings.windowOpacity = 0.8
        manager.applyAppearanceToAllSessions()

        #expect(view.font.fontName == "Menlo-Regular")
        #expect(view.font.pointSize == 18)
        #expect(view.lineSpacing == 1.4)
        #expect(abs(view.nativeBackgroundColor.alphaComponent - 0.8) < 0.001)

        settings.settings.windowOpacity = 1.0
        manager.applyAppearanceToAllSessions()
        #expect(abs(view.nativeBackgroundColor.alphaComponent - 1.0) < 0.001)
    }

    @Test func restartSessionPutsAFreshShellBehindTheSameIdentifier() async throws {
        let (_, manager) = makeStack(escalationDelay: 0.05)
        let session = manager.createSession(profile: try makeHermeticProfile(), workingDirectory: nil)
        defer { manager.terminateSession(id: session.id) }

        let firstView = try #require(manager.terminalView(for: session.id))
        let firstPID = firstView.process.shellPid
        let firstStarted = await poll { ProcessProbe.isAlive(pid: firstPID) }
        #expect(firstStarted)

        // The shell exited on its own; the pane is still there and asks for a new one.
        session.processState = .exited(ExitStatus(rawStatus: 0))
        manager.restartSession(id: session.id, forceDefaultShell: false)

        let secondView = try #require(manager.terminalView(for: session.id))
        #expect(secondView !== firstView, "restart must install a brand new view")
        #expect(secondView.sessionID == session.id)
        #expect(manager.session(id: session.id) === session, "the session object must survive")
        #expect(session.processState == .running)
        #expect(session.launchFailure == nil)
        #expect(session.restartGeneration == 1, "the pane keys its host view on this")

        let secondPID = secondView.process.shellPid
        #expect(secondPID > 0)
        #expect(secondPID != firstPID)

        let restarted = await poll { ProcessProbe.isAlive(pid: secondPID) }
        #expect(restarted, "the replacement shell must be running")

        let oldOneDied = await poll { ProcessProbe.isAlive(pid: firstPID) == false }
        #expect(oldOneDied, "the old shell must be reaped, not leaked")
    }

    @Test func aBrokenShellPathIsRecordedAndRecoverableWithTheDefaultShell() async throws {
        let (settings, manager) = makeStack(escalationDelay: 0.05)
        settings.settings.defaultShellPath = "/nonexistent/shell"

        let session = manager.createSession(profile: nil, workingDirectory: nil)
        defer { manager.terminateSession(id: session.id) }

        #expect(session.launchFailure == "/nonexistent/shell")
        #expect(session.processState == .exited(ExitStatus(rawStatus: 127 << 8)))
        #expect((manager.terminalView(for: session.id)?.process.shellPid ?? 0) <= 0)

        // §8 recovery action: ignore the broken setting and come up on the login shell.
        manager.restartSession(id: session.id, forceDefaultShell: true)

        #expect(session.launchFailure == nil)
        #expect(session.processState == .running)
        #expect(session.shellPath == ShellService.defaultShellPath())

        let view = try #require(manager.terminalView(for: session.id))
        let alive = await poll { ProcessProbe.isAlive(pid: view.process.shellPid) }
        #expect(alive, "the default shell must come up even though the setting is broken")
    }

    @Test func restartingAnUnknownSessionIsAHarmlessNoOp() {
        let (_, manager) = makeStack()
        manager.restartSession(id: UUID(), forceDefaultShell: false)
        manager.restartSession(id: UUID(), forceDefaultShell: true)
    }
}
