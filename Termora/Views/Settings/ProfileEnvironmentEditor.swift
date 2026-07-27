import SwiftUI

/// Profilin ek ortam değişkenlerini iki kolonlu satırlar hâlinde düzenler.
/// Üst görünüm bu editöre `.id(profile.id)` verir; profil değişince satırlar sıfırdan yüklenir.
struct ProfileEnvironmentEditor: View {
    @Binding var environment: [String: String]

    @State private var entries: [EnvironmentEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Anahtar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 150, alignment: .leading)
                Text("Değer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if entries.isEmpty {
                Text("Bu profil için ek ortam değişkeni yok.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach($entries) { $entry in
                HStack(spacing: 8) {
                    TextField("KEY", text: $entry.key)
                        .frame(width: 150)
                    TextField("value", text: $entry.value)
                    Button {
                        remove(id: entry.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Bu değişkeni sil")
                }
            }

            HStack {
                Button {
                    entries.append(EnvironmentEntry(key: "", value: ""))
                } label: {
                    Label("Değişken ekle", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Spacer()
            }

            Text("⚠️ Hassas değerleri (API anahtarı, parola) buraya koymayın — profiller UserDefaults'a düz metin olarak yazılır.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            entries = EnvironmentEditing.entries(from: environment)
        }
        .onChange(of: entries) { _, newValue in
            environment = EnvironmentEditing.dictionary(from: newValue)
        }
    }

    private func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }
}
