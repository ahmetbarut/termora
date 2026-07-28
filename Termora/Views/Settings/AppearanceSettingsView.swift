import AppKit
import SwiftUI

struct AppearanceSettingsView: View {
    @Bindable var settings: SettingsStore
    let themes: ThemeStore

    @State private var fontMenu = FontCatalog.FontMenu(recommended: [], others: [])

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Theme", selection: $settings.settings.themeID) {
                    ForEach(themes.themes) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                ThemePreviewView(theme: themes.theme(id: settings.settings.themeID))
            }

            Section("Font") {
                Picker("Family", selection: $settings.settings.fontName) {
                    // brief 3 "Alternatif fontlar": önerilenler üstte, kurulu olmayanlar hiç yok.
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

                Stepper(value: fontSizeBinding, in: SettingsLimits.fontSizeRange, step: 1) {
                    Text("Size: \(Int(settings.settings.fontSize)) pt")
                }

                VStack(alignment: .leading, spacing: 2) {
                    // Değer ayrı bir `Text`'te gösteriliyor; ekran okuyucu onu kaydırıcıya
                    // bağlayamadığı için değer açıkça bildirilir.
                    Slider(value: lineSpacingBinding, in: SettingsLimits.lineSpacingRange, step: 0.05) {
                        Text("Line height")
                    }
                    .accessibilityValue(String(format: "%.2f times", settings.settings.lineSpacing))

                    Text(String(format: "%.2f×", settings.settings.lineSpacing))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }

            Section("Cursor & Window") {
                Picker("Cursor shape", selection: $settings.settings.cursorStyle) {
                    ForEach(CursorStyleSetting.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Slider(value: opacityBinding, in: SettingsLimits.opacityRange, step: 0.05) {
                        Text("Window opacity")
                    }
                    .accessibilityValue(
                        "\(Int((settings.settings.windowOpacity * 100).rounded())) percent opaque")

                    Text("\(Int((settings.settings.windowOpacity * 100).rounded()))% opaque")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            fontMenu = FontCatalog.availableFontMenu()
        }
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { settings.settings.fontSize },
            set: { settings.settings.fontSize = SettingsLimits.clampFontSize($0) }
        )
    }

    private var lineSpacingBinding: Binding<Double> {
        Binding(
            get: { settings.settings.lineSpacing },
            set: { settings.settings.lineSpacing = SettingsLimits.clampLineSpacing($0) }
        )
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { settings.settings.windowOpacity },
            set: { settings.settings.windowOpacity = SettingsLimits.clampOpacity($0) }
        )
    }
}
