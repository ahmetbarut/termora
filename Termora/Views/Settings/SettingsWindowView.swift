import SwiftUI

/// Ayarlar penceresinin bölümleri (briefs/2 "Ayarlar Ekranı" listesi, briefs/3 sıra).
///
/// Listede YALNIZ var olan bölümler bulunur; brief'in geri kalanı (Terminal, AI,
/// Keybindings, Updates, About) uygulanana kadar boş bir sekme olarak gösterilmez.
enum SettingsTab: String, CaseIterable {
    case general
    case appearance
    case profiles
    case workspaces
    case ssh
    case ai
    case privacy

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .profiles: "Profiles"
        case .workspaces: "Workspaces"
        case .ssh: "SSH"
        case .ai: "AI"
        case .privacy: "Privacy"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .profiles: "person.crop.rectangle.stack"
        case .workspaces: CommandPaletteCategory.workspaces.symbolName
        case .ssh: CommandPaletteCategory.ssh.symbolName
        case .ai: "sparkles"
        case .privacy: "hand.raised"
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

    var body: some View {
        TabView {
            // brief 3 "Settings Tasarımı" sol menü adları; yalnız var olan bölümler.
            GeneralSettingsView(settings: settings)
                .tabItem { label(for: .general) }

            AppearanceSettingsView(settings: settings, themes: themes)
                .tabItem { label(for: .appearance) }

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

            PrivacySettingsView()
                .tabItem { label(for: .privacy) }
        }
        .frame(width: 560, height: 480)
    }

    private func label(for tab: SettingsTab) -> some View {
        Label(tab.title, systemImage: tab.symbolName)
    }
}
