//
//  AppServices.swift
//  Termora
//

import AppKit
import Foundation
import Observation

/// Object graph for one running Termora instance, built once by `TermoraApp`.
/// Stores are shared by every window, and so is `SessionManager` — it owns the terminal view
/// cache, so a per-window copy would lose live shells. `WorkspaceViewModel` (M2) is per-window.
@MainActor
@Observable
final class AppServices {
    let settings: SettingsStore
    let themes: ThemeStore
    let profiles: ProfileStore
    /// Saved workspaces. Shared like every other store: the Workspaces settings tab edits the
    /// same list a window reads when it opens one.
    let workspaces: WorkspaceStore
    let sessionManager: SessionManager

    /// Settings is a separate scene, so it cannot reach a window's `WorkspaceViewModel`.
    /// It parks the request here; the key window picks it up and clears it. Per-window view
    /// models stay per-window, and a workspace never opens in a window nobody is looking at.
    var workspaceOpenRequest: Workspace?

    /// "Use Current Layout" için: anahtar pencere kendi düzenini buraya bağlar.
    /// Pencere yoksa nil kalır ve düzen kopyalama sessizce hiçbir şey yapmaz.
    @ObservationIgnored var capturedLayoutProvider: (() -> [WorkspaceTab])?

    init() {
        // Termora draws its own tab bar (M2); leaving the system tabbing on would add a
        // "Show Tab Bar" menu item and fight ⌘T for the same gesture.
        NSWindow.allowsAutomaticWindowTabbing = false

        let settings = SettingsStore()
        let themes = ThemeStore()
        let profiles = ProfileStore()
        self.settings = settings
        self.themes = themes
        self.profiles = profiles
        self.workspaces = WorkspaceStore()
        self.sessionManager = SessionManager(settings: settings, themes: themes, profiles: profiles)
    }
}