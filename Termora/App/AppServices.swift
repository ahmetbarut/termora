//
//  AppServices.swift
//  Termora
//

import AppKit
import Foundation

/// Object graph for one running Termora instance, built once by `TermoraApp`.
/// Stores are shared by every window, and so is `SessionManager` — it owns the terminal view
/// cache, so a per-window copy would lose live shells. `WorkspaceViewModel` (M2) is per-window.
@MainActor
final class AppServices {
    let settings: SettingsStore
    let themes: ThemeStore
    let profiles: ProfileStore
    let sessionManager: SessionManager

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
        self.sessionManager = SessionManager(settings: settings, themes: themes, profiles: profiles)
    }
}