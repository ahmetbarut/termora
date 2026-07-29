import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var settings: SettingsStore

    @State private var shells: [ShellInfo] = []
    @State private var scrollbackText: String = ""
    @State private var notificationThresholdText: String = ""

    /// Kancaların kurulu olup olmadığı DOSYADAN okunur, bir ayardan değil: kullanıcı
    /// bloğu elle silmiş olabilir ve Termora "kurulu" demeye devam ederdi.
    @State private var isIntegrationInstalled = false
    @State private var integrationFailure: String?
    private let installer = ShellIntegrationInstaller()

    /// Kancaların yazılacağı kabuk. Ayarlardaki varsayılan kabuk boşsa kullanıcının
    /// giriş kabuğuna düşülür — Termora burada bir kabuk UYDURMAZ.
    private var integrationFamily: ShellFamily? {
        ShellFamily(shellPath: settings.settings.defaultShellPath ?? ShellService.defaultShellPath())
    }

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

            Section(ShellIntegrationContent.title) {
                if let family = integrationFamily {
                    Text(ShellIntegrationContent.explanation(for: family))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        // Dotfile'a yazan TEK yol bu düğmedir; Termora kendiliğinden yazmaz.
                        Button(isIntegrationInstalled
                               ? ShellIntegrationContent.uninstallTitle
                               : ShellIntegrationContent.installTitle) {
                            applyIntegration(install: !isIntegrationInstalled, family: family)
                        }
                        if isIntegrationInstalled {
                            Text(ShellIntegrationContent.installedNote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let integrationFailure {
                        // Başarısız yazma SESSİZ kalmaz: kullanıcı kurulduğunu sanırdı.
                        Text(integrationFailure)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.warning.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    // Ölü bir düğme yerine dürüst bir cümle.
                    Text(ShellIntegrationContent.unsupportedShellNote(
                        shellPath: settings.settings.defaultShellPath ?? ShellService.defaultShellPath()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

                // briefs/3 "Yeni Sekme Ekranı": varsayılan KAPALI — yeni sekme doğrudan
                // shell açar ve bu ekran araya girmez.
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Ask what to open on ⌘T", isOn: $settings.settings.showsNewTabLauncher)
                    Text("Off by default: ⌘T starts your shell right away. Turn this on to "
                         + "pick a folder, workspace or SSH host first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

            soundsSection
        }
        .formStyle(.grouped)
        .onAppear {
            shells = ShellService.availableShells()
            scrollbackText = String(settings.settings.scrollbackLines)
            notificationThresholdText = Self.thresholdText(settings.settings.longCommandThresholdSeconds)
            refreshIntegrationState()
        }
        // Varsayılan kabuk değişince kancaların hedef dosyası da değişir.
        .onChange(of: settings.settings.defaultShellPath) { _, _ in
            refreshIntegrationState()
        }
        .onChange(of: settings.settings.scrollbackLines) { _, newValue in
            scrollbackText = String(newValue)
        }
        .onChange(of: settings.settings.longCommandThresholdSeconds) { _, newValue in
            notificationThresholdText = Self.thresholdText(newValue)
        }
    }

    // MARK: - Shell integration

    private func refreshIntegrationState() {
        integrationFailure = nil
        isIntegrationInstalled = integrationFamily.map { installer.isInstalled(for: $0) } ?? false
    }

    /// Kullanıcının dosyasına yazan tek yol. Hata SESSİZ kalmaz ve durum dosyadan
    /// YENİDEN okunur — "yazdım" demek yetmez, yazılmış olduğunu görmek gerekir.
    private func applyIntegration(install: Bool, family: ShellFamily) {
        do {
            if install {
                try installer.install(for: family)
            } else {
                try installer.uninstall(for: family)
            }
            integrationFailure = nil
        } catch {
            integrationFailure = "~/\(family.startupFileName) could not be updated: "
                + error.localizedDescription
        }
        isIntegrationInstalled = installer.isInstalled(for: family)
    }

    // MARK: - Sounds (briefs/3 "Ses Kullanımı")

    /// briefs/3 "Ses Kullanımı": *Uygulama varsayılan olarak sessiz olmalıdır* ve
    /// *her ses ayrı ayrı kapatılabilmelidir.*
    @ViewBuilder
    private var soundsSection: some View {
        Section {
            ForEach(SoundEvent.allCases) { event in
                VStack(alignment: .leading, spacing: 1) {
                    Toggle(event.title, isOn: Binding(
                        get: { settings.settings.isSoundEnabled(event) },
                        set: { settings.settings.setSoundEnabled(event, $0) }
                    ))
                    Text(event.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Toggle("Flash the terminal instead of ringing",
                       isOn: $settings.settings.usesVisualBell)
                Text("A short flash when a program rings the bell. Works whether or not the "
                     + "bell sound is on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Sounds")
        } footer: {
            Text("Termora is silent until you turn something on here.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
