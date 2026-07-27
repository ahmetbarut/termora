//
//  TermoraApp.swift
//  Termora
//

import SwiftUI

@main
struct TermoraApp: App {

    @NSApplicationDelegateAdaptor(TermoraAppDelegate.self) private var appDelegate

    /// `@State`, not `let`: SwiftUI may rebuild the `App` struct, and a fresh `AppServices`
    /// on every rebuild would mean a fresh `SessionManager` — every open shell would vanish.
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            MainWindowView(services: services)
                .termoraWindowChrome(
                    opacity: SettingsLimits.clampOpacity(services.settings.settings.windowOpacity),
                    backgroundColor: services.themes.theme(id: services.settings.settings.themeID).backgroundNSColor
                )
                .syncingTerminalAppearance(settings: services.settings, sessionManager: services.sessionManager)
        }
        .defaultSize(width: 900, height: 560)
        .commands {
            AppCommands()
            ProfileCommands(profiles: services.profiles)
        }

        Settings {
            SettingsWindowView(settings: services.settings,
                               themes: services.themes,
                               profiles: services.profiles)
        }
    }
}