import AppKit
import SwiftUI

/// Ekran 1. Metinler brief 3 "İlk Açılış Akışı"ndan birebir alınmıştır.
struct OnboardingWelcomeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            // brief 3 "Logo Kullanımı": logo ağırlıklı olarak ikon, onboarding ve About'ta.
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            Text("Welcome to Termora")
                .font(.system(size: 28, weight: .semibold))
                .multilineTextAlignment(.center)

            Text("A native terminal built for focused developers.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Two quick steps: pick your shell and appearance. You can change everything later in Settings.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
