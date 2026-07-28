import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppearanceSettingsView: View {
    @Bindable var settings: SettingsStore
    let themes: ThemeStore

    @State private var fontMenu = FontCatalog.FontMenu(recommended: [], others: [])
    /// Son içe/dışa aktarmanın sonucu. Hata SESSİZCE yutulmaz: ya bu cümle ya da
    /// aşağıdaki hata kutusu görünür (brief 3 "Error State").
    @State private var themeStatus: String?
    @State private var themeError: ThemeFileError?
    @State private var showsTechnicalDetail = false
    @State private var isConfirmingThemeRemoval = false

    private var selectedTheme: Theme { themes.theme(id: settings.settings.themeID) }
    private var canRemoveSelectedTheme: Bool { !themes.isBuiltIn(id: selectedTheme.id) }

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Theme", selection: $settings.settings.themeID) {
                    // Paket temaları salt okunurdur, kullanıcı temaları silinebilir;
                    // ayrı gruplar hangi temanın hangisi olduğunu seçmeden önce söyler.
                    ForEach(themes.builtInThemes) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                    if !themes.userThemes.isEmpty {
                        Divider()
                        ForEach(themes.userThemes) { theme in
                            Text(theme.name).tag(theme.id)
                        }
                    }
                }
                ThemePreviewView(theme: selectedTheme)

                HStack(spacing: 8) {
                    Button("Import Theme…") { importTheme() }
                        .accessibilityLabel("Import Theme From File")
                    Button("Export Theme…") { exportTheme() }
                        .accessibilityLabel("Export Selected Theme To File")
                    Spacer()
                    Button("Remove Theme…", role: .destructive) { isConfirmingThemeRemoval = true }
                        .accessibilityLabel("Remove Selected Theme")
                        .disabled(!canRemoveSelectedTheme)
                }
                .confirmationDialog("Remove the theme “\(selectedTheme.name)”?",
                                    isPresented: $isConfirmingThemeRemoval) {
                    Button("Remove Theme", role: .destructive) { removeSelectedTheme() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Its file is deleted from your theme library. Built-in themes are not affected.")
                }

                if let themeStatus {
                    Label(themeStatus, systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                }

                if let themeError {
                    themeErrorBox(themeError)
                }
            }

            Section("Font") {
                Picker("Family", selection: $settings.settings.fontName) {
                    // brief 3 "Alternatif fontlar": önerilenler üstte, kurulu olmayanlar hiç yok.
                    ForEach(fontMenu.recommended, id: \.self) { family in
                        Text(family).tag(family as String?)
                    }
                    if !fontMenu.others.isEmpty {
                        Divider()
                        ForEach(fontMenu.others, id: \.self) { family in
                            Text(family).tag(family as String?)
                        }
                    }
                    Divider()
                    Text("System Monospace").tag(nil as String?)
                }

                Stepper(value: fontSizeBinding, in: SettingsLimits.fontSizeRange, step: 1) {
                    Text("Size: \(Int(settings.settings.fontSize)) pt")
                }

                VStack(alignment: .leading, spacing: 2) {
                    // Değer ayrı bir `Text`'te gösteriliyor; ekran okuyucu onu kaydırıcıya
                    // bağlayamadığı için değer açıkça bildirilir.
                    Slider(value: lineSpacingBinding, in: SettingsLimits.lineSpacingRange, step: 0.05) {
                        Text("Line height")
                    }
                    .accessibilityValue(String(format: "%.2f times", settings.settings.lineSpacing))

                    Text(String(format: "%.2f×", settings.settings.lineSpacing))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }

            Section("Cursor & Window") {
                Picker("Cursor shape", selection: $settings.settings.cursorStyle) {
                    ForEach(CursorStyleSetting.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Slider(value: opacityBinding, in: SettingsLimits.opacityRange, step: 0.05) {
                        Text("Window opacity")
                    }
                    .accessibilityValue(
                        "\(Int((settings.settings.windowOpacity * 100).rounded())) percent opaque")

                    Text("\(Int((settings.settings.windowOpacity * 100).rounded()))% opaque")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            fontMenu = FontCatalog.availableFontMenu()
        }
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { settings.settings.fontSize },
            set: { settings.settings.fontSize = SettingsLimits.clampFontSize($0) }
        )
    }

    private var lineSpacingBinding: Binding<Double> {
        Binding(
            get: { settings.settings.lineSpacing },
            set: { settings.settings.lineSpacing = SettingsLimits.clampLineSpacing($0) }
        )
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { settings.settings.windowOpacity },
            set: { settings.settings.windowOpacity = SettingsLimits.clampOpacity($0) }
        )
    }

    // MARK: - Tema dosyaları

    /// brief 3 "Error State": ne başarısız oldu (başlık), muhtemel sebep (açıklama),
    /// kullanıcı ne yapabilir (öneri) ve teknik detay nasıl görüntülenir (açılır bölüm).
    private func themeErrorBox(_ error: ThemeFileError) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Durum yalnız renkle anlatılmıyor: ikonun yanında başlık metni de var.
            Label(error.title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(DesignTokens.danger.color)

            Text(error.message)
                .fixedSize(horizontal: false, vertical: true)

            Text(error.recovery)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup("Technical details", isExpanded: $showsTechnicalDetail) {
                Text(error.technicalDetail)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption)

            HStack {
                Spacer()
                Button("Dismiss") { themeError = nil }
            }
        }
        .font(.callout)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(DesignTokens.danger.color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(DesignTokens.danger.color.opacity(0.45))
        )
    }

    private func importTheme() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.prompt = "Import"
        panel.message = "Choose a Termora theme file."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        themeStatus = nil
        themeError = nil
        showsTechnicalDetail = false
        do {
            let result = try themes.importTheme(from: url)
            // Kullanıcı temayı görsün diye seçili hâle getirilir; aksi hâlde başarı cümlesi
            // dışında hiçbir şey değişmezdi.
            settings.settings.themeID = result.theme.id
            themeStatus = result.statusMessage
        } catch let error as ThemeFileError {
            themeError = error
        } catch {
            themeError = ThemeFileError(reason: .unreadableFile(error.localizedDescription),
                                        fileName: url.lastPathComponent)
        }
    }

    private func exportTheme() {
        let theme = selectedTheme
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = ThemeFile.suggestedFileName(for: theme)
        panel.prompt = "Export"
        panel.message = "Save “\(theme.name)” as a theme file."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        themeStatus = nil
        themeError = nil
        showsTechnicalDetail = false
        do {
            try themes.exportTheme(theme, to: url)
            themeStatus = "Exported “\(theme.name)” to \(url.lastPathComponent)."
        } catch let error as ThemeFileError {
            themeError = error
        } catch {
            themeError = ThemeFileError(reason: .couldNotSave(error.localizedDescription),
                                        fileName: url.lastPathComponent)
        }
    }

    private func removeSelectedTheme() {
        let theme = selectedTheme
        guard !themes.isBuiltIn(id: theme.id) else { return }
        themes.removeUserTheme(id: theme.id)
        themeError = nil
        // Seçim silinen temada kalırsa Picker boş görünürdü.
        settings.settings.themeID = ThemeStore.fallback.id
        themeStatus = "Removed “\(theme.name)”."
    }
}
