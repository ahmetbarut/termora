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

    /// `profiles` is injected from day one: `restartSession` needs the session's profile to
    /// bring the shell back up with the same environment, and Task 19 resolves the per-profile
    /// theme/font override through the same store. Every call site (AppServices, tests) is
    /// written against this initialiser, so the object graph is never rewired later.
    init(
        settings: SettingsStore,
        themes: ThemeStore,
        profiles: ProfileStore,
        escalationDelay: TimeInterval = 1.5
    ) {
        self.settings = settings
        self.themes = themes
        self.profiles = profiles
        self.escalationDelay = escalationDelay
    }

    // MARK: - SessionManaging

    func createSession(profile: TerminalProfile?, workingDirectory: String?) -> TerminalSession {
        let shellPath = resolveShellPath(profile: profile)
        let directory = workingDirectory
            ?? profile?.startupDirectory
            ?? settings.settings.startupDirectory

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

        return session
    }

    func session(id: UUID) -> TerminalSession? {
        sessions[id]
    }

    func terminateSession(id: UUID) {
        sessions[id] = nil
        guard let view = views.removeValue(forKey: id) else { return }
        view.processDelegate = nil
        killProcess(of: view)
    }

    func hasRunningProcess(sessionID: UUID) -> Bool {
        guard let process = views[sessionID]?.process else { return false }
        return ProcessProbe.hasForegroundJob(masterFD: process.childfd, shellPID: process.shellPid)
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
        return view
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

    // MARK: - View cache

    /// The cached AppKit view for a session. Never creates one: views come into existence
    /// together with their session in `createSession` and die in `terminateSession`.
    func terminalView(for sessionID: UUID) -> TermoraTerminalView? {
        views[sessionID]
    }

    // MARK: - Appearance

    /// One-way settings flow (§3.5): settings change -> every open terminal is updated.
    func applyAppearanceToAllSessions() {
        for (sessionID, view) in views {
            applyAppearance(to: view, sessionID: sessionID)
        }
    }

    /// M1 applies the global settings to every terminal alike. `sessionID` is already part of
    /// the signature because Task 19 resolves the session's profile through it (per-profile
    /// theme and font overrides); the name and the parameter list are final from here on.
    private func applyAppearance(to view: TermoraTerminalView, sessionID: UUID) {
        let current = settings.settings
        let theme = themes.theme(id: current.themeID)

        view.font = Self.resolveFont(name: current.fontName, size: current.fontSize)
        view.lineSpacing = CGFloat(current.lineSpacing)
        view.nativeForegroundColor = theme.foregroundNSColor

        let opacity = min(max(current.windowOpacity, 0.2), 1.0)
        view.nativeBackgroundColor = opacity < 1.0
            ? theme.backgroundNSColor.withAlphaComponent(CGFloat(opacity))
            : theme.backgroundNSColor

        view.caretColor = theme.cursorNSColor
        view.installColors(theme.swiftTermAnsiColors())
        view.getTerminal().setCursorStyle(current.cursorStyle.swiftTermStyle)
        view.changeScrollback(current.scrollbackLines)
    }

    /// Pure: a missing, empty or unknown font name falls back to the system monospaced face.
    static func resolveFont(name: String?, size: Double) -> NSFont {
        let pointSize = CGFloat(size)
        guard let name, !name.isEmpty, let font = NSFont(name: name, size: pointSize) else {
            return NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        }
        return font
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
        // SwiftTerm already pushed the new winsize onto the PTY. The status bar consumes
        // cols/rows in M5 (Task 21 fills this body); nothing to do in M1.
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
