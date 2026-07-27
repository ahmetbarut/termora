import SwiftUI

struct ProfilesSettingsView: View {
    @Bindable var profiles: ProfileStore
    let themes: ThemeStore

    @State private var selection: UUID?
    @State private var shells: [ShellInfo] = []
    @State private var fontFamilies: [String] = []

    /// `selection` geçersizleştiğinde okunan kararlı yer tutucu (yeni UUID üretmez).
    /// Force unwrap yok (brief bölüm 2, geliştirme kuralları): sıfır UUID'si
    /// `UUID(uuid:)` ile doğrudan kurulur, ayrıştırılacak bir metin yoktur.
    private static let placeholder = TerminalProfile(
        id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
        name: ""
    )

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(profiles.profiles) { profile in
                        Text(profile.name.isEmpty ? "Adsız profil" : profile.name)
                            .tag(profile.id)
                    }
                }

                Divider()

                HStack(spacing: 4) {
                    Button {
                        addProfile()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Yeni profil ekle")

                    Button {
                        removeSelectedProfile()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .help("Seçili profili sil")
                    .disabled(selection == nil)

                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 180)

            Divider()

            Group {
                if let editorBinding {
                    ProfileEditorView(
                        profile: editorBinding,
                        shells: shells,
                        themes: themes,
                        fontFamilies: fontFamilies
                    )
                } else {
                    VStack(spacing: 6) {
                        Text("Profil seçilmedi")
                            .font(.headline)
                        Text("Soldaki listeden bir profil seçin veya + ile yeni profil ekleyin.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            shells = ShellService.availableShells()
            fontFamilies = FontCatalog.availableMonospacedFamilies()
            if selection == nil {
                selection = profiles.profiles.first?.id
            }
        }
    }

    /// Kimlik üzerinden yazan binding: silme sonrası bayat indeks kullanılmaz.
    private var editorBinding: Binding<TerminalProfile>? {
        guard let id = selection, profiles.profiles.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { profiles.profiles.first { $0.id == id } ?? Self.placeholder },
            set: { newValue in
                guard let index = profiles.profiles.firstIndex(where: { $0.id == id }) else { return }
                profiles.profiles[index] = newValue
            }
        )
    }

    private func addProfile() {
        let profile = TerminalProfile(name: "Yeni Profil")
        profiles.profiles.append(profile)
        selection = profile.id
    }

    private func removeSelectedProfile() {
        guard let id = selection else { return }
        profiles.profiles.removeAll { $0.id == id }
        selection = profiles.profiles.first?.id
    }
}
