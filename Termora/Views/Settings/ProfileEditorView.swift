import AppKit
import SwiftUI

struct ProfileEditorView: View {
    @Binding var profile: TerminalProfile
    let shells: [ShellInfo]
    let themes: ThemeStore
    let fontFamilies: [String]
    /// brief 3 "Settings Tasarımı": tehlikeli işlem Danger Zone'dan çağrılır.
    let onDelete: () -> Void

    @State private var isConfirmingDelete = false

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: $profile.name)
            }

            Section("Launch") {
                Picker("Shell", selection: $profile.shellPath) {
                    Text("Use global setting").tag(nil as String?)
                    ForEach(shells) { shell in
                        Text(shell.displayName).tag(shell.path as String?)
                    }
                }

                HStack(spacing: 8) {
                    Text("Startup directory")
                    Spacer()
                    Text(profile.startupDirectory ?? "Use global setting")
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(.secondary)
                    // Bu ekranda üç ayrı "Clear" düğmesi var; her biri neyi temizlediğini söyler.
                    Button("Choose…") { chooseStartupDirectory() }
                        .accessibilityLabel("Choose Startup Directory")
                    Button("Clear") { profile.startupDirectory = nil }
                        .accessibilityLabel("Clear Startup Directory Override")
                        .disabled(profile.startupDirectory == nil)
                }

                TextField(
                    "Startup command",
                    text: startupCommandBinding,
                    prompt: Text("e.g. tmux attach")
                )
            }

            Section("Appearance Overrides") {
                Picker("Font", selection: $profile.fontName) {
                    Text("Use global setting").tag(nil as String?)
                    ForEach(fontFamilies, id: \.self) { family in
                        Text(family).tag(family as String?)
                    }
                }

                HStack(spacing: 8) {
                    Text("Font size")
                    Spacer()
                    Text(profile.fontSize.map { "\(Int($0)) pt" } ?? "Global setting")
                        .foregroundStyle(.secondary)
                    Stepper("", value: fontSizeBinding, in: SettingsLimits.fontSizeRange, step: 1)
                        .labelsHidden()
                        .accessibilityLabel("Font size")
                    Button("Clear") { profile.fontSize = nil }
                        .accessibilityLabel("Clear Font Size Override")
                        .disabled(profile.fontSize == nil)
                }

                Picker("Theme", selection: $profile.themeID) {
                    Text("Use global setting").tag(nil as String?)
                    ForEach(themes.themes) { theme in
                        Text(theme.name).tag(theme.id as String?)
                    }
                }
            }

            Section("Environment Variables") {
                ProfileEnvironmentEditor(environment: $profile.environment)
                    .id(profile.id)
            }

            Section {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Delete this profile")
                        Text("Open terminals keep running and fall back to the global settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Delete Profile…", role: .destructive) { isConfirmingDelete = true }
                }
            } header: {
                Label("Danger Zone", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(DesignTokens.danger.color)
            }
            .confirmationDialog(
                "Delete the profile “\(profile.name.isEmpty ? "Untitled Profile" : profile.name)”?",
                isPresented: $isConfirmingDelete
            ) {
                Button("Delete Profile", role: .destructive) { onDelete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone. Terminals launched from this profile keep running.")
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
        panel.prompt = "Choose"
        panel.message = "Select the startup folder for terminals launched from this profile."
        if let current = profile.startupDirectory {
            panel.directoryURL = URL(fileURLWithPath: current)
        }
        if panel.runModal() == .OK, let url = panel.url {
            profile.startupDirectory = url.path
        }
    }
}
