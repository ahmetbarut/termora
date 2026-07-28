import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var settings: SettingsStore

    @State private var shells: [ShellInfo] = []
    @State private var scrollbackText: String = ""
    @State private var notificationThresholdText: String = ""

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

            Section("Session") {
                Toggle("Restore windows and tabs from last session",
                       isOn: $settings.settings.restoresPreviousSession)
                    // Vaadin sınırı hem görsel açıklamada hem VoiceOver ipucunda durur:
                    // anahtarın durumu tek başına "süreçler devam eder mi?" sorusunu
                    // cevaplamaz (briefs/2).
                    .accessibilityHint("New shells are started; startup commands are not run again.")
                Text("Windows, tabs and split panes reopen in their saved folders. "
                     + "New shells are started — running commands do not continue — "
                     + "and startup commands are not run again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            notificationsSection
        }
        .formStyle(.grouped)
        .onAppear {
            shells = ShellService.availableShells()
            scrollbackText = String(settings.settings.scrollbackLines)
            notificationThresholdText = Self.thresholdText(settings.settings.longCommandThresholdSeconds)
        }
        .onChange(of: settings.settings.scrollbackLines) { _, newValue in
            scrollbackText = String(newValue)
        }
        .onChange(of: settings.settings.longCommandThresholdSeconds) { _, newValue in
            notificationThresholdText = Self.thresholdText(newValue)
        }
    }

    // MARK: - Notifications (briefs/2 "Bildirimler")

    @ViewBuilder
    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle("Notify when a long-running command finishes",
                   isOn: $settings.settings.notifiesOnLongCommands)
                // The permission prompt is the surprising part; say so before it appears.
                .accessibilityHint("macOS asks for notification permission the first time a command qualifies.")

            HStack(spacing: 8) {
                Text("Only for commands longer than")
                Spacer()
                // The visible label is the `Text` to its left; VoiceOver cannot connect the
                // two, so the field repeats it.
                TextField("", text: $notificationThresholdText)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                    .onSubmit { commitNotificationThreshold() }
                    .accessibilityLabel("Minimum command duration in seconds")
                Stepper("", value: thresholdBinding, in: CommandNotificationLimits.thresholdRange, step: 15)
                    .labelsHidden()
                    .accessibilityLabel("Minimum command duration in seconds")
                Text("seconds")
                    .foregroundStyle(.secondary)
            }
            // Only the dependent controls are disabled — putting `.disabled` on the Section
            // would dim the master switch too and the user could never turn the feature
            // back on.
            .disabled(!settings.settings.notifiesOnLongCommands)

            Toggle("Notify for completed commands", isOn: $settings.settings.notifiesOnCommandSuccess)
                .disabled(!settings.settings.notifiesOnLongCommands)
            Toggle("Notify for failed commands", isOn: $settings.settings.notifiesOnCommandFailure)
                .disabled(!settings.settings.notifiesOnLongCommands)

            // Honest about what Termora can observe: it watches the terminal's foreground job,
            // not the shell's exit status, so most completions carry no success/failure verdict.
            Text("Termora notices a command by watching which process owns the terminal, "
                 + "so it reports that a command finished — not whether it succeeded. "
                 + "Commands are announced only while you are looking at another window or tab, "
                 + "and a profile can turn them off for its own terminals.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var thresholdBinding: Binding<Double> {
        Binding(
            get: { settings.settings.longCommandThresholdSeconds },
            set: { settings.settings.longCommandThresholdSeconds = CommandNotificationLimits.clampThreshold($0) }
        )
    }

    private func commitNotificationThreshold() {
        let value = CommandNotificationLimits.threshold(
            fromText: notificationThresholdText,
            fallback: settings.settings.longCommandThresholdSeconds
        )
        settings.settings.longCommandThresholdSeconds = value
        notificationThresholdText = Self.thresholdText(value)
    }

    /// Whole seconds: the field takes an integer count, and the stored value is clamped into
    /// a range whose bounds are whole seconds anyway.
    private static func thresholdText(_ seconds: Double) -> String {
        String(Int(CommandNotificationLimits.clampThreshold(seconds).rounded()))
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
