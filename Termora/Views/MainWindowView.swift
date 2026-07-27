//
//  MainWindowView.swift
//  Termora
//

import SwiftUI

/// M1 window: exactly one tab holding exactly one pane.
/// Tabs arrive in M2 (`TabBarView`), splits in M3 (`PaneTreeView`).
struct MainWindowView: View {

    private let services: AppServices

    @State private var sessionID: UUID?

    /// Explicit because `services` is private: the synthesised memberwise initialiser would be
    /// private too. Task 12 keeps this initialiser and adds the workspace view model to it.
    init(services: AppServices) {
        self.services = services
    }

    var body: some View {
        Group {
            if let sessionID {
                TerminalHostView(
                    sessionID: sessionID,
                    sessionManager: services.sessionManager,
                    isActive: true
                )
            } else {
                Color.black
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .onAppear {
            guard sessionID == nil else { return }
            sessionID = services.sessionManager
                .createSession(profile: nil, workingDirectory: nil)
                .id
        }
    }
}