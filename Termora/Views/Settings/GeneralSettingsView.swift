import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var settings: SettingsStore

    @State private var shells: [ShellInfo] = []
    @State private var scrollbackText: String = ""

    var body: some View {
        Form {
            Section("Kabuk") {
                Picker("Varsayılan kabuk", selection: $settings.settings.defaultShellPath) {
                    Text("Sistem varsayılanı").tag(nil as String?)
                    ForEach(shells) { shell in
                        Text(shell.displayName).tag(shell.path as String?)
                    }
                }
            }

            Section("Başlangıç klasörü") {
                HStack(spacing: 8) {
                    Text(settings.settings.startupDirectory ?? "Ana klasör (~)")
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Seç…") { chooseStartupDirectory() }
                    Button("Temizle") { settings.settings.startupDirectory = nil }
                        .disabled(settings.settings.startupDirectory == nil)
                }
            }

            Section("Terminal") {
                HStack(spacing: 8) {
                    Text("Kaydırma geçmişi (satır)")
                    Spacer()
                    TextField("", text: $scrollbackText)
                        .frame(width: 90)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { commitScrollbackText() }
                    Stepper("", value: scrollbackBinding, in: SettingsLimits.scrollbackRange, step: 500)
                        .labelsHidden()
                }
                Text("100 – 100.000 arası. Aralık dışı değerler kırpılır.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Durum çubuğunu göster", isOn: $settings.settings.showStatusBar)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            shells = ShellService.availableShells()
            scrollbackText = String(settings.settings.scrollbackLines)
        }
        .onChange(of: settings.settings.scrollbackLines) { _, newValue in
            scrollbackText = String(newValue)
        }
    }

    private var scrollbackBinding: Binding<Int> {
        Binding(
            get: { settings.settings.scrollbackLines },
            set: { settings.settings.scrollbackLines = SettingsLimits.clampScrollback($0) }
        )
    }

    private func commitScrollbackText() {
        let value = SettingsLimits.scrollback(
            fromText: scrollbackText,
            fallback: settings.settings.scrollbackLines
        )
        settings.settings.scrollbackLines = value
        scrollbackText = String(value)
    }

    private func chooseStartupDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Seç"
        panel.message = "Yeni terminallerin açılacağı klasörü seçin."
        if let current = settings.settings.startupDirectory {
            panel.directoryURL = URL(fileURLWithPath: current)
        }
        if panel.runModal() == .OK, let url = panel.url {
            settings.settings.startupDirectory = url.path
        }
    }
}
