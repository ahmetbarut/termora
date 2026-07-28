import SwiftUI

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

    var body: some View {
        TabView {
            // brief 3 "Settings Tasarımı" sol menü adları; yalnız var olan bölümler.
            GeneralSettingsView(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }

            AppearanceSettingsView(settings: settings, themes: themes)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }

            ProfilesSettingsView(profiles: profiles, themes: themes)
                .tabItem { Label("Profiles", systemImage: "person.crop.rectangle.stack") }

            WorkspacesSettingsView(workspaces: workspaces,
                                   requestOpen: requestOpen,
                                   captureCurrentLayout: captureCurrentLayout)
                .tabItem { Label("Workspaces", systemImage: CommandPaletteCategory.workspaces.symbolName) }
        }
        .frame(width: 560, height: 480)
    }
}
