import SwiftUI

/// briefs/2 "Ayarlar Ekranı" ▸ Terminal.
///
/// Bu ayarlar daha önce Appearance içindeydi. Ayrılmalarının sebebi brief'in listesi
/// değil, ne oldukları: Appearance terminalin NASIL GÖRÜNDÜĞÜNÜ, burası NASIL
/// ÇALIŞTIĞINI belirler — hangi kabuk, nerede açılır, ne kadar geçmiş tutulur.
struct TerminalSettingsView: View {

    let settings: SettingsStore

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
        }
        .formStyle(.grouped)
        .onAppear(perform: loadDrafts)
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
