import AppKit
import SwiftUI

struct ProfileEditorView: View {
    @Binding var profile: TerminalProfile
    let shells: [ShellInfo]
    let themes: ThemeStore
    let fontFamilies: [String]

    var body: some View {
        Form {
            Section("Kimlik") {
                TextField("Ad", text: $profile.name)
            }

            Section("Başlatma") {
                Picker("Kabuk", selection: $profile.shellPath) {
                    Text("Genel ayarı kullan").tag(nil as String?)
                    ForEach(shells) { shell in
                        Text(shell.displayName).tag(shell.path as String?)
                    }
                }

                HStack(spacing: 8) {
                    Text("Başlangıç klasörü")
                    Spacer()
                    Text(profile.startupDirectory ?? "Genel ayarı kullan")
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(.secondary)
                    Button("Seç…") { chooseStartupDirectory() }
                    Button("Temizle") { profile.startupDirectory = nil }
                        .disabled(profile.startupDirectory == nil)
                }

                TextField(
                    "Başlangıç komutu",
                    text: startupCommandBinding,
                    prompt: Text("örn. tmux attach")
                )
            }

            Section("Görünüm geçersiz kılmaları") {
                Picker("Yazı tipi", selection: $profile.fontName) {
                    Text("Genel ayarı kullan").tag(nil as String?)
                    ForEach(fontFamilies, id: \.self) { family in
                        Text(family).tag(family as String?)
                    }
                }

                HStack(spacing: 8) {
                    Text("Yazı boyutu")
                    Spacer()
                    Text(profile.fontSize.map { "\(Int($0)) pt" } ?? "Genel ayar")
                        .foregroundStyle(.secondary)
                    Stepper("", value: fontSizeBinding, in: SettingsLimits.fontSizeRange, step: 1)
                        .labelsHidden()
                    Button("Temizle") { profile.fontSize = nil }
                        .disabled(profile.fontSize == nil)
                }

                Picker("Tema", selection: $profile.themeID) {
                    Text("Genel ayarı kullan").tag(nil as String?)
                    ForEach(themes.themes) { theme in
                        Text(theme.name).tag(theme.id as String?)
                    }
                }
            }

            Section("Ortam değişkenleri") {
                ProfileEnvironmentEditor(environment: $profile.environment)
                    .id(profile.id)
            }
        }
        .formStyle(.grouped)
    }

    private var startupCommandBinding: Binding<String> {
        Binding(
            get: { profile.startupCommand ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                profile.startupCommand = trimmed.isEmpty ? nil : newValue
            }
        )
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { profile.fontSize ?? SettingsLimits.defaultFontSize },
            set: { profile.fontSize = SettingsLimits.clampFontSize($0) }
        )
    }

    private func chooseStartupDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Seç"
        panel.message = "Bu profille açılan terminallerin başlangıç klasörünü seçin."
        if let current = profile.startupDirectory {
            panel.directoryURL = URL(fileURLWithPath: current)
        }
        if panel.runModal() == .OK, let url = panel.url {
            profile.startupDirectory = url.path
        }
    }
}
