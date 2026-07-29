//
//  CommandCompletionNotifier.swift
//  Termora
//

import Foundation
import UserNotifications
import os

// MARK: - Delivery boundary

/// The seam between the decision logic (pure, fully tested) and the system notification
/// centre (untestable, kept as thin as it can be).
@MainActor
protocol CommandNotificationDelivering: AnyObject {
    /// Asks macOS for permission. Returns false for both "user said no" and "the request
    /// failed" — from the feature's point of view they are the same silence.
    func requestAuthorization() async -> Bool
    func deliver(_ message: CommandNotificationMessage, identifier: String) async
}

/// The only code in this feature that touches `UNUserNotificationCenter`.
@MainActor
final class UserNotificationDeliverer: CommandNotificationDelivering {

    private let logger = Logger(subsystem: "com.ahmetbarut.Termora", category: "Notifications")

    func requestAuthorization() async -> Bool {
        do {
            // `.alert` only. briefs/3 "Ses Kullanımı": the app is silent by default, so asking
            // for the sound permission would request something we never intend to use.
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
        } catch {
            // Unsigned builds and non-bundled hosts fail here. Not worth a user-facing error:
            // the feature simply stays quiet.
            logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func deliver(_ message: CommandNotificationMessage, identifier: String) async {
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        // Bildirimin KENDİ sesi hep nil. Ses ayrı bir ayardır (briefs/3 "Ses Kullanımı":
        // her ses ayrı ayrı kapatılabilmeli) ve bildirimin sesini `.default` yapmak, ses
        // anahtarı kapalıyken de ses çıkarırdı.
        content.sound = nil

        // nil trigger = deliver now.
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            logger.error("Notification delivery failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Notifier

/// Watches foreground-command samples and announces the long ones (briefs/2 "Bildirimler").
///
/// Split in two halves on purpose:
///   * `sample(...)` is synchronous and does all the thinking — tracker + policy. It is what
///     the tests drive, and it never awaits anything.
///   * `deliverPending()` is the async half and is the only place the system is touched.
@MainActor
final class CommandCompletionNotifier {

    enum AuthorizationState: Equatable {
        case notRequested
        case granted
        case denied
    }

    /// A user who steps away for an hour should not come back to a wall of banners. Oldest
    /// entries are dropped first — the most recent completions are the interesting ones.
    static let maximumPendingNotifications = 8

    private let settings: SettingsStore
    private let logger = Logger(subsystem: "com.ahmetbarut.Termora", category: "Notifications")

    /// Created lazily: constructing the real deliverer is harmless, but resolving
    /// `UNUserNotificationCenter.current()` from a process that is not a proper app bundle
    /// raises an ObjC exception, and nothing should pay that cost until there is something
    /// to actually deliver.
    private var deliverer: (any CommandNotificationDelivering)?

    private var tracker = CommandActivityTracker()
    private var pending: [(message: CommandNotificationMessage, identifier: String)] = []

    /// The single in-flight drain, or nil when none is running. Serialising through one task
    /// is what stops two overlapping drains from delivering the same banner twice; awaiting it
    /// is what lets a caller (or a test) know the queue has actually been flushed.
    private var drainTask: Task<Void, Never>?

    private(set) var authorization: AuthorizationState = .notRequested

    var pendingCount: Int { pending.count }

    init(settings: SettingsStore, deliverer: (any CommandNotificationDelivering)? = nil) {
        self.settings = settings
        self.deliverer = deliverer
    }

    // MARK: Sampling

    /// Feeds one "what owns this terminal right now?" sample.
    ///
    /// Returns the decision when a command ended on this sample, nil when nothing ended.
    /// Queues the notification and kicks the drain itself, so callers stay synchronous.
    @discardableResult
    func sample(
        sessionID: UUID,
        foregroundCommand: String?,
        profile: TerminalProfile?,
        isTerminalVisibleToUser: Bool,
        now: Date = Date()
    ) -> CommandNotificationDecision? {
        guard let activity = tracker.observe(sessionID: sessionID,
                                             foregroundCommand: foregroundCommand,
                                             at: now)
        else { return nil }

        let decision = CommandCompletionPolicy.decide(
            activity: activity,
            settings: settings.settings,
            profile: profile,
            isTerminalVisibleToUser: isTerminalVisibleToUser
        )
        guard decision == .notify else { return decision }

        // A refusal is permanent for this launch, so there is nothing to queue up for.
        guard authorization != .denied else { return decision }

        enqueue(activity)
        startDrainIfNeeded()
        return decision
    }

    /// The pane is gone. Whatever it was running did not "complete" as far as the user is
    /// concerned, so it is dropped without a notification.
    func sessionEnded(sessionID: UUID) {
        tracker.forget(sessionID: sessionID)
    }

    private func enqueue(_ activity: CommandActivity) {
        pending.append((CommandNotificationText.message(for: activity), activity.notificationIdentifier))
        if pending.count > Self.maximumPendingNotifications {
            pending.removeFirst(pending.count - Self.maximumPendingNotifications)
        }
    }

    // MARK: Delivery

    /// Waits until everything queued so far has been handed to the deliverer (or dropped
    /// because permission was refused). Production code never has to call this — `sample`
    /// starts the drain itself — but tests do, and so would a future "flush before quitting".
    func deliverPending() async {
        await startDrainIfNeeded().value
    }

    @discardableResult
    private func startDrainIfNeeded() -> Task<Void, Never> {
        // A live drain re-checks `pending` after every delivery, so an entry queued while it
        // runs is picked up by it; `drainTask` is cleared before the drain returns, and there
        // is no suspension point between that clear and the loop's last emptiness check.
        if let drainTask { return drainTask }
        let task = Task { await self.drain() }
        drainTask = task
        return task
    }

    /// Requests permission on the FIRST entry — the brief asks for the permission prompt when
    /// a notification is actually due, not at launch, and it is never re-asked in a launch.
    private func drain() async {
        defer { drainTask = nil }

        while !pending.isEmpty {
            if authorization == .denied {
                pending.removeAll()
                return
            }
            let deliverer = resolvedDeliverer()

            if authorization == .notRequested {
                let granted = await deliverer.requestAuthorization()
                authorization = granted ? .granted : .denied
                guard granted else {
                    // Silently, per the brief: a refused permission is a decision, not an error.
                    logger.info("Notification permission not granted; command completion notifications stay quiet.")
                    pending.removeAll()
                    return
                }
            }

            let next = pending.removeFirst()
            // briefs/3 "Ses Kullanımı" ▸ "Uzun işlem tamamlandı". Ses bildirimin KENDİ
            // sesi değil ayrı bir ayardır: bildirimi açık ama sesi kapalı tutan kullanıcı
            // sessizce bildirilmeli.
            SoundPlayer.play(.longCommand, settings: settings.settings)
            await deliverer.deliver(next.message, identifier: next.identifier)
        }
    }

    private func resolvedDeliverer() -> any CommandNotificationDelivering {
        if let deliverer { return deliverer }
        let created = UserNotificationDeliverer()
        deliverer = created
        return created
    }
}
