import SwiftUI

/// briefs/3 "Yeni Sekme Ekranı".
///
/// Terminalin YERİNE geçen bir sekme değil, ⌘T'nin önüne geçen bir seçim katmanı.
/// Sebep brief'in kendi cümlesi: *Bu ekran terminal kullanımını yavaşlatmamalı.* Sekme
/// olarak kurulsaydı, kullanıcı seçim yapana kadar boş bir terminal sekmesi açık kalır
/// ve kapatması gereken bir şey doğardı.
struct NewTabLauncherView: View {

    let availability: NewTabLauncherAvailability
    let onChoose: (NewTabLauncherOption) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Tab")
                .font(.title3.weight(.semibold))

            VStack(spacing: 4) {
                ForEach(NewTabLauncherOption.allCases) { option in
                    row(for: option)
                }
            }

            HStack {
                Text("Turn this screen off in Settings ▸ General.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func row(for option: NewTabLauncherOption) -> some View {
        let enabled = availability.isEnabled(option)
        return Button {
            onChoose(option)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: option.symbolName)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.title)
                    Text(enabled ? option.explanation : "Nothing saved yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("⌘\(option.shortcutDigit)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // briefs/3 "Klavye Öncelikli Kullanım": her seçenek rakamla da seçilebilir.
        .keyboardShortcut(KeyEquivalent(Character("\(option.shortcutDigit)")), modifiers: .command)
        // Kullanılamayan seçenek GİZLENMEZ, devre dışı görünür.
        .disabled(!enabled)
        .accessibilityLabel(enabled
                            ? "\(option.title). \(option.explanation)"
                            : "\(option.title). Unavailable: nothing saved yet.")
    }
}
