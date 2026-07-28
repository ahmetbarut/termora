import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var settings: SettingsStore

    @State private var shells: [ShellInfo] = []
    @State private var scrollbackText: String = ""

    var body: some View {
        Form {
            Section("Shell") {
                Picker("Default shell", selection: $settings.settings.defaultShellPath) {
                    Text("System default").tag(nil as String?)
                    ForEach(shells) { shell in
                        Text(shell.displayName).tag(shell.path as String?)
                    }
                }
            }

            Section("Startup Directory") {
                HStack(spacing: 8) {
                    Text(settings.settings.startupDirectory ?? "Home folder (~)")
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(.secondary)
                    Spacer()
                    // Görünen metin kısa tutulur; konuşulan etiket neyin değiştiğini söyler.
                    Button("Choose…") { chooseStartupDirectory() }
                        .accessibilityLabel("Choose Startup Directory")
                    Button("Clear") { settings.settings.startupDirectory = nil }
                        .accessibilityLabel("Clear Startup Directory")
                        .disabled(settings.settings.startupDirectory == nil)
                }
            }

            Section("Terminal") {
                HStack(spacing: 8) {
                    Text("Scrollback (lines)")
                    Spacer()
                    // Alanın görünen etiketi solundaki `Text`; ekran okuyucu ikisini
                    // ilişkilendiremediği için etiket burada tekrar edilir.
                    TextField("", text: $scrollbackText)
                        .frame(width: 90)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { commitScrollbackText() }
                        .accessibilityLabel("Scrollback lines")
                    Stepper("", value: scrollbackBinding, in: SettingsLimits.scrollbackRange, step: 500)
                        .labelsHidden()
                        .accessibilityLabel("Scrollback lines")
                }
                Text("100 – 100,000. Values outside the range are clamped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Show status bar", isOn: $settings.settings.showStatusBar)
            }

            Section("Startup") {
                Toggle("Restore windows and tabs from last session",
                       isOn: $settings.settings.restoresPreviousSession)
                    // Vaadin sınırı açıkça yazılır (briefs/2): süreçler devam etmez.
                    // Aynı cümle VoiceOver'a da gider; durum yalnız anahtarın görünümünden
                    // anlaşılmasın diye açıklama etikete bağlanır.
                    .accessibilityHint("Reopens your windows, tabs and split panes in their "
                                       + "saved folders. New shells are started, and startup "
                                       + "commands are not run again.")
                Text("Windows, tabs and split panes reopen in their saved folders. "
                     + "New shells are started — running commands do not continue — "
                     + "and startup commands are not run again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        panel.prompt = "Choose"
        panel.message = "Select the folder new terminals open in."
        if let current = settings.settings.startupDirectory {
            panel.directoryURL = URL(fileURLWithPath: current)
        }
        if panel.runModal() == .OK, let url = panel.url {
            settings.settings.startupDirectory = url.path
        }
    }
}
