import SwiftUI

/// briefs/2 "Ayarlar Ekranı" ▸ Terminal.
///
/// Bu ayarlar daha önce Appearance içindeydi. Ayrılmalarının sebebi brief'in listesi
/// değil, ne oldukları: Appearance terminalin NASIL GÖRÜNDÜĞÜNÜ, burası NASIL
/// ÇALIŞTIĞINI belirler — hangi kabuk, nerede açılır, ne kadar geçmiş tutulur.
struct TerminalSettingsView: View {

    @Bindable var settings: SettingsStore
    /// briefs/3 "Sidebar" ▸ Saved Commands. Düzenleme burada yaşıyor: komutlar
    /// terminale ait ve brief ayrı bir sekme saymıyor.
    let savedCommands: SavedCommandStore

    /// Yol alanları yazarken her tuşta ayara YAZILMAZ: yarım yazılmış bir yol
    /// (`/usr/local/bi`) kaydedilir ve yeni sekme açılmaz olurdu.
    @State private var shellDraft = ""
    @State private var directoryDraft = ""
    @State private var scrollbackDraft = ""

    var body: some View {
        Form {
            Section {
                TextField("Shell path", text: $shellDraft, prompt: Text("Login shell"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commitShell)
                    .accessibilityHint("Leave empty to use your login shell")

                HStack {
                    Text("Empty means your login shell, the one macOS opens for your account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose…") { chooseShell() }
                }
            } header: {
                Text("Shell")
            }

            Section {
                TextField("Startup directory", text: $directoryDraft, prompt: Text("Home directory"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commitDirectory)
                    .accessibilityHint("Leave empty to start new terminals in your home directory")

                HStack {
                    Text("New terminals open here. Empty means your home directory.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose…") { chooseDirectory() }
                }
            } header: {
                Text("Startup")
            }

            Section {
                TextField("Scrollback lines", text: $scrollbackDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commitScrollback)
                    .accessibilityLabel("Scrollback lines")

                Text("How many lines of history each terminal keeps. "
                     + "Between \(SettingsLimits.scrollbackRange.lowerBound) and "
                     + "\(SettingsLimits.scrollbackRange.upperBound).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("History")
            }

            Section {
                Toggle("Use Option key as Meta (Esc)", isOn: $settings.settings.optionKeySendsMeta)
                Text("Off (default): Option types the character printed on the key — "
                     + "Option+4 gives “$”, Option+5 gives “€”. "
                     + "On: Option sends an Esc-prefixed Meta sequence for shell/emacs "
                     + "shortcuts (Option+b jumps back a word).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Keyboard")
            }

            savedCommandsSection
        }
        .formStyle(.grouped)
        .onAppear(perform: loadDrafts)
    }

    /// Liste + satır içi düzenleme. Ayrı bir editör penceresi açmak, iki alanı olan bir
    /// kayıt için gereğinden ağır olurdu.
    @ViewBuilder
    private var savedCommandsSection: some View {
        Section {
            if savedCommands.commands.isEmpty {
                // briefs/3 "Empty State": tek cümle, nereden geldiğini söyler.
                Text("Save a command from the Command Blocks panel, then find it here or in "
                     + "the command palette.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(savedCommands.commands) { command in
                    SavedCommandRow(command: command,
                                    onChange: { savedCommands.update($0) },
                                    onDelete: { savedCommands.remove(id: command.id) })
                }
            }
        } header: {
            Text("Saved Commands")
        }
    }

    private func loadDrafts() {
        shellDraft = settings.settings.defaultShellPath ?? ""
        directoryDraft = settings.settings.startupDirectory ?? ""
        scrollbackDraft = String(settings.settings.scrollbackLines)
    }

    /// Boş alan "ayar yok" demektir ve `nil` yazılır: boş dize kaydetmek, kabuk yolu
    /// olarak boş bir yol denenmesine yol açardı.
    private func commitShell() {
        let trimmed = shellDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.settings.defaultShellPath = trimmed.isEmpty ? nil : trimmed
        shellDraft = settings.settings.defaultShellPath ?? ""
    }

    private func commitDirectory() {
        let trimmed = directoryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.settings.startupDirectory = trimmed.isEmpty ? nil : trimmed
        directoryDraft = settings.settings.startupDirectory ?? ""
    }

    /// Ayrıştırılamayan girdi mevcut değere düşer ve her hâlde sınırlara kırpılır.
    private func commitScrollback() {
        let value = SettingsLimits.scrollback(fromText: scrollbackDraft,
                                              fallback: settings.settings.scrollbackLines)
        settings.settings.scrollbackLines = value
        scrollbackDraft = String(value)
    }

    private func chooseShell() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/bin")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        shellDraft = url.path
        commitShell()
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        directoryDraft = url.path
        commitDirectory()
    }
}


// MARK: - Kayıtlı komut satırı

/// Tek bir kayıtlı komut: ad, komut ve —riskliyse— uyarı.
private struct SavedCommandRow: View {
    let command: SavedCommand
    let onChange: (SavedCommand) -> Void
    let onDelete: () -> Void

    @State private var nameDraft = ""
    @State private var commandDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Name", text: $nameDraft, prompt: Text(command.command))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commit)
                Button("Delete", role: .destructive, action: onDelete)
            }
            TextField("Command", text: $commandDraft)
                .textFieldStyle(.roundedBorder)
                .font(.callout.monospaced())
                .onSubmit(commit)

            if command.isRisky {
                // briefs/2 "Tehlikeli Komut Koruması": kayıt engellenmez ama söylenir.
                // Renk tek gösterge değil — simge ve cümle de var.
                Label("This command is hard to undo. Termora writes it to the terminal but "
                      + "never runs it for you.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.warning.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            nameDraft = command.name
            commandDraft = command.command
        }
    }

    /// Boş komut kaydı DEPO tarafından reddedilir; alan eski değerine döner ki kullanıcı
    /// kaydettiğini sanmasın.
    private func commit() {
        var edited = command
        edited.name = nameDraft
        edited.command = commandDraft
        onChange(edited)
        commandDraft = commandDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? command.command : commandDraft
    }
}
