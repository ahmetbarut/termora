//
//  CommandCompletionNotifierTests.swift
//  TermoraTests
//

import Foundation
import Testing
@testable import Termora

// MARK: - Pure decision

@MainActor
@Suite struct CommandCompletionPolicyTests {

    private static let epoch = Date(timeIntervalSince1970: 1_000_000)

    private func activity(seconds: TimeInterval = 60, outcome: CommandOutcome = .unknown) -> CommandActivity {
        CommandActivity(
            sessionID: UUID(),
            command: "npm",
            startedAt: Self.epoch,
            finishedAt: Self.epoch.addingTimeInterval(seconds),
            outcome: outcome
        )
    }

    /// Notifications on, defaults otherwise.
    private func enabledSettings() -> AppSettings {
        var settings = AppSettings()
        settings.notifiesOnLongCommands = true
        return settings
    }

    @Test func nothingIsAnnouncedWhileTheFeatureIsOff() {
        let decision = CommandCompletionPolicy.decide(
            activity: activity(seconds: 600),
            settings: AppSettings(),
            profile: nil,
            isTerminalVisibleToUser: false
        )
        #expect(decision == .suppressedNotificationsDisabled)
    }

    @Test func aLongCommandInABackgroundWindowIsAnnounced() {
        let decision = CommandCompletionPolicy.decide(
            activity: activity(seconds: 600),
            settings: enabledSettings(),
            profile: nil,
            isTerminalVisibleToUser: false
        )
        #expect(decision == .notify)
    }

    // MARK: Threshold

    @Test func commandsShorterThanTheThresholdAreNotAnnounced() {
        var settings = enabledSettings()
        settings.longCommandThresholdSeconds = 30
        let decision = CommandCompletionPolicy.decide(
            activity: activity(seconds: 29.9),
            settings: settings,
            profile: nil,
            isTerminalVisibleToUser: false
        )
        #expect(decision == .suppressedShorterThanThreshold)
    }

    /// The threshold is a minimum, not an exclusive bound: a command that ran exactly as
    /// long as the user asked for is announced.
    @Test func aCommandExactlyAtTheThresholdIsAnnounced() {
        var settings = enabledSettings()
        settings.longCommandThresholdSeconds = 30
        let decision = CommandCompletionPolicy.decide(
            activity: activity(seconds: 30),
            settings: settings,
            profile: nil,
            isTerminalVisibleToUser: false
        )
        #expect(decision == .notify)
    }

    /// A hand-edited or corrupt settings blob must not disable the feature by accident:
    /// the stored threshold goes through the same clamp the UI uses.
    @Test func anOutOfRangeStoredThresholdIsClamped() {
        var settings = enabledSettings()
        settings.longCommandThresholdSeconds = -100
        let decision = CommandCompletionPolicy.decide(
            activity: activity(seconds: 5),
            settings: settings,
            profile: nil,
            isTerminalVisibleToUser: false
        )
        #expect(decision == .notify)
    }

    // MARK: Outcome

    @Test func successNotificationsCanBeTurnedOffOnTheirOwn() {
        var settings = enabledSettings()
        settings.notifiesOnCommandSuccess = false
        settings.notifiesOnCommandFailure = true

        #expect(CommandCompletionPolicy.decide(
            activity: activity(seconds: 600, outcome: .succeeded),
            settings: settings, profile: nil, isTerminalVisibleToUser: false) == .suppressedOutcomeNotSelected)
        #expect(CommandCompletionPolicy.decide(
            activity: activity(seconds: 600, outcome: .failed(exitCode: 1)),
            settings: settings, profile: nil, isTerminalVisibleToUser: false) == .notify)
    }

    @Test func failureNotificationsCanBeTurnedOffOnTheirOwn() {
        var settings = enabledSettings()
        settings.notifiesOnCommandSuccess = true
        settings.notifiesOnCommandFailure = false

        #expect(CommandCompletionPolicy.decide(
            activity: activity(seconds: 600, outcome: .failed(exitCode: 1)),
            settings: settings, profile: nil, isTerminalVisibleToUser: false) == .suppressedOutcomeNotSelected)
        #expect(CommandCompletionPolicy.decide(
            activity: activity(seconds: 600, outcome: .succeeded),
            settings: settings, profile: nil, isTerminalVisibleToUser: false) == .notify)
    }

    /// The probe cannot prove failure, so an unknown outcome rides the "completed" switch.
    /// Putting it on the failure switch would announce every command to a user who asked
    /// to hear about failures only.
    @Test func anUnknownOutcomeFollowsTheCompletedSwitch() {
        var settings = enabledSettings()
        settings.notifiesOnCommandSuccess = false
        settings.notifiesOnCommandFailure = true
        #expect(CommandCompletionPolicy.decide(
            activity: activity(seconds: 600, outcome: .unknown),
            settings: settings, profile: nil, isTerminalVisibleToUser: false) == .suppressedOutcomeNotSelected)

        settings.notifiesOnCommandSuccess = true
        settings.notifiesOnCommandFailure = false
        #expect(CommandCompletionPolicy.decide(
            activity: activity(seconds: 600, outcome: .unknown),
            settings: settings, profile: nil, isTerminalVisibleToUser: false) == .notify)
    }

    // MARK: Profile

    @Test func aProfileCanTurnNotificationsOffForItsOwnSessions() {
        var profile = TerminalProfile(name: "Watch")
        profile.suppressesCommandNotifications = true
        let decision = CommandCompletionPolicy.decide(
            activity: activity(seconds: 600),
            settings: enabledSettings(),
            profile: profile,
            isTerminalVisibleToUser: false
        )
        #expect(decision == .suppressedByProfile)
    }

    @Test func aProfileWithoutTheOverrideInheritsTheGlobalSetting() {
        let decision = CommandCompletionPolicy.decide(
            activity: activity(seconds: 600),
            settings: enabledSettings(),
            profile: TerminalProfile(name: "Plain"),
            isTerminalVisibleToUser: false
        )
        #expect(decision == .notify)
    }

    // MARK: Foreground

    /// A banner about a command whose output the user is already staring at is pure noise,
    /// so a visible pane in the key window of an active app suppresses it. A pane in another
    /// tab or another window is NOT visible and is still announced.
    @Test func aCommandTheUserIsWatchingIsNotAnnounced() {
        let decision = CommandCompletionPolicy.decide(
            activity: activity(seconds: 600),
            settings: enabledSettings(),
            profile: nil,
            isTerminalVisibleToUser: true
        )
        #expect(decision == .suppressedUserIsWatching)
    }
}

// MARK: - Delivery

/// Stands in for `UNUserNotificationCenter`. The real deliverer is never constructed in
/// tests: it would ask the running test host for notification permission.
@MainActor
private final class FakeDeliverer: CommandNotificationDelivering {
    var authorizationAnswer = true
    private(set) var authorizationRequests = 0
    private(set) var delivered: [(message: CommandNotificationMessage, identifier: String)] = []

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return authorizationAnswer
    }

    func deliver(_ message: CommandNotificationMessage, identifier: String) async {
        delivered.append((message, identifier))
    }
}

@MainActor
@Suite struct CommandCompletionNotifierTests {

    private static let epoch = Date(timeIntervalSince1970: 1_000_000)

    private func makeStore(configure: (inout AppSettings) -> Void = { _ in }) -> SettingsStore {
        let suiteName = "TermoraTests.Notifier.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: defaults)
        var settings = store.settings
        settings.notifiesOnLongCommands = true
        settings.longCommandThresholdSeconds = 30
        configure(&settings)
        store.settings = settings
        return store
    }

    @Test func aFinishedLongCommandIsDeliveredOnce() async throws {
        let deliverer = FakeDeliverer()
        let notifier = CommandCompletionNotifier(settings: makeStore(), deliverer: deliverer)
        let session = UUID()

        #expect(notifier.sample(sessionID: session, foregroundCommand: "npm",
                                profile: nil, isTerminalVisibleToUser: false, now: Self.epoch) == nil)
        let decision = notifier.sample(sessionID: session, foregroundCommand: nil,
                                       profile: nil, isTerminalVisibleToUser: false,
                                       now: Self.epoch + 258)
        #expect(decision == .notify)

        await notifier.deliverPending()
        #expect(deliverer.delivered.count == 1)
        #expect(deliverer.delivered.first?.message.title == "npm")
        #expect(deliverer.delivered.first?.message.body == "Completed in 4m 18s")
    }

    @Test func aShortCommandIsNeverDelivered() async {
        let deliverer = FakeDeliverer()
        let notifier = CommandCompletionNotifier(settings: makeStore(), deliverer: deliverer)
        let session = UUID()
        _ = notifier.sample(sessionID: session, foregroundCommand: "ls",
                            profile: nil, isTerminalVisibleToUser: false, now: Self.epoch)
        let decision = notifier.sample(sessionID: session, foregroundCommand: nil,
                                       profile: nil, isTerminalVisibleToUser: false, now: Self.epoch + 2)
        #expect(decision == .suppressedShorterThanThreshold)

        await notifier.deliverPending()
        #expect(deliverer.delivered.isEmpty)
        // Nothing to announce means nothing to ask permission for (brief: ask on first
        // notification, not at launch).
        #expect(deliverer.authorizationRequests == 0)
    }

    /// The permission sheet is a modal interruption; it is worth showing exactly once, at
    /// the moment the user would actually have received something.
    @Test func permissionIsRequestedOnlyOnceAndOnlyOnTheFirstRealNotification() async {
        let deliverer = FakeDeliverer()
        let notifier = CommandCompletionNotifier(settings: makeStore(), deliverer: deliverer)
        #expect(notifier.authorization == .notRequested)

        for index in 0..<3 {
            let session = UUID()
            let start = Self.epoch + Double(index) * 1000
            _ = notifier.sample(sessionID: session, foregroundCommand: "npm",
                                profile: nil, isTerminalVisibleToUser: false, now: start)
            _ = notifier.sample(sessionID: session, foregroundCommand: nil,
                                profile: nil, isTerminalVisibleToUser: false, now: start + 60)
            await notifier.deliverPending()
        }

        #expect(deliverer.authorizationRequests == 1)
        #expect(notifier.authorization == .granted)
        #expect(deliverer.delivered.count == 3)
    }

    /// Denied permission is not an error the user should see again — the feature just goes
    /// quiet, and we stop asking for the rest of the launch.
    @Test func aDeniedPermissionSilencesTheFeatureWithoutAskingAgain() async {
        let deliverer = FakeDeliverer()
        deliverer.authorizationAnswer = false
        let notifier = CommandCompletionNotifier(settings: makeStore(), deliverer: deliverer)

        for index in 0..<3 {
            let session = UUID()
            let start = Self.epoch + Double(index) * 1000
            _ = notifier.sample(sessionID: session, foregroundCommand: "npm",
                                profile: nil, isTerminalVisibleToUser: false, now: start)
            _ = notifier.sample(sessionID: session, foregroundCommand: nil,
                                profile: nil, isTerminalVisibleToUser: false, now: start + 60)
            await notifier.deliverPending()
        }

        #expect(deliverer.authorizationRequests == 1)
        #expect(notifier.authorization == .denied)
        #expect(deliverer.delivered.isEmpty)
    }

    @Test func aProfileWithNotificationsOffIsSilent() async {
        let deliverer = FakeDeliverer()
        let notifier = CommandCompletionNotifier(settings: makeStore(), deliverer: deliverer)
        var profile = TerminalProfile(name: "Quiet")
        profile.suppressesCommandNotifications = true
        let session = UUID()

        _ = notifier.sample(sessionID: session, foregroundCommand: "npm",
                            profile: profile, isTerminalVisibleToUser: false, now: Self.epoch)
        let decision = notifier.sample(sessionID: session, foregroundCommand: nil,
                                       profile: profile, isTerminalVisibleToUser: false,
                                       now: Self.epoch + 600)
        #expect(decision == .suppressedByProfile)
        await notifier.deliverPending()
        #expect(deliverer.delivered.isEmpty)
    }

    @Test func closingASessionDropsItsRunningCommand() async {
        let deliverer = FakeDeliverer()
        let notifier = CommandCompletionNotifier(settings: makeStore(), deliverer: deliverer)
        let session = UUID()

        _ = notifier.sample(sessionID: session, foregroundCommand: "npm",
                            profile: nil, isTerminalVisibleToUser: false, now: Self.epoch)
        notifier.sessionEnded(sessionID: session)
        let decision = notifier.sample(sessionID: session, foregroundCommand: nil,
                                       profile: nil, isTerminalVisibleToUser: false,
                                       now: Self.epoch + 600)
        #expect(decision == nil)
        await notifier.deliverPending()
        #expect(deliverer.delivered.isEmpty)
    }

    /// A user who comes back after an hour should not be buried under a backlog; the queue
    /// is bounded and keeps the newest entries.
    @Test func thePendingQueueIsBounded() async {
        let deliverer = FakeDeliverer()
        deliverer.authorizationAnswer = true
        let notifier = CommandCompletionNotifier(settings: makeStore(), deliverer: deliverer)

        let overflow = CommandCompletionNotifier.maximumPendingNotifications + 5
        for index in 0..<overflow {
            let session = UUID()
            let start = Self.epoch + Double(index) * 1000
            _ = notifier.sample(sessionID: session, foregroundCommand: "cmd\(index)",
                                profile: nil, isTerminalVisibleToUser: false, now: start)
            _ = notifier.sample(sessionID: session, foregroundCommand: nil,
                                profile: nil, isTerminalVisibleToUser: false, now: start + 60)
        }
        #expect(notifier.pendingCount == CommandCompletionNotifier.maximumPendingNotifications)

        await notifier.deliverPending()
        #expect(deliverer.delivered.count == CommandCompletionNotifier.maximumPendingNotifications)
        // Oldest entries were dropped, so the last command must still be in there.
        #expect(deliverer.delivered.last?.message.title == "cmd\(overflow - 1)")
    }

    @Test func identifiersAreDistinctSoNotificationsDoNotReplaceEachOther() async {
        let deliverer = FakeDeliverer()
        let notifier = CommandCompletionNotifier(settings: makeStore(), deliverer: deliverer)
        let session = UUID()

        _ = notifier.sample(sessionID: session, foregroundCommand: "make",
                            profile: nil, isTerminalVisibleToUser: false, now: Self.epoch)
        _ = notifier.sample(sessionID: session, foregroundCommand: "test",
                            profile: nil, isTerminalVisibleToUser: false, now: Self.epoch + 100)
        _ = notifier.sample(sessionID: session, foregroundCommand: nil,
                            profile: nil, isTerminalVisibleToUser: false, now: Self.epoch + 300)
        await notifier.deliverPending()

        #expect(deliverer.delivered.count == 2)
        let identifiers = Set(deliverer.delivered.map(\.identifier))
        #expect(identifiers.count == 2)
    }
}
