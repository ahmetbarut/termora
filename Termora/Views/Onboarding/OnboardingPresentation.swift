import SwiftUI

enum OnboardingScene {
    /// `TermoraApp` içindeki `Window` sahnesinin kimliği.
    static let windowID = "termora.onboarding"
}

/// Ayarlarda onboarding tamamlanmamışsa ilk açılışta akış penceresini açar.
/// Pencere ayrı bir sahnedir; ana pencere arkasında kullanılabilir kalır.
private struct OnboardingPresentationModifier: ViewModifier {
    let settings: SettingsStore

    @Environment(\.openWindow) private var openWindow
    /// Pencere başına tek deneme: `onAppear` her yeniden yerleşimde tetiklenebilir.
    @State private var didRequestOnboarding = false

    func body(content: Content) -> some View {
        content.onAppear {
            guard !didRequestOnboarding, !settings.settings.hasCompletedOnboarding else { return }
            didRequestOnboarding = true
            openWindow(id: OnboardingScene.windowID)
        }
    }
}

extension View {
    func presentingOnboardingIfNeeded(settings: SettingsStore) -> some View {
        modifier(OnboardingPresentationModifier(settings: settings))
    }
}
