//
//  TermoraApp.swift
//  Termora
//

import SwiftUI

@main
struct TermoraApp: App {

    /// `@State`, not `let`: SwiftUI may rebuild the `App` struct, and a fresh `AppServices`
    /// on every rebuild would mean a fresh `SessionManager` — every open shell would vanish.
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            MainWindowView(services: services)
        }
        .defaultSize(width: 900, height: 560)

        Settings {
            SettingsPlaceholderView()
        }
    }
}