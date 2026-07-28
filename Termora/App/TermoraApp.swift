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
        // Kimlikli grup: oturum geri yüklemede İLK pencere, kayıttaki diğer pencereleri
        // `openWindow(id:)` ile açar (bkz. `MainWindowView.prepareWindow`).
        WindowGroup(id: MainWindowScene.groupID) {
            MainWindowView(services: services)
                .termoraWindowChrome(
                    opacity: SettingsLimits.clampOpacity(services.settings.settings.windowOpacity),
                    backgroundColor: services.themes.theme(id: services.settings.settings.themeID).backgroundNSColor
                )
                .syncingTerminalAppearance(settings: services.settings, sessionManager: services.sessionManager)
                .presentingOnboardingIfNeeded(settings: services.settings)
        }
        .defaultSize(width: 900, height: 560)
        .commands {
            AppCommands()
            ProfileCommands(profiles: services.profiles)
        }

        // brief 3 "İlk Açılış Akışı": ayrı bir pencere; sheet olsaydı ana pencereyi
        // kilitlerdi. Kapatıldığında terminal normal şekilde kullanılmaya devam eder.
        Window("Welcome to Termora", id: OnboardingScene.windowID) {
            OnboardingWindowView(settings: services.settings, themes: services.themes)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            SettingsWindowView(settings: services.settings,
                               themes: services.themes,
                               profiles: services.profiles,
                               workspaces: services.workspaces,
                               requestOpen: { services.workspaceOpenRequest = $0 },
                               captureCurrentLayout: { services.capturedLayout() },
                               ssh: services.sshHosts,
                               connectSSH: { services.sshConnectRequest = $0 })
        }
    }
}