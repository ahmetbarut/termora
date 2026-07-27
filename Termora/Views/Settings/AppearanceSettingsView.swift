import AppKit
import SwiftUI

struct AppearanceSettingsView: View {
    @Bindable var settings: SettingsStore
    let themes: ThemeStore

    @State private var fontFamilies: [String] = []

    var body: some View {
        Form {
            Section("Tema") {
                Picker("Tema", selection: $settings.settings.themeID) {
                    ForEach(themes.themes) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                ThemePreviewView(theme: themes.theme(id: settings.settings.themeID))
            }

            Section("Yazı tipi") {
                Picker("Aile", selection: $settings.settings.fontName) {
                    Text("Varsayılan (\(FontCatalog.fallbackFamily))").tag(nil as String?)
                    ForEach(fontFamilies, id: \.self) { family in
                        Text(family).tag(family as String?)
                    }
                }

                Stepper(value: fontSizeBinding, in: SettingsLimits.fontSizeRange, step: 1) {
                    Text("Boyut: \(Int(settings.settings.fontSize)) pt")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Slider(value: lineSpacingBinding, in: SettingsLimits.lineSpacingRange, step: 0.05) {
                        Text("Satır aralığı")
                    }
                    Text(String(format: "%.2f×", settings.settings.lineSpacing))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("İmleç ve pencere") {
                Picker("İmleç şekli", selection: $settings.settings.cursorStyle) {
                    ForEach(CursorStyleSetting.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Slider(value: opacityBinding, in: SettingsLimits.opacityRange, step: 0.05) {
                        Text("Pencere saydamlığı")
                    }
                    Text("%\(Int((settings.settings.windowOpacity * 100).rounded())) opaklık")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            fontFamilies = FontCatalog.availableMonospacedFamilies()
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
