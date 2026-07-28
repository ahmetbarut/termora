//
//  CommandActivity.swift
//  Termora
//

import Foundation

// MARK: - Outcome

/// How a foreground command ended, as far as Termora can actually tell.
///
/// `.unknown` is the honest answer for everything Termora observes today. Detection runs
/// through `ForegroundProcessProbe`, which reads the pty's foreground process GROUP — not
/// `waitpid`. When that group disappears we know the command is over, but its exit status
/// was reaped by the user's shell and never crosses the pty. Claiming success there would
/// be a fabricated status line.
///
/// `.succeeded` / `.failed` exist because the decision logic and the notification wording
/// must already be able to tell them apart (briefs/2: success and failure are separately
/// configurable). A later shell integration — an OSC 133 `D;<exit>` report from the prompt —
/// can start producing them without a single change to the policy below.
enum CommandOutcome: Equatable {
    case unknown
    case succeeded
    case failed(exitCode: Int32?)
}

// MARK: - Activity

/// One foreground command, from the moment it took the terminal to the moment it gave it back.
struct CommandActivity: Equatable {
    let sessionID: UUID
    /// Process name of the foreground process group leader, e.g. `npm`. It is NOT the command
    /// line: libproc hands out `p_comm`/`p_name`, so `npm run build` is only ever seen as `npm`.
    let command: String
    let startedAt: Date
    let finishedAt: Date
    let outcome: CommandOutcome

    /// Clamped at zero: a wall-clock jump (NTP step, sleep/wake) can hand us a finish that
    /// precedes the start, and a negative duration would both slip under every threshold and
    /// render as "-3s" in the notification body.
    var duration: TimeInterval {
        max(0, finishedAt.timeIntervalSince(startedAt))
    }

    /// Stable, collision-free id for `UNNotificationRequest`. Reusing an identifier makes
    /// UserNotifications REPLACE the earlier banner, so two builds finishing in the same
    /// session would silently overwrite each other.
    var notificationIdentifier: String {
        let millis = Int((finishedAt.timeIntervalSince1970 * 1000).rounded())
        return "com.ahmetbarut.Termora.command-completion.\(sessionID.uuidString).\(millis)"
    }
}

// MARK: - Limits

/// Single source of truth for the "don't tell me about short commands" threshold.
/// Both the Settings UI and the decision below clamp through here, so a hand-edited or
/// corrupt settings blob can never park the threshold somewhere the UI cannot express.
enum CommandNotificationLimits {
    /// One second is the floor rather than zero: below the one-second sampling interval the
    /// probe cannot see a command at all, so a smaller value would only look like a setting.
    static let thresholdRange: ClosedRange<TimeInterval> = 1...3600

    /// Long enough that `ls`, `git status` and a quick `make` stay silent, short enough that a
    /// test suite or a container build still reaches the user.
    static let defaultThreshold: TimeInterval = 30

    static func clampThreshold(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return defaultThreshold }
        return min(max(value, thresholdRange.lowerBound), thresholdRange.upperBound)
    }

    /// For the Settings text field: unparseable input falls back, both paths get clamped.
    static func threshold(fromText text: String, fallback: TimeInterval) -> TimeInterval {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Double(trimmed) else { return clampThreshold(fallback) }
        return clampThreshold(parsed)
    }
}

// MARK: - Duration text

/// "4m 18s" style durations. Deliberately not `DateComponentsFormatter`: that one is
/// locale-dependent and the brief pins the UI language to English.
enum CommandDurationFormatter {
    /// At most two units, largest first. Non-finite and negative input reads as "0s" —
    /// `Int(Double.nan)` would trap.
    static func short(_ duration: TimeInterval) -> String {
        guard duration.isFinite, duration > 0 else { return "0s" }
        let total = Int(duration.rounded())

        if total >= 3600 {
            let hours = total / 3600
            let minutes = (total % 3600) / 60
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }
        if total >= 60 {
            let minutes = total / 60
            let seconds = total % 60
            return seconds == 0 ? "\(minutes)m" : "\(minutes)m \(seconds)s"
        }
        return "\(total)s"
    }
}

// MARK: - Notification text

/// Title + body of one macOS notification.
struct CommandNotificationMessage: Equatable {
    let title: String
    let body: String
}

enum CommandNotificationText {
    /// briefs/2 shows `npm run build completed successfully in 4m 18s` as an example. Two
    /// parts of it are knowingly NOT reproduced, because reproducing them would mean making
    /// facts up:
    ///   * the command line — libproc gives the process name only, so the title is `npm`;
    ///   * "successfully" — see `CommandOutcome`; an unobserved exit status reads "Completed".
    static func message(for activity: CommandActivity) -> CommandNotificationMessage {
        let elapsed = CommandDurationFormatter.short(activity.duration)
        let body: String
        switch activity.outcome {
        case .unknown:
            body = "Completed in \(elapsed)"
        case .succeeded:
            body = "Completed successfully in \(elapsed)"
        case let .failed(exitCode):
            if let exitCode {
                body = "Failed with exit code \(exitCode) after \(elapsed)"
            } else {
                body = "Failed after \(elapsed)"
            }
        }
        return CommandNotificationMessage(title: activity.command, body: body)
    }
}

// MARK: - Tracker

/// Turns a stream of "what owns the terminal right now?" samples into finished commands.
///
/// The brief's definition of "a command ended": the foreground job WAS there and is now gone.
/// `ForegroundProcessProbe.foregroundCommandName(shellPID:)` returns nil when the shell itself
/// holds the terminal, so nil is the idle state.
///
/// Pure value type on purpose — the whole detection rule is testable without a pty.
struct CommandActivityTracker {

    private struct RunningCommand {
        let name: String
        let startedAt: Date
    }

    private var running: [UUID: RunningCommand] = [:]

    /// Number of sessions currently believed to be running a command. Diagnostics/tests.
    var trackedCommandCount: Int { running.count }

    /// Feeds one sample for one session and returns the command that just ended, if any.
    ///
    /// A CHANGED name also closes the previous command: `make && ./run` never shows an idle
    /// shell between the two, so waiting for nil would merge them into one bogus activity.
    mutating func observe(sessionID: UUID, foregroundCommand: String?, at now: Date) -> CommandActivity? {
        // libproc can hand back an empty name for a process it cannot describe; an empty
        // notification title is worse than no notification.
        let name = foregroundCommand?.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = (name?.isEmpty ?? true) ? nil : name

        let previous = running[sessionID]
        if let previous, previous.name == current { return nil }

        if let current {
            running[sessionID] = RunningCommand(name: current, startedAt: now)
        } else {
            running.removeValue(forKey: sessionID)
        }

        guard let previous else { return nil }
        return CommandActivity(
            sessionID: sessionID,
            command: previous.name,
            startedAt: previous.startedAt,
            finishedAt: now,
            // The probe watches process groups, never waitpid — see `CommandOutcome`.
            outcome: .unknown
        )
    }

    /// Drops a session without emitting anything. Closing a pane is not a command completing:
    /// announcing "npm completed" right after the user killed the tab would describe a process
    /// they themselves terminated.
    mutating func forget(sessionID: UUID) {
        running.removeValue(forKey: sessionID)
    }
}

// MARK: - Decision

/// Why a finished command was or was not announced. A reason (rather than a bare `Bool`) keeps
/// the tests honest about WHICH rule fired and makes the log line useful.
enum CommandNotificationDecision: Equatable {
    case notify
    case suppressedNotificationsDisabled
    case suppressedByProfile
    case suppressedShorterThanThreshold
    case suppressedOutcomeNotSelected
    case suppressedUserIsWatching
}

/// The entire "should this be announced?" rule, as one pure function (briefs/2 "Bildirimler").
enum CommandCompletionPolicy {

    /// - Parameter isTerminalVisibleToUser: true when the app is active AND the pane that ran
    ///   the command is on screen in the key window. A banner about output the user is already
    ///   staring at is pure noise. Deliberately NOT "the app is active": running a build in one
    ///   tab while working in another is the exact workflow this feature exists for, and a pane
    ///   in a background tab or a background window still gets announced.
    static func decide(
        activity: CommandActivity,
        settings: AppSettings,
        profile: TerminalProfile?,
        isTerminalVisibleToUser: Bool
    ) -> CommandNotificationDecision {
        guard settings.notifiesOnLongCommands else { return .suppressedNotificationsDisabled }
        if profile?.suppressesCommandNotifications == true { return .suppressedByProfile }

        // `>=`, not `>`: a command that ran exactly as long as the user asked for counts.
        let threshold = CommandNotificationLimits.clampThreshold(settings.longCommandThresholdSeconds)
        guard activity.duration >= threshold else { return .suppressedShorterThanThreshold }

        switch activity.outcome {
        case .succeeded, .unknown:
            // `.unknown` rides the "completed" switch rather than the "failed" one. Termora
            // cannot prove failure, so putting it on the failure switch would announce EVERY
            // command to a user who asked to hear about failures only.
            guard settings.notifiesOnCommandSuccess else { return .suppressedOutcomeNotSelected }
        case .failed:
            guard settings.notifiesOnCommandFailure else { return .suppressedOutcomeNotSelected }
        }

        guard !isTerminalVisibleToUser else { return .suppressedUserIsWatching }
        return .notify
    }
}
