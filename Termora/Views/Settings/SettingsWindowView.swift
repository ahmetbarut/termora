import SwiftUI

struct SettingsWindowView: View {
    let settings: SettingsStore
    let themes: ThemeStore
    /// Profiller sekmesi Task 19'da bu depoyu kullanır.
    let profiles: ProfileStore

    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings)
                .tabItem { Label("Genel", systemImage: "gearshape") }

            AppearanceSettingsView(settings: settings, themes: themes)
                .tabItem { Label("Görünüm", systemImage: "paintpalette") }

            ProfilesSettingsView(profiles: profiles, themes: themes)
                .tabItem { Label("Profiller", systemImage: "person.crop.rectangle.stack") }
        }
        .frame(width: 560, height: 480)
    }
}
