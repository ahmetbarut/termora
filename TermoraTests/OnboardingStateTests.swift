import Foundation
import Testing
@testable import Termora

@MainActor
@Suite struct OnboardingStepTests {

    @Test func threeStepsInBriefOrder() {
        #expect(OnboardingStep.allCases == [.welcome, .appearance, .finish])
    }

    /// brief 3 "İlk Açılış Akışı" buton metinleri birebir verilmiştir.
    @Test func primaryActionTitlesMatchBriefText() {
        #expect(OnboardingStep.welcome.primaryActionTitle == "Get Started")
        #expect(OnboardingStep.finish.primaryActionTitle == "Open Termora")
        // Belirsiz "OK"/"Yes" yasak; ara adımda eylem adlandırılır.
        #expect(OnboardingStep.appearance.primaryActionTitle == "Continue")
    }

    @Test func nextAndPreviousStopAtTheEnds() {
        #expect(OnboardingStep.welcome.previous == nil)
        #expect(OnboardingStep.welcome.next == .appearance)
        #expect(OnboardingStep.appearance.previous == .welcome)
        #expect(OnboardingStep.appearance.next == .finish)
        #expect(OnboardingStep.finish.next == nil)
        #expect(OnboardingStep.finish.previous == .appearance)
    }
}

@MainActor
@Suite struct OnboardingSelectionsTests {

    @Test func seedsFromCurrentSettingsAndDetectedShell() {
        var settings = AppSettings()
        settings.fontName = "Menlo"
        settings.fontSize = 15
        settings.themeID = "nord"

        let selections = OnboardingSelections(settings: settings, detectedShellPath: "/bin/zsh")
        #expect(selections.shellPath == "/bin/zsh")
        #expect(selections.fontName == "Menlo")
        #expect(Double(selections.fontSize) == 15)
        #expect(selections.themeID == "nord")
    }

    @Test func seedsShellFromAnExplicitSettingWhenOneExists() {
        var settings = AppSettings()
        settings.defaultShellPath = "/bin/bash"

        let selections = OnboardingSelections(settings: settings, detectedShellPath: "/bin/zsh")
        #expect(selections.shellPath == "/bin/bash")
    }

    @Test func applyWritesEveryScreenTwoChoice() {
        var selections = OnboardingSelections(settings: AppSettings(), detectedShellPath: "/bin/zsh")
        selections.shellPath = "/opt/homebrew/bin/fish"
        selections.fontName = "JetBrains Mono"
        selections.fontSize = 16
        selections.themeID = "solarized-light"

        let applied = selections.applied(to: AppSettings())
        #expect(applied.defaultShellPath == "/opt/homebrew/bin/fish")
        #expect(applied.fontName == "JetBrains Mono")
        #expect(Double(applied.fontSize) == 16)
        #expect(applied.themeID == "solarized-light")
    }

    /// Algılanan shell seçili kalırsa ayar "System default" (nil) kalmalı; aksi hâlde
    /// kullanıcı login shell'ini değiştirdiğinde Termora eski yola sabitlenirdi.
    @Test func keepingTheDetectedShellLeavesTheSettingOnSystemDefault() {
        let selections = OnboardingSelections(settings: AppSettings(), detectedShellPath: "/bin/zsh")
        let applied = selections.applied(to: AppSettings())
        #expect(applied.defaultShellPath == nil)
    }

    @Test func applyClampsFontSizeIntoTheSupportedRange() {
        var selections = OnboardingSelections(settings: AppSettings(), detectedShellPath: "/bin/zsh")
        selections.fontSize = 999
        let applied = selections.applied(to: AppSettings())
        #expect(Double(applied.fontSize) == Double(SettingsLimits.fontSizeRange.upperBound))
    }

    /// Görünüm dışındaki ayarlara dokunulmamalı.
    @Test func applyLeavesUnrelatedSettingsUntouched() {
        var current = AppSettings()
        current.scrollbackLines = 42_000
        current.startupDirectory = "/Users/me/code"
        current.showStatusBar = false

        let applied = OnboardingSelections(settings: current, detectedShellPath: "/bin/zsh")
            .applied(to: current)
        #expect(applied.scrollbackLines == 42_000)
        #expect(applied.startupDirectory == "/Users/me/code")
        #expect(applied.showStatusBar == false)
    }
}

@MainActor
@Suite struct OnboardingStateTests {

    private static func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "OnboardingStateTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private static func makeStore() -> (store: SettingsStore, teardown: () -> Void) {
        let (defaults, suiteName) = makeDefaults()
        return (SettingsStore(defaults: defaults), { defaults.removePersistentDomain(forName: suiteName) })
    }

    @Test func startsOnWelcomeWithoutABackStep() {
        let state = OnboardingState(settings: AppSettings(), detectedShellPath: "/bin/zsh")
        #expect(state.step == .welcome)
        #expect(state.canGoBack == false)
        #expect(state.isFinished == false)
        #expect(state.primaryActionTitle == "Get Started")
    }

    @Test func primaryActionWalksForwardThenFinishes() {
        let (store, teardown) = Self.makeStore()
        defer { teardown() }
        let state = OnboardingState(settings: store.settings, detectedShellPath: "/bin/zsh")

        state.primaryAction(writingTo: store)
        #expect(state.step == .appearance)
        #expect(state.isFinished == false)

        state.primaryAction(writingTo: store)
        #expect(state.step == .finish)
        #expect(state.isFinished == false)

        state.primaryAction(writingTo: store)
        #expect(state.isFinished == true)
        #expect(state.step == .finish)
    }

    @Test func goBackReturnsToThePreviousStepAndStopsAtWelcome() {
        let (store, teardown) = Self.makeStore()
        defer { teardown() }
        let state = OnboardingState(settings: store.settings, detectedShellPath: "/bin/zsh")

        state.primaryAction(writingTo: store)
        state.primaryAction(writingTo: store)
        #expect(state.step == .finish)
        #expect(state.canGoBack == true)

        state.goBack()
        #expect(state.step == .appearance)
        state.goBack()
        #expect(state.step == .welcome)
        state.goBack()
        #expect(state.step == .welcome)
    }

    @Test func finishingWritesTheChoicesAndMarksOnboardingComplete() {
        let (store, teardown) = Self.makeStore()
        defer { teardown() }
        let state = OnboardingState(settings: store.settings, detectedShellPath: "/bin/zsh")
        state.selections.themeID = "nord"
        state.selections.fontSize = 17
        state.selections.shellPath = "/bin/bash"

        state.finish(writingTo: store)

        #expect(store.settings.themeID == "nord")
        #expect(Double(store.settings.fontSize) == 17)
        #expect(store.settings.defaultShellPath == "/bin/bash")
        #expect(store.settings.hasCompletedOnboarding == true)
        #expect(state.isFinished == true)
    }

    /// Atlama da bir tamamlanmadır: onboarding bir daha gösterilmez (brief 2 "Onboarding").
    @Test func skippingMarksOnboardingCompleteWithoutChangingAppearance() {
        let (store, teardown) = Self.makeStore()
        defer { teardown() }
        let before = store.settings
        let state = OnboardingState(settings: store.settings, detectedShellPath: "/bin/zsh")

        state.skip(writingTo: store)

        #expect(store.settings.hasCompletedOnboarding == true)
        #expect(store.settings.themeID == before.themeID)
        #expect(store.settings.fontName == before.fontName)
        #expect(Double(store.settings.fontSize) == Double(before.fontSize))
        #expect(store.settings.defaultShellPath == before.defaultShellPath)
        #expect(state.isFinished == true)
    }

    @Test func completionSurvivesAStoreReload() {
        let (defaults, suiteName) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        let state = OnboardingState(settings: store.settings, detectedShellPath: "/bin/zsh")
        state.skip(writingTo: store)

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.settings.hasCompletedOnboarding == true)
    }
}

@MainActor
@Suite struct OnboardingPreviewTests {

    @Test func previewHasContent() {
        #expect(OnboardingPreview.lines.isEmpty == false)
        let text = OnboardingPreview.lines
            .flatMap(\.segments)
            .map(\.text)
            .joined()
        #expect(text.contains("swift build"))
    }

    /// Temsili çıktı temanın 16 ANSI rengiyle boyanır; aralık dışı bir indeks
    /// sessizce yanlış renge düşerdi.
    @Test func everyAnsiReferenceIsInsideTheSixteenColorTable() {
        for line in OnboardingPreview.lines {
            for segment in line.segments {
                if case .ansi(let index) = segment.ink {
                    #expect((0..<16).contains(index))
                }
            }
        }
    }

    @Test func lineIdentifiersAreUnique() {
        let ids = OnboardingPreview.lines.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
