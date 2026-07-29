//
//  SessionManager.swift
//  Termora
//

import AppKit
import Darwin
import Foundation
import Observation
import SwiftTerm
import os

/// The surface `WorkspaceViewModel` depends on, so window logic can be tested with a mock.
@MainActor
protocol SessionManaging: AnyObject {
    func createSession(profile: TerminalProfile?, workingDirectory: String?) -> TerminalSession
    func session(id: UUID) -> TerminalSession?
    func terminateSession(id: UUID)
    func hasRunningProcess(sessionID: UUID) -> Bool

    /// §8: the pane stays open when the shell dies. Restart puts a new shell behind the SAME
    /// session id, so panes, tabs and every id-keyed lookup survive it. `forceDefaultShell`
    /// ignores the settings/profile path and uses the login shell — the recovery action for
    /// "this shell cannot be executed".
    func restartSession(id: UUID, forceDefaultShell: Bool)

    /// Oturuma kullanıcı yazmış gibi girdi gönderir. Shell menüsündeki "Clear Screen"
    /// bunu kullanır: ekranı Termora'nın kendi tarafında temizlemek yerine shell'in kendi
    /// `Ctrl+L` yolunu izler, böylece scrollback ve shell durumu ayrışmaz.
    func sendInput(_ text: String, toSession id: UUID)
}

/// Single owner of terminal session lifetime.
///
/// It creates the shell, caches the AppKit view keyed by session id — so SwiftUI may tear
/// the representable down and rebuild it without killing the process or losing scrollback —
/// applies appearance settings to every live terminal, and shuts processes down
/// deterministically (SIGTERM, then SIGKILL).
@MainActor
@Observable
final class SessionManager: SessionManaging, LocalProcessTerminalViewDelegate {

    private let settings: SettingsStore
    private let themes: ThemeStore
    private let profiles: ProfileStore
    private let escalationDelay: TimeInterval
    private let logger = Logger(subsystem: "com.ahmetbarut.Termora", category: "SessionManager")

    private var sessions: [UUID: TerminalSession] = [:]
    @ObservationIgnored private var views: [UUID: TermoraTerminalView] = [:]

    /// briefs/2 "Bildirimler". Lives here because this is the only object that owns both the
    /// shell pids and the AppKit views — the two things needed to answer "did a command just
    /// finish?" and "is the user looking at it?".
    @ObservationIgnored private let notifier: CommandCompletionNotifier

    /// How often the foreground process group is sampled. One second matches the tickers the
    /// window already runs for tab titles and the status bar, and it bounds the error on a
    /// reported duration to a single second.
    static let foregroundSampleInterval: Duration = .seconds(1)

    /// Runs only while at least one session exists. Holds `self` weakly so the manager can be
    /// released; the loop then ends on its own.
    @ObservationIgnored private var samplingTask: Task<Void, Never>?

    /// `profiles` is injected from day one: `restartSession` needs the session's profile to
    /// bring the shell back up with the same environment, and Task 19 resolves the per-profile
    /// theme/font override through the same store. Every call site (AppServices, tests) is
    /// written against this initialiser, so the object graph is never rewired later.
    init(
        settings: SettingsStore,
        themes: ThemeStore,
        profiles: ProfileStore,
        escalationDelay: TimeInterval = 1.5,
        notifier: CommandCompletionNotifier? = nil
    ) {
        self.settings = settings
        self.themes = themes
        self.profiles = profiles
        self.escalationDelay = escalationDelay
        self.notifier = notifier ?? CommandCompletionNotifier(settings: settings)
    }

    // MARK: - SessionManaging

    func createSession(profile: TerminalProfile?, workingDirectory: String?) -> TerminalSession {
        let shellPath = resolveShellPath(profile: profile)
        // Son basamak home dizinidir: Finder'dan açılan bir GUI uygulamasının cwd'si `/`
        // olduğundan, `startProcess(currentDirectory: nil)` shell'i `/` içinde başlatır.
        // Spec, yeni terminalin kullanıcının home dizininden açılmasını şart koşar.
        let directory = workingDirectory
            ?? profile?.startupDirectory
            ?? settings.settings.startupDirectory
            ?? NSHomeDirectory()

        let session = TerminalSession(
            shellPath: shellPath,
            profileID: profile?.id,
            workingDirectory: directory
        )
        sessions[session.id] = session

        let view = makeView(sessionID: session.id)
        views[session.id] = view

        startShell(
            shellPath,
            in: view,
            session: session,
            environment: profile?.environment ?? [:],
            startupCommand: profile?.startupCommand,
            workingDirectory: directory
        )

        startForegroundSamplingIfNeeded()
        return session
    }

    func session(id: UUID) -> TerminalSession? {
        sessions[id]
    }

    func terminateSession(id: UUID) {
        sessions[id] = nil
        // Before the view goes: whatever was running in this pane did not "complete", the user
        // closed it. `sessionEnded` drops it without announcing anything.
        notifier.sessionEnded(sessionID: id)
        defer { stopForegroundSamplingIfIdle() }
        guard let view = views.removeValue(forKey: id) else { return }
        view.processDelegate = nil
        killProcess(of: view)
    }

    func hasRunningProcess(sessionID: UUID) -> Bool {
        guard let process = views[sessionID]?.process else { return false }
        return ProcessProbe.hasForegroundJob(masterFD: process.childfd, shellPID: process.shellPid)
    }

    // MARK: - Command completion notifications (briefs/2 "Bildirimler")

    /// One sampling pass over every live session: who owns each pty right now?
    ///
    /// Internal rather than private so a test can step it deterministically instead of racing
    /// the one-second loop. `ForegroundProcessProbe` answers "the shell itself" with nil, which
    /// is exactly the idle state `CommandActivityTracker` expects.
    func sampleForegroundCommands(now: Date = Date()) {
        for sessionID in views.keys {
            let command = shellPID(sessionID: sessionID).flatMap {
                ForegroundProcessProbe.foregroundCommandName(shellPID: $0)
            }
            notifier.sample(
                sessionID: sessionID,
                foregroundCommand: command,
                profile: profile(forSession: sessionID),
                isTerminalVisibleToUser: isTerminalVisibleToUser(sessionID: sessionID),
                now: now
            )
        }
    }

    /// True only when the user can actually see this pane's output right now: the app is
    /// active, the pane is in the key window and nothing is covering it in the view tree
    /// (an inactive tab's pane is hidden or has no window at all).
    ///
    /// This is the one genuinely untestable input of the notification decision, which is why
    /// it is a single expression and the rule that consumes it is pure.
    private func isTerminalVisibleToUser(sessionID: UUID) -> Bool {
        guard NSApp.isActive,
              let view = views[sessionID],
              let window = view.window,
              window.isKeyWindow
        else { return false }
        return !view.isHiddenOrHasHiddenAncestor
    }

    /// Sampling costs one `proc_pidinfo` per session per second and runs regardless of the
    /// notification setting: it has to, otherwise a command already running when the user
    /// flips the switch on would have no start time and could never be announced.
    private func startForegroundSamplingIfNeeded() {
        guard samplingTask == nil else { return }
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.foregroundSampleInterval)
                // `weak self` keeps the loop from holding the manager alive; once it is gone
                // there is nothing left to sample.
                guard !Task.isCancelled, let self else { return }
                self.sampleForegroundCommands()
            }
        }
    }

    private func stopForegroundSamplingIfIdle() {
        guard views.isEmpty else { return }
        samplingTask?.cancel()
        samplingTask = nil
    }

    // MARK: - Shell lifecycle

    /// A terminal view wired to this manager and dressed in the current appearance.
    private func makeView(sessionID: UUID) -> TermoraTerminalView {
        let view = TermoraTerminalView(
            sessionID: sessionID,
            frame: CGRect(x: 0, y: 0, width: 640, height: 400)
        )
        view.processDelegate = self
        applyAppearance(to: view, sessionID: sessionID)
        registerShellIntegrationHandler(on: view, sessionID: sessionID)
        registerCommandBlockRecorder(on: view, sessionID: sessionID)
        registerBell(on: view)
        return view
    }

    /// briefs/3 "Ses Kullanımı": bell duyulur ya da GÖRÜLÜR, ikisi de kapalıysa hiçbir
    /// şey olmaz. Sesi kapalı tutan kullanıcı için görsel karşılık şart: bell bir bilgi
    /// taşır ve sessizlik onu tamamen yutmamalı.
    private func registerBell(on view: TermoraTerminalView) {
        view.onBell = { [weak self, weak view] in
            guard let self else { return }
            SoundPlayer.play(.bell, settings: settings.settings)
            guard settings.settings.usesVisualBell, let view else { return }
            view.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
            // Kısa bir parlama: briefs/3 animasyon süresi 120–180 ms.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak view] in
                view?.layer?.backgroundColor = nil
            }
        }
    }

    /// Ham baytları komut bloğu kaydedicisine akıtır (briefs/2 "Komut Blokları").
    ///
    /// Kayıt HER ZAMAN çalışır, panel açık olmasa bile: panel açıldığında kullanıcı boş
    /// bir listeye değil, o ana kadar çalıştırdığı komutlara bakmalı. Maliyeti dar —
    /// kaydedici işaret görmeden hiçbir şey biriktirmez ve shell integration kurulu
    /// değilse tek bir blok bile açılmaz.
    private func registerCommandBlockRecorder(on view: TermoraTerminalView, sessionID: UUID) {
        view.onDataReceived = { [weak self] slice in
            // `dataReceived` PTY okuma kuyruğundan gelir; oturum durumu MainActor'a aittir.
            // Baytlar kopyalanır: dilim çağrı bitince geçersizdir.
            let bytes = Array(slice)
            Task { @MainActor [weak self] in
                self?.recordCommandBlockBytes(bytes, sessionID: sessionID)
            }
        }
    }

    @MainActor
    private func recordCommandBlockBytes(_ bytes: [UInt8], sessionID: UUID) {
        guard let session = session(id: sessionID) else { return }
        session.commandBlocks.consume(bytes, now: Date())
    }

    /// Shell integration kancalarının yaydığı OSC 133 işaretlerini dinler.
    ///
    /// Kancalar kurulu değilse bu işleyici HİÇ çağrılmaz ve hiçbir şey değişmez —
    /// entegrasyon isteğe bağlıdır (briefs/2 Onboarding "İsteğe Bağlı Özellikler").
    private func registerShellIntegrationHandler(on view: TermoraTerminalView, sessionID: UUID) {
        view.getTerminal().registerOscHandler(code: 133) { [weak self] payload in
            let text = "133;" + (String(bytes: payload, encoding: .utf8) ?? "")
            guard let marker = ShellIntegrationMarker(payload: text) else { return }
            // OSC işleyicisi ayrıştırma kuyruğundan gelir; oturum durumu MainActor'a aittir.
            Task { @MainActor [weak self] in
                self?.apply(marker, to: sessionID)
            }
        }
    }

    @MainActor
    private func apply(_ marker: ShellIntegrationMarker, to sessionID: UUID) {
        guard let session = session(id: sessionID) else { return }
        session.didReceiveShellIntegrationMarker = true
        switch marker {
        case let .commandEnd(exitCode):
            // Kod bilinmiyorsa ESKİSİ KORUNMAZ: bir önceki komutun kodunu yeni komuta
            // yapıştırmak, kullanıcıya yanlış bir sonuç göstermek olurdu.
            session.lastCommandExitCode = exitCode
        case .promptStart, .commandStart:
            break
        case .outputStart:
            // Yeni bir komut çalışmaya başladı: önceki kod artık geçmişe aittir.
            session.lastCommandExitCode = nil
        }
    }

    /// Starts `shellPath` behind `view`, or records the failure on the session.
    ///
    /// §8: X_OK is checked before `startProcess`, otherwise `forkpty` succeeds and the child
    /// dies silently inside `exec` with nothing to show the user. `launchFailure` is what the
    /// pane's error banner (M3) reads in order to offer "try the default shell".
    private func startShell(
        _ shellPath: String,
        in view: TermoraTerminalView,
        session: TerminalSession,
        environment: [String: String],
        startupCommand: String?,
        workingDirectory: String?
    ) {
        // `Darwin.` qualification is required: the `@Observable` macro synthesises an
        // `access(keyPath:)` member on this class, which otherwise shadows POSIX `access`.
        guard Darwin.access(shellPath, X_OK) == 0 else {
            logger.error("Shell is not executable: \(shellPath, privacy: .public)")
            view.feed(text: "Termora: cannot execute \(shellPath)\r\n")
            session.launchFailure = shellPath
            session.processState = .exited(ExitStatus(rawStatus: 127 << 8))
            return
        }

        session.launchFailure = nil
        view.startProcess(
            executable: shellPath,
            args: [],
            environment: EnvironmentBuilder.environment(extra: environment),
            execName: ShellService.loginArgv0(forShellPath: shellPath),
            currentDirectory: workingDirectory
        )

        if let startupCommand, !startupCommand.isEmpty {
            view.send(txt: startupCommand + "\n")
        }
    }

    /// SIGTERM now, SIGKILL after `escalationDelay` if the shell is still there.
    /// The caller has already dropped the view from `views` and cleared its delegate.
    private func killProcess(of view: TermoraTerminalView) {
        let pid = view.process.shellPid
        guard pid > 0 else { return }

        view.terminate() // SwiftTerm sends SIGTERM to the shell pid only.

        DispatchQueue.main.asyncAfter(deadline: .now() + escalationDelay) {
            var status: Int32 = 0
            // != 0 covers both "we reaped it" (> 0) and "already gone" (-1/ECHILD).
            if waitpid(pid, &status, WNOHANG) != 0 { return }
            kill(pid, SIGKILL)
            _ = waitpid(pid, &status, 0) // returns immediately once SIGKILL lands
        }
    }

    func restartSession(id: UUID, forceDefaultShell: Bool) {
        guard let session = sessions[id] else { return }

        // The old shell — and anything it was running — is about to be killed on purpose.
        notifier.sessionEnded(sessionID: id)

        if let oldView = views.removeValue(forKey: id) {
            // Clear the delegate first: `terminate()` fires processTerminated on the main queue
            // and it must not overwrite the state of the session we are just reviving.
            oldView.processDelegate = nil
            killProcess(of: oldView)
        }

        let profile = session.profileID.flatMap { profileID in
            profiles.profiles.first { $0.id == profileID }
        }
        let shellPath = forceDefaultShell
            ? ShellService.defaultShellPath()
            : resolveShellPath(profile: profile)
        session.shellPath = shellPath

        let view = makeView(sessionID: id)
        views[id] = view

        startForegroundSamplingIfNeeded()

        // The pane's `TerminalHostView` is keyed on this, so SwiftUI drops the dead NSView and
        // hosts the new one; the session id — and therefore the pane and the tab — stays put.
        session.restartGeneration += 1
        session.processState = .running
        startShell(
            shellPath,
            in: view,
            session: session,
            environment: profile?.environment ?? [:],
            startupCommand: profile?.startupCommand,
            workingDirectory: session.workingDirectory
        )
    }

    // MARK: - View cache

    /// The cached AppKit view for a session. Never creates one: views come into existence
    /// together with their session in `createSession` and die in `terminateSession`.
    func terminalView(for sessionID: UUID) -> TermoraTerminalView? {
        views[sessionID]
    }

    /// Görünümü olmayan oturum sessizce yok sayılır: oturum kapanırken menü öğesi hâlâ
    /// tetiklenebilir ve bu bir hata değildir.
    func sendInput(_ text: String, toSession id: UUID) {
        views[id]?.send(txt: text)
    }

    // MARK: - Appearance

    /// One-way settings flow (§3.5): settings change -> every open terminal is updated.
    func applyAppearanceToAllSessions() {
        for (sessionID, view) in views {
            applyAppearance(to: view, sessionID: sessionID)
        }
    }

    /// Applies the appearance to a single terminal. When the session was opened with a profile,
    /// the profile's font/theme overrides win; line spacing, cursor and scrollback stay global.
    ///
    /// The two expensive setters are guarded by an "did the value actually change?" check:
    /// SwiftTerm's `font` setter calls `selectNone()` (it would wipe the user's text selection
    /// on every unrelated settings tweak) and `changeScrollback` refreshes the whole screen.
    private func applyAppearance(to view: TermoraTerminalView, sessionID: UUID) {
        let current = settings.settings
        let resolved = AppearanceResolver.resolve(settings: current, profile: profile(forSession: sessionID))
        let theme = themes.theme(id: resolved.themeID)
        let opacity = SettingsLimits.clampOpacity(current.windowOpacity)

        let font = FontCatalog.resolvedFont(
            name: resolved.fontName,
            size: resolved.fontSize,
            usesLigatures: resolved.usesLigatures
        )
        if view.font != font {
            view.font = font
        }

        let lineSpacing = CGFloat(SettingsLimits.clampLineSpacing(current.lineSpacing))
        if view.lineSpacing != lineSpacing {
            view.lineSpacing = lineSpacing
        }

        view.nativeForegroundColor = theme.foregroundNSColor
        view.nativeBackgroundColor = opacity < 1.0
            ? theme.backgroundNSColor.withAlphaComponent(CGFloat(opacity))
            : theme.backgroundNSColor
        view.caretColor = theme.cursorNSColor
        view.selectedTextBackgroundColor = theme.selectionNSColor
        view.installColors(theme.swiftTermAnsiColors())
        view.getTerminal().setCursorStyle(current.cursorStyle.swiftTermStyle)

        // `TerminalView.changeScrollback` also updates the scroller; `Terminal.changeScrollback`
        // does not — but it is the one holding the value we compare against.
        let scrollback = SettingsLimits.clampScrollback(current.scrollbackLines)
        if view.getTerminal().options.scrollback != scrollback {
            view.changeScrollback(scrollback)
        }

        // Option tuşu: `optionAsMetaKey` SwiftTerm'in alanı, `optionKeySendsMeta`
        // bizim kalıcı ayarımız. Varsayılan KAPALI, böylece Option alternatif karakteri
        // (Option+4 = `$` gibi) yazar; açılırsa Esc önekli Meta dizisi gönderir.
        if view.optionAsMetaKey != current.optionKeySendsMeta {
            view.optionAsMetaKey = current.optionKeySendsMeta
        }
    }

    /// The profile a session was opened with, if it still exists in the store.
    private func profile(forSession sessionID: UUID) -> TerminalProfile? {
        guard let profileID = sessions[sessionID]?.profileID else { return nil }
        return profiles.profiles.first { $0.id == profileID }
    }


    /// Pure: OSC 7 payloads arrive as `file:///path`, but some shells emit a bare path.
    static func workingDirectory(fromHostReport report: String?) -> String? {
        guard let report, !report.isEmpty else { return nil }
        if report.hasPrefix("/") { return report }
        guard let url = URL(string: report), url.isFileURL else { return nil }
        return url.path
    }

    private func resolveShellPath(profile: TerminalProfile?) -> String {
        if let path = profile?.shellPath, !path.isEmpty { return path }
        if let path = settings.settings.defaultShellPath, !path.isEmpty { return path }
        return ShellService.defaultShellPath()
    }

    // MARK: - LocalProcessTerminalViewDelegate
    //
    // The conformance is declared on the class itself rather than in an extension because
    // `makeView` assigns `view.processDelegate = self`: without it this file does not compile
    // (`cannot assign value of type 'SessionManager' to type '(any LocalProcessTerminalViewDelegate)?'`).
    // The bodies stay empty until Step 26 — no extension adds the conformance later.
    //
    // SwiftTerm's delegate is not actor-isolated, but `LocalProcess` dispatches every callback
    // on `DispatchQueue.main` (its `dispatchQueue` defaults to the main queue), so the bodies
    // hop in with `MainActor.assumeIsolated` instead of an async detour.

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // SwiftTerm already pushed the new winsize onto the PTY; we only mirror it into the
        // session so the status bar (Task 21) can show cols×rows.
        MainActor.assumeIsolated {
            guard let view = source as? TermoraTerminalView,
                  let session = self.session(id: view.sessionID) else { return }
            session.terminalSize = (cols: newCols, rows: newRows)
        }
    }

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        MainActor.assumeIsolated {
            guard let sessionID = (source as? TermoraTerminalView)?.sessionID else { return }
            sessions[sessionID]?.title = title
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        MainActor.assumeIsolated {
            guard let sessionID = (source as? TermoraTerminalView)?.sessionID,
                  let path = Self.workingDirectory(fromHostReport: directory)
            else { return }
            sessions[sessionID]?.workingDirectory = path
        }
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        MainActor.assumeIsolated {
            guard let sessionID = (source as? TermoraTerminalView)?.sessionID else { return }
            // `exitCode` is the raw waitpid status, not an exit code (SwiftTerm passes `n` from
            // `waitpid` straight through). nil means the PTY died before waitpid ran, which we
            // report as "hung up".
            sessions[sessionID]?.processState = .exited(ExitStatus(rawStatus: exitCode ?? SIGHUP))
        }
    }
}
