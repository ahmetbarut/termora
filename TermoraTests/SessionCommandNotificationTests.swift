//
//  SessionCommandNotificationTests.swift
//  TermoraTests
//

import AppKit
import Darwin
import Foundation
import SwiftTerm
import Testing
@testable import Termora

/// Records instead of delivering. The real `UserNotificationDeliverer` is never built here:
/// it would ask the running test host for notification permission.
@MainActor
private final class RecordingDeliverer: CommandNotificationDelivering {
    private(set) var delivered: [CommandNotificationMessage] = []

    func requestAuthorization() async -> Bool { true }

    func deliver(_ message: CommandNotificationMessage, identifier: String) async {
        delivered.append(message)
    }
}

/// A profile whose ZDOTDIR is an empty directory, so the developer's own ~/.zshrc cannot make
/// this pty test slow or flaky.
private func makeHermeticProfile(suppressesNotifications: Bool = false) throws -> TerminalProfile {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("TermoraTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var profile = TerminalProfile(
        name: "Hermetic",
        shellPath: "/bin/zsh",
        environment: ["ZDOTDIR": directory.path]
    )
    profile.suppressesCommandNotifications = suppressesNotifications
    return profile
}

@MainActor
struct SessionCommandNotificationTests {

    /// End of a foreground job is signalled with Ctrl-C rather than a timed command.
    ///
    /// The first version of this test ran `sleep 2` and waited for it to finish on its own.
    /// It passed alone and timed out inside the full suite: ~660 `@MainActor` tests share one
    /// main thread, the sampler got starved for longer than the command lived, and the whole
    /// command came and went unobserved. Holding the terminal open until the test itself
    /// decides to release it removes every timing assumption but one — that the command has
    /// been observed at least once, which the test waits for explicitly.
    private static let endOfTextControlCharacter = "\u{03}"

    private func makeStack(
        deliverer: RecordingDeliverer
    ) -> (settings: SettingsStore, manager: SessionManager, profiles: ProfileStore) {
        let suiteName = "TermoraTests.SessionNotifications.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = SettingsStore(defaults: defaults)
        settings.settings.defaultShellPath = "/bin/zsh"
        settings.settings.notifiesOnLongCommands = true
        // The floor of the supported range; the test then keeps the command alive past it.
        settings.settings.longCommandThresholdSeconds = CommandNotificationLimits.thresholdRange.lowerBound

        let profiles = ProfileStore(defaults: defaults)
        let manager = SessionManager(
            settings: settings,
            themes: ThemeStore(),
            profiles: profiles,
            escalationDelay: 0.2,
            notifier: CommandCompletionNotifier(settings: settings, deliverer: deliverer)
        )
        return (settings, manager, profiles)
    }

    /// Yields to the main run loop while waiting — SwiftTerm drains the pty master on the main
    /// queue, so a blocking sleep would stall the shell. `tick` steps the sampler by hand so
    /// the test does not depend on the manager's own one-second loop getting scheduled.
    private func poll(
        timeout: Duration = .seconds(60),
        tick: @MainActor () -> Void,
        until condition: () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            tick()
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        tick()
        return condition()
    }

    /// Starts a shell running a command that holds the terminal until Ctrl-C, and returns once
    /// the sampler has actually seen that command.
    private func startHeldCommand(
        manager: SessionManager,
        session: TerminalSession
    ) async throws -> TermoraTerminalView {
        let view = try #require(manager.terminalView(for: session.id))
        let shellPID = view.process.shellPid
        let alive = await poll(timeout: .seconds(30), tick: {}) { ProcessProbe.isAlive(pid: shellPID) }
        #expect(alive, "shell başlamadı")

        // Bounded on purpose: if this test dies before its Ctrl-C, the orphan still exits.
        view.send(txt: "sleep 30\n")

        let observed = await poll(tick: { manager.sampleForegroundCommands() }) {
            ForegroundProcessProbe.foregroundCommandName(shellPID: shellPID) == "sleep"
        }
        #expect(observed, "ön plan işi hiç gözlenmedi")
        return view
    }

    /// The whole chain against a real shell: pty -> `ForegroundProcessProbe` -> tracker ->
    /// policy -> deliverer. Everything under it is unit-tested in isolation; this is the only
    /// proof that the pieces are wired to each other.
    @Test func aRealCommandInARealShellProducesANotification() async throws {
        let deliverer = RecordingDeliverer()
        let (_, manager, profiles) = makeStack(deliverer: deliverer)

        let profile = try makeHermeticProfile()
        // `SessionManager` resolves a session's profile out of the store, so a profile that
        // only exists on the stack would never reach the policy.
        profiles.profiles.append(profile)
        let session = manager.createSession(profile: profile, workingDirectory: NSHomeDirectory())
        defer { manager.terminateSession(id: session.id) }

        let view = try await startHeldCommand(manager: manager, session: session)

        // Hold it past the one-second threshold, sampling throughout.
        let heldUntil = ContinuousClock.now + .milliseconds(1500)
        _ = await poll(tick: { manager.sampleForegroundCommands() }) { ContinuousClock.now >= heldUntil }

        view.send(txt: Self.endOfTextControlCharacter)

        let notified = await poll(tick: { manager.sampleForegroundCommands() }) {
            !deliverer.delivered.isEmpty
        }
        #expect(notified, "uzun süren komut için bildirim üretilmedi")
        #expect(deliverer.delivered.first?.title == "sleep")
        // Honest wording: the shell reaped the exit status, Termora never saw it.
        #expect(deliverer.delivered.first?.body.hasPrefix("Completed in ") == true)
        #expect(deliverer.delivered.first?.body.contains("successfully") == false)
    }

    /// briefs/2: profil bazında kapatılabilmeli — end to end, not just inside the policy.
    @Test func aProfileWithNotificationsOffStaysSilentAgainstARealShell() async throws {
        let deliverer = RecordingDeliverer()
        let (_, manager, profiles) = makeStack(deliverer: deliverer)

        let profile = try makeHermeticProfile(suppressesNotifications: true)
        profiles.profiles.append(profile)
        let session = manager.createSession(profile: profile, workingDirectory: NSHomeDirectory())
        defer { manager.terminateSession(id: session.id) }

        let view = try await startHeldCommand(manager: manager, session: session)

        let heldUntil = ContinuousClock.now + .milliseconds(1500)
        _ = await poll(tick: { manager.sampleForegroundCommands() }) { ContinuousClock.now >= heldUntil }

        view.send(txt: Self.endOfTextControlCharacter)

        // Wait for the shell to take the terminal back — the same moment that would have
        // produced a notification for an unsuppressed profile — and then some.
        let shellPID = view.process.shellPid
        _ = await poll(tick: { manager.sampleForegroundCommands() }) {
            ForegroundProcessProbe.foregroundCommandName(shellPID: shellPID) == nil
        }
        let settleUntil = ContinuousClock.now + .milliseconds(500)
        _ = await poll(tick: { manager.sampleForegroundCommands() }) { ContinuousClock.now >= settleUntil }

        #expect(deliverer.delivered.isEmpty)
    }
}
