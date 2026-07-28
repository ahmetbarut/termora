import SwiftUI

/// Profilin ek ortam değişkenlerini iki kolonlu satırlar hâlinde düzenler.
/// Üst görünüm bu editöre `.id(profile.id)` verir; profil değişince satırlar sıfırdan yüklenir.
struct ProfileEnvironmentEditor: View {
    @Binding var environment: [String: String]

    @State private var entries: [EnvironmentEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 150, alignment: .leading)
                Text("Value")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if entries.isEmpty {
                Text("No extra environment variables for this profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach($entries) { $entry in
                // Satır başına bir "eksi" düğmesi var; etiket hangi değişkeni sildiğini
                // söylemezse VoiceOver kullanıcısı için hepsi aynı düğmedir.
                let named = entry.key.isEmpty ? "the empty row" : entry.key

                HStack(spacing: 8) {
                    TextField("KEY", text: $entry.key)
                        .frame(width: 150)
                        .accessibilityLabel("Variable name")
                    TextField("value", text: $entry.value)
                        .accessibilityLabel("Value of \(named)")
                    Button {
                        remove(id: entry.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this variable")
                    .accessibilityLabel("Remove \(named)")
                }
            }

            HStack {
                Button {
                    entries.append(EnvironmentEntry(key: "", value: ""))
                } label: {
                    Label("Add Variable", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Spacer()
            }

            Label(
                "Do not store secrets (API keys, passwords) here — profiles are written to UserDefaults in plain text.",
                systemImage: "exclamationmark.triangle"
            )
                .font(.caption)
                .foregroundStyle(DesignTokens.warning.color)
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
