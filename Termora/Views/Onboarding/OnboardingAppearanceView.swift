import AppKit
import SwiftUI

/// Ekran 2: algılanan shell, font seçimi, tema seçimi ve canlı terminal önizlemesi
/// (brief 3 "İlk Açılış Akışı"). Seçimler akış bitince ayarlara yazılır.
struct OnboardingAppearanceView: View {
    @Bindable var state: OnboardingState
    let themes: ThemeStore

    @State private var shells: [ShellInfo] = []
    @State private var fontMenu = FontCatalog.FontMenu(recommended: [], others: [])

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Shell and appearance")
                .font(.system(size: 17, weight: .semibold))

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Shell")
                        .gridColumnAlignment(.trailing)
                        .foregroundStyle(.secondary)
                    Picker("Shell", selection: $state.selections.shellPath) {
                        ForEach(shellChoices) { shell in
                            Text(label(for: shell)).tag(shell.path)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Shell")
                }

                GridRow {
                    Text("Font")
                        .gridColumnAlignment(.trailing)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Picker("Font", selection: $state.selections.fontName) {
                            ForEach(fontMenu.recommended, id: \.self) { family in
                                Text(family).tag(family as String?)
                            }
                            if !fontMenu.others.isEmpty {
                                Divider()
                                ForEach(fontMenu.others, id: \.self) { family in
                                    Text(family).tag(family as String?)
                                }
                            }
                            Divider()
                            Text("System Monospace").tag(nil as String?)
                        }
                        .labelsHidden()
                        .accessibilityLabel("Font family")

                        Stepper(value: fontSizeBinding, in: SettingsLimits.fontSizeRange, step: 1) {
                            Text("\(Int(state.selections.fontSize)) pt")
                                .monospacedDigit()
                        }
                        .accessibilityLabel("Font size")
                        .accessibilityValue("\(Int(state.selections.fontSize)) points")
                    }
                }

                GridRow {
                    Text("Theme")
                        .gridColumnAlignment(.trailing)
                        .foregroundStyle(.secondary)
                    Picker("Theme", selection: $state.selections.themeID) {
                        ForEach(themes.themes) { theme in
                            Text(theme.name).tag(theme.id)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Theme")
                }
            }

            OnboardingTerminalPreview(
                theme: themes.theme(id: state.selections.themeID),
                fontName: state.selections.fontName,
                fontSize: state.selections.fontSize
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .onAppear {
            shells = ShellService.availableShells()
            fontMenu = FontCatalog.availableFontMenu()
        }
    }

    /// Algılanan shell listede yoksa (ör. /etc/shells'te yazmıyorsa) yine de seçilebilir
    /// kalmalı: aksi hâlde Picker boş bir seçimle açılır.
    private var shellChoices: [ShellInfo] {
        let detected = state.selections.detectedShellPath
        var choices = shells
        if !choices.contains(where: { $0.path == detected }) {
            choices.insert(
                ShellInfo(path: detected, displayName: (detected as NSString).lastPathComponent),
                at: 0)
        }
        if !choices.contains(where: { $0.path == state.selections.shellPath }) {
            let current = state.selections.shellPath
            choices.append(
                ShellInfo(path: current, displayName: (current as NSString).lastPathComponent))
        }
        return choices
    }

    private func label(for shell: ShellInfo) -> String {
        shell.path == state.selections.detectedShellPath
            ? "\(shell.displayName) — detected"
            : shell.displayName
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { state.selections.fontSize },
            set: { state.selections.fontSize = SettingsLimits.clampFontSize($0) }
        )
    }
}
