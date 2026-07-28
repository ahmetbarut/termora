import AppKit
import SwiftUI

/// İlk açılış akışının penceresi (brief 3 "İlk Açılış Akışı").
///
/// Kendi penceresidir, sheet değildir: ana pencereyi engellemez, kapandığında terminal
/// olduğu gibi kullanılmaya devam eder.
struct OnboardingWindowView: View {
    let settings: SettingsStore
    let themes: ThemeStore

    @State private var state: OnboardingState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @MainActor
    init(settings: SettingsStore, themes: ThemeStore) {
        self.settings = settings
        self.themes = themes
        _state = State(initialValue: OnboardingState(settings: settings.settings))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                stepContent
                    .id(state.step)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(stepAnimation, value: state.step)

            Divider()
            footer
        }
        .frame(width: 620, height: 520)
        .background(
            WindowAccessor { window in
                // Akış üç ekrandan ibaret; boyut değiştirmek yerleşimi bozar.
                window.styleMask.remove(.resizable)
                window.title = "Welcome to Termora"
            }
        )
        .onChange(of: state.isFinished) { _, finished in
            if finished { dismiss() }
        }
        .onDisappear {
            // Pencere kırmızı düğmeyle kapatıldıysa bu da bir atlamadır: akış bir daha
            // gösterilmez, yoksa kullanıcı her açılışta aynı ekranla karşılaşırdı.
            if !state.isFinished { state.skip(writingTo: settings) }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch state.step {
        case .welcome:
            OnboardingWelcomeView()
        case .appearance:
            OnboardingAppearanceView(state: state, themes: themes)
        case .finish:
            OnboardingSummaryView(state: state, themes: themes)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if state.canGoBack {
                Button("Back") {
                    withAnimation(stepAnimation) { state.goBack() }
                }
                .accessibilityLabel("Back to the previous step")
            }

            stepIndicator

            Spacer()

            if state.step != .finish {
                Button("Skip Setup") {
                    state.skip(writingTo: settings)
                }
                .accessibilityLabel("Skip setup and open Termora")
            }

            Button(state.primaryActionTitle) {
                withAnimation(stepAnimation) { state.primaryAction(writingTo: settings) }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    /// Sadece renkle anlatım olmasın diye göstergenin VoiceOver metni sayıyla verilir.
    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases) { step in
                Circle()
                    .fill(step == state.step
                          ? DesignTokens.accentBlue.color
                          : Color(nsColor: .tertiaryLabelColor))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(state.step.rawValue + 1) of \(OnboardingStep.allCases.count)")
    }

    /// brief 3 "Animasyonlar": 120–180 ms, "Reduce Motion" açıkken hareket yok.
    private var stepAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.16)
    }
}
