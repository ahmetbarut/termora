//
//  SettingsPlaceholderView.swift
//  Termora
//

import SwiftUI

/// Stands in for the real Settings window until M4, so the ⌘, menu item is not dead.
struct SettingsPlaceholderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Settings")
                .font(.title3.weight(.semibold))
            Text("Appearance, profiles and shell options arrive in milestone M4.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(width: 420, height: 180)
    }
}