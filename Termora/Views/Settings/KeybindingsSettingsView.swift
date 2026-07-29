import AppKit
import SwiftUI

/// briefs/2 "Ayarlar Ekranı" ▸ Keybindings.
///
/// briefs/2 ayrıca *klavye kısayolları çakıştığında kullanıcı uyarılmalıdır* diyor. Uyarı
/// ancak değiştirme mümkünse anlamlıdır — katalog sabitken çakışmayı zaten bir test
/// engelliyor. Bu yüzden ekran hem gösterir hem değiştirir.
struct KeybindingsSettingsView: View {

    let settings: SettingsStore

    /// Şu an tuş bekleyen komut; nil ise kayıt kapalı.
    @State private var recordingID: String?
    @State private var monitor: Any?
    @State private var query = ""

    private var shortcuts: [AppShortcut] {
        AppShortcuts.resolved(customStrokes: settings.settings.customShortcutStrokes)
    }

    /// Çakışan komutların kimlikleri. Satır kendi rengini buradan alır.
    private var conflictingIDs: Set<String> {
        Set(AppShortcuts.conflicts(in: shortcuts).flatMap { $0.map(\.id) })
    }

    private var visibleShortcuts: [AppShortcut] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return shortcuts }
        return shortcuts.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !conflictingIDs.isEmpty {
                conflictBanner
            }
            List {
                ForEach(visibleShortcuts) { shortcut in
                    row(for: shortcut)
                }
            }
            .searchable(text: $query, prompt: "Filter commands")
        }
        .onDisappear(perform: stopRecording)
    }

    /// briefs/3 "Error State": ne oldu, neden önemli, kullanıcı ne yapabilir.
    private var conflictBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignTokens.warning.color)
            VStack(alignment: .leading, spacing: 2) {
                Text("Two commands share a shortcut")
                    .font(.callout.weight(.semibold))
                Text("macOS gives the keystroke to one of them and the other never runs. "
                     + "Change one, or reset it to its default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(10)
        .background(DesignTokens.warning.color.opacity(0.12))
    }

    private func row(for shortcut: AppShortcut) -> some View {
        HStack {
            Text(shortcut.title)
                .foregroundStyle(conflictingIDs.contains(shortcut.id) ? DesignTokens.warning.color : .primary)
            Spacer()

            if recordingID == shortcut.id {
                Text("Press a key…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Cancel", action: stopRecording)
            } else {
                Text(KeyboardShortcutText.display(shortcut))
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                Button("Change") { startRecording(shortcut.id) }
            }

            if settings.settings.customShortcutStrokes[shortcut.id] != nil {
                Button("Reset") { reset(shortcut.id) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: shortcut))
    }

    private func accessibilityLabel(for shortcut: AppShortcut) -> String {
        var parts = [shortcut.title, KeyboardShortcutText.spoken(shortcut)]
        // Çakışma yalnız renkle anlatılmaz (briefs/3 "Erişilebilirlik").
        if conflictingIDs.contains(shortcut.id) { parts.append("Conflicts with another command") }
        return parts.joined(separator: ". ")
    }

    // MARK: - Tuş kaydı

    private func startRecording(_ id: String) {
        stopRecording()
        recordingID = id
        // Yerel monitör: kayıt sırasında tuş uygulamanın kendi menülerine GİTMEMELİ,
        // yoksa ⌘W ayarlar penceresini kapatırdı.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            capture(event)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recordingID = nil
    }

    private func capture(_ event: NSEvent) {
        defer { stopRecording() }
        guard let id = recordingID else { return }
        // Escape kaydı iptal eder; kısayol olarak atanamaz çünkü paletin ve arama
        // çubuğunun kaçış tuşudur.
        guard event.keyCode != 53 else { return }
        guard let stroke = KeyboardShortcutText.stroke(from: event) else { return }
        settings.settings.customShortcutStrokes[id] = stroke
    }

    private func reset(_ id: String) {
        settings.settings.customShortcutStrokes.removeValue(forKey: id)
    }
}
