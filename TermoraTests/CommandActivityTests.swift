//
//  CommandActivityTests.swift
//  TermoraTests
//

import Foundation
import Testing
@testable import Termora

@MainActor
@Suite struct CommandActivityTests {

    private static let epoch = Date(timeIntervalSince1970: 1_000_000)

    private func activity(
        command: String = "npm",
        seconds: TimeInterval = 60,
        outcome: CommandOutcome = .unknown,
        sessionID: UUID = UUID()
    ) -> CommandActivity {
        CommandActivity(
            sessionID: sessionID,
            command: command,
            startedAt: Self.epoch,
            finishedAt: Self.epoch.addingTimeInterval(seconds),
            outcome: outcome
        )
    }

    // MARK: - Duration

    @Test func durationIsTheDistanceBetweenStartAndFinish() {
        #expect(Double(activity(seconds: 258).duration) == 258)
    }

    /// Wall-clock jumps (NTP, sleep/wake) can hand us a finish that precedes the start.
    /// A negative duration would slip under every threshold check and, worse, render as
    /// "-3s" in the notification body.
    @Test func durationNeverGoesNegative() {
        let backwards = CommandActivity(
            sessionID: UUID(),
            command: "npm",
            startedAt: Self.epoch,
            finishedAt: Self.epoch.addingTimeInterval(-30),
            outcome: .unknown
        )
        #expect(Double(backwards.duration) == 0)
    }

    // MARK: - Duration formatting

    @Test func durationFormatterMatchesTheBriefExample() {
        #expect(CommandDurationFormatter.short(258) == "4m 18s")
    }

    @Test func durationFormatterUsesAtMostTwoUnits() {
        #expect(CommandDurationFormatter.short(0) == "0s")
        #expect(CommandDurationFormatter.short(45) == "45s")
        #expect(CommandDurationFormatter.short(59.4) == "59s")
        #expect(CommandDurationFormatter.short(60) == "1m")
        #expect(CommandDurationFormatter.short(240) == "4m")
        #expect(CommandDurationFormatter.short(3600) == "1h")
        #expect(CommandDurationFormatter.short(3725) == "1h 2m")
    }

    /// Rounds to the nearest second so 59.6 s never prints as "59s" next to a 1m sibling.
    @Test func durationFormatterRoundsToTheNearestSecond() {
        #expect(CommandDurationFormatter.short(59.6) == "1m")
        #expect(CommandDurationFormatter.short(1.4) == "1s")
    }

    /// A non-finite duration would trap inside `Int(_:)`. The formatter is fed by a
    /// `Date` subtraction, which can produce NaN if a date is itself non-finite.
    @Test func durationFormatterSurvivesNonFiniteInput() {
        #expect(CommandDurationFormatter.short(.nan) == "0s")
        #expect(CommandDurationFormatter.short(.infinity) == "0s")
        #expect(CommandDurationFormatter.short(-5) == "0s")
    }

    // MARK: - Notification text

    /// The probe cannot see an exit status, so the honest wording is "Completed", never
    /// "Completed successfully" (see the brief's example, which we deliberately do not copy).
    @Test func unknownOutcomeIsAnnouncedWithoutClaimingSuccess() {
        let message = CommandNotificationText.message(for: activity(command: "npm", seconds: 258))
        #expect(message.title == "npm")
        #expect(message.body == "Completed in 4m 18s")
        #expect(!message.body.contains("successfully"))
    }

    @Test func succeededOutcomeSaysSuccessfully() {
        let message = CommandNotificationText.message(
            for: activity(command: "npm", seconds: 258, outcome: .succeeded))
        #expect(message.body == "Completed successfully in 4m 18s")
    }

    @Test func failedOutcomeNamesTheExitCodeWhenItIsKnown() {
        let withCode = CommandNotificationText.message(
            for: activity(command: "cargo", seconds: 90, outcome: .failed(exitCode: 101)))
        #expect(withCode.title == "cargo")
        #expect(withCode.body == "Failed with exit code 101 after 1m 30s")

        let withoutCode = CommandNotificationText.message(
            for: activity(command: "cargo", seconds: 90, outcome: .failed(exitCode: nil)))
        #expect(withoutCode.body == "Failed after 1m 30s")
    }

    /// The notification identifier must not collide between two commands finishing in the
    /// same session — UNUserNotificationCenter replaces a notification that reuses an id.
    @Test func notificationIdentifierIsUniquePerFinish() {
        let sessionID = UUID()
        let first = activity(seconds: 60, sessionID: sessionID)
        let second = activity(seconds: 120, sessionID: sessionID)
        #expect(first.notificationIdentifier != second.notificationIdentifier)
        #expect(first.notificationIdentifier == activity(seconds: 60, sessionID: sessionID).notificationIdentifier)
    }

    // MARK: - Threshold limits

    @Test func thresholdIsClampedIntoTheSupportedRange() {
        #expect(Double(CommandNotificationLimits.clampThreshold(0)) == Double(CommandNotificationLimits.thresholdRange.lowerBound))
        #expect(Double(CommandNotificationLimits.clampThreshold(-10)) == Double(CommandNotificationLimits.thresholdRange.lowerBound))
        #expect(Double(CommandNotificationLimits.clampThreshold(99_999)) == Double(CommandNotificationLimits.thresholdRange.upperBound))
        #expect(Double(CommandNotificationLimits.clampThreshold(30)) == 30)
    }

    @Test func thresholdClampFallsBackOnNonFiniteInput() {
        #expect(Double(CommandNotificationLimits.clampThreshold(.nan)) == Double(CommandNotificationLimits.defaultThreshold))
    }

    @Test func thresholdParsesFromTextAndFallsBack() {
        #expect(Double(CommandNotificationLimits.threshold(fromText: "120", fallback: 30)) == 120)
        #expect(Double(CommandNotificationLimits.threshold(fromText: " 45 ", fallback: 30)) == 45)
        #expect(Double(CommandNotificationLimits.threshold(fromText: "abc", fallback: 30)) == 30)
        #expect(Double(CommandNotificationLimits.threshold(fromText: "999999", fallback: 30)) == Double(CommandNotificationLimits.thresholdRange.upperBound))
    }
}

// MARK: - Tracker

@MainActor
@Suite struct CommandActivityTrackerTests {

    private static let epoch = Date(timeIntervalSince1970: 1_000_000)

    @Test func aCommandThatIsStillRunningEmitsNothing() {
        var tracker = CommandActivityTracker()
        let session = UUID()
        #expect(tracker.observe(sessionID: session, foregroundCommand: "npm", at: Self.epoch) == nil)
        #expect(tracker.observe(sessionID: session, foregroundCommand: "npm", at: Self.epoch + 10) == nil)
    }

    /// The foreground process group going away is the moment a command ends (brief).
    @Test func theForegroundJobDisappearingEndsTheCommand() throws {
        var tracker = CommandActivityTracker()
        let session = UUID()
        _ = tracker.observe(sessionID: session, foregroundCommand: "npm", at: Self.epoch)
        // `#require` cannot wrap a mutating call: the macro captures the expression and the
        // tracker becomes immutable inside it. Hoisting keeps the mutation outside.
        let sample = tracker.observe(sessionID: session, foregroundCommand: nil, at: Self.epoch + 258)
        let finished = try #require(sample)
        #expect(finished.command == "npm")
        #expect(finished.sessionID == session)
        #expect(Double(finished.duration) == 258)
        // The probe watches process groups, not waitpid: the outcome is genuinely unknown.
        #expect(finished.outcome == .unknown)
    }

    /// Back-to-back commands (`make && ./run`) never show an idle shell between them, so a
    /// changed foreground name has to close the previous command and open the next one.
    @Test func aChangedForegroundCommandClosesThePreviousOne() throws {
        var tracker = CommandActivityTracker()
        let session = UUID()
        _ = tracker.observe(sessionID: session, foregroundCommand: "make", at: Self.epoch)
        let firstSample = tracker.observe(sessionID: session, foregroundCommand: "run", at: Self.epoch + 30)
        let finished = try #require(firstSample)
        #expect(finished.command == "make")
        #expect(Double(finished.duration) == 30)

        let secondSample = tracker.observe(sessionID: session, foregroundCommand: nil, at: Self.epoch + 50)
        let second = try #require(secondSample)
        #expect(second.command == "run")
        #expect(Double(second.duration) == 20)
    }

    @Test func anIdleShellEmitsNothing() {
        var tracker = CommandActivityTracker()
        #expect(tracker.observe(sessionID: UUID(), foregroundCommand: nil, at: Self.epoch) == nil)
    }

    /// A blank name from libproc must not become a tracked "command" whose completion is
    /// later announced as an empty notification title.
    @Test func blankCommandNamesAreTreatedAsIdle() {
        var tracker = CommandActivityTracker()
        let session = UUID()
        #expect(tracker.observe(sessionID: session, foregroundCommand: "   ", at: Self.epoch) == nil)
        #expect(tracker.observe(sessionID: session, foregroundCommand: nil, at: Self.epoch + 60) == nil)
    }

    @Test func sessionsAreTrackedIndependently() throws {
        var tracker = CommandActivityTracker()
        let a = UUID()
        let b = UUID()
        _ = tracker.observe(sessionID: a, foregroundCommand: "npm", at: Self.epoch)
        _ = tracker.observe(sessionID: b, foregroundCommand: "cargo", at: Self.epoch + 5)
        #expect(tracker.observe(sessionID: a, foregroundCommand: nil, at: Self.epoch + 10)?.command == "npm")
        let cargoSample = tracker.observe(sessionID: b, foregroundCommand: nil, at: Self.epoch + 25)
        let cargo = try #require(cargoSample)
        #expect(cargo.command == "cargo")
        #expect(Double(cargo.duration) == 20)
    }

    /// Closing the pane is not a command completing. Announcing "npm completed" right after
    /// the user killed the tab would be a lie about a process they just terminated.
    @Test func forgettingASessionDropsItsRunningCommandSilently() {
        var tracker = CommandActivityTracker()
        let session = UUID()
        _ = tracker.observe(sessionID: session, foregroundCommand: "npm", at: Self.epoch)
        tracker.forget(sessionID: session)
        #expect(tracker.trackedCommandCount == 0)
        #expect(tracker.observe(sessionID: session, foregroundCommand: nil, at: Self.epoch + 60) == nil)
    }

    @Test func trackedCommandCountReflectsRunningCommandsOnly() {
        var tracker = CommandActivityTracker()
        let session = UUID()
        _ = tracker.observe(sessionID: session, foregroundCommand: "npm", at: Self.epoch)
        #expect(tracker.trackedCommandCount == 1)
        _ = tracker.observe(sessionID: session, foregroundCommand: nil, at: Self.epoch + 1)
        #expect(tracker.trackedCommandCount == 0)
    }
}
