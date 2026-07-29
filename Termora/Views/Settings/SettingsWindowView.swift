import SwiftUI

/// Ayarlar penceresinin bölümleri (briefs/2 "Ayarlar Ekranı" listesi, briefs/3 sıra).
///
/// Listede YALNIZ var olan bölümler bulunur; brief'in geri kalanı (Terminal, AI,
/// Keybindings, Updates, About) uygulanana kadar boş bir sekme olarak gösterilmez.
enum SettingsTab: String, CaseIterable {
    case general
    case appearance
    case terminal
    case profiles
    case workspaces
    case ssh
    case ai
    case keybindings
    case privacy
    case license
    case updates
    case about

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .terminal: "Terminal"
        case .profiles: "Profiles"
        case .workspaces: "Workspaces"
        case .ssh: "SSH"
        case .ai: "AI"
        case .keybindings: "Keybindings"
        case .privacy: "Privacy"
        case .license: "License"
        case .updates: "Updates"
        case .about: "About"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .terminal: "terminal"
        case .profiles: "person.crop.rectangle.stack"
        case .workspaces: CommandPaletteCategory.workspaces.symbolName
        case .ssh: CommandPaletteCategory.ssh.symbolName
        case .ai: "sparkles"
        case .keybindings: "keyboard"
        case .privacy: "hand.raised"
        case .license: "checkmark.seal"
        case .updates: "arrow.down.circle"
        case .about: "info.circle"
        }
    }
}

struct SettingsWindowView: View {
    let settings: SettingsStore
    let themes: ThemeStore
    /// Profiller sekmesi Task 19'da bu depoyu kullanır.
    let profiles: ProfileStore
    let workspaces: WorkspaceStore
    /// Ayarlar penceresinin kendi terminal penceresi yok; açılış isteğini
    /// anahtar pencereye iletir (bkz. AppServices.workspaceOpenRequest).
    let requestOpen: (Workspace) -> Void
    let captureCurrentLayout: () -> [WorkspaceTab]
    let savedCommands: SavedCommandStore
    /// Kayıtlı SSH profilleri. Varsayılan paylaşılan örnektir: bu pencereyi kuran
    /// `TermoraApp` bu görevin kapsamı dışında olduğu için depo oradan geçirilemiyor
    /// (bkz. `SSHHostStore.shared`).
    var ssh: SSHHostStore = .shared
    /// Ayarlar penceresinin terminali yok; bağlanma isteği anahtar pencereye iletilir.
    var connectSSH: ((SSHTarget) -> Void)?
    /// Kurulu Ollama modelleri. Panelle AYNI mantığı paylaşır (bkz. `AIModelCatalog`),
    /// böylece iki ekran "model yok" durumunu aynı cümlelerle anlatır.
    /// Verilmezse `AppServices`'in kaydettiği kataloğa düşer.
    var aiCatalog: AIModelCatalog?
    /// Kurulu lisans. Varsayılan paylaşılan örnektir; `TermoraApp` kendi deposunu geçirir.
    var license: LicenseStore = .shared

    var body: some View {
        TabView {
            // brief 3 "Settings Tasarımı" sol menü adları; yalnız var olan bölümler.
            GeneralSettingsView(settings: settings)
                .tabItem { label(for: .general) }

            AppearanceSettingsView(settings: settings, themes: themes)
                .tabItem { label(for: .appearance) }

            TerminalSettingsView(settings: settings, savedCommands: savedCommands)
                .tabItem { label(for: .terminal) }

            ProfilesSettingsView(profiles: profiles, themes: themes)
                .tabItem { label(for: .profiles) }

            WorkspacesSettingsView(workspaces: workspaces,
                                   requestOpen: requestOpen,
                                   captureCurrentLayout: captureCurrentLayout)
                .tabItem { label(for: .workspaces) }

            SSHSettingsView(hosts: ssh, connect: connectSSH)
                .tabItem { label(for: .ssh) }

            if let catalog = aiCatalog ?? AIModelCatalog.current {
                AISettingsView(catalog: catalog, settings: settings)
                    .tabItem { label(for: .ai) }
            }

            KeybindingsSettingsView(settings: settings)
                .tabItem { label(for: .keybindings) }

            PrivacySettingsView(settings: settings)
                .tabItem { label(for: .privacy) }

            LicenseSettingsView(license: license)
                .tabItem { label(for: .license) }

            UpdatesSettingsView(settings: settings)
                .tabItem { label(for: .updates) }

            AboutSettingsView()
                .tabItem { label(for: .about) }
        }
        .frame(width: 560, height: 480)
    }

    private func label(for tab: SettingsTab) -> some View {
        Label(tab.title, systemImage: tab.symbolName)
    }
}
