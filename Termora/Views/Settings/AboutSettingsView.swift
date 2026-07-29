import AppKit
import SwiftUI

/// Uygulamanın kendi künyesi. Info.plist'ten okunur — ikinci bir yerde sürüm tutmak,
/// bir gün ayrışan iki sürüm numarası demektir.
enum AppIdentity {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Termora"
    }
}

/// briefs/2 "Ayarlar Ekranı" ▸ About.
struct AboutSettingsView: View {

    var body: some View {
        Form {
            Section {
                LabeledContent("Version") {
                    Text("\(AppIdentity.version) (\(AppIdentity.build))")
                        .textSelection(.enabled)
                        .monospacedDigit()
                }
                LabeledContent("System") {
                    Text(ProcessInfo.processInfo.operatingSystemVersionString)
                        .textSelection(.enabled)
                }
            } header: {
                Text(AppIdentity.displayName)
            } footer: {
                // briefs/1 "Ürün Konumlandırması" — ürün vaadi.
                Text("A native terminal built for focused developers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Open the Repository") {
                    NSWorkspace.shared.open(TermoraLinks.repository)
                }
                Button("Report an Issue…") {
                    NSWorkspace.shared.open(TermoraLinks.newIssue)
                }
            } header: {
                Text("Links")
            }
        }
        .formStyle(.grouped)
    }
}

/// Updates sayfasının metinleri. Görünümden ayrı ki sayfanın İDDİALARI sınanabilsin:
/// ne gönderildiği, imzanın doğrulandığı ve yapının hazır olup olmadığı.
@MainActor
enum UpdatesContent {
    static let notConfiguredNote = """
        This build does not carry an update feed, so Termora does not check for updates \
        on its own and sends nothing anywhere. The button opens the releases page in your \
        browser.
        """

    static let privacyNote = """
        The check asks the update feed for the latest version number and nothing else. \
        Termora never sends your machine profile, your usage, or any identifier with it.
        """

    static let signatureNote = """
        Every update is verified against Termora's EdDSA signature before it is installed; \
        a package whose signature does not match is refused.
        """
}

/// briefs/2 "Ayarlar Ekranı" ▸ Updates.
///
/// Sayfa yapının HAZIR olup olmadığına göre iki farklı şey gösterir. Appcast adresi ve
/// açık anahtar yoksa Sparkle hiç başlatılmaz; o durumda "otomatik kontrol" anahtarı
/// çizmek, hiçbir şey yapmayan bir anahtar göstermek olurdu.
struct UpdatesSettingsView: View {

    /// Ayarlar; anahtar değiştiğinde Sparkle'a taşınır.
    let settings: SettingsStore
    var updater: AppUpdater = .shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Installed version") {
                    Text("\(AppIdentity.version) (\(AppIdentity.build))")
                        .monospacedDigit()
                }

                if updater.isReady {
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { settings.settings.checksForUpdatesAutomatically },
                        set: {
                            settings.settings.checksForUpdatesAutomatically = $0
                            updater.apply(settings.settings)
                        }
                    ))

                    Picker("Check", selection: Binding(
                        get: { settings.settings.updateCheckInterval },
                        set: {
                            settings.settings.updateCheckInterval = $0
                            updater.apply(settings.settings)
                        }
                    )) {
                        ForEach(UpdateCheckInterval.allCases) { interval in
                            Text(interval.title).tag(interval)
                        }
                    }
                    .disabled(!settings.settings.checksForUpdatesAutomatically)

                    // Elle kontrol otomatik ayardan BAĞIMSIZ: kullanıcı kapalı tutup yine
                    // de bugün bakmak isteyebilir. Sparkle'ın kendi penceresi "Skip This
                    // Version" ve "Remind Me Later" seçeneklerini burada sunar.
                    Button("Check Now…") { updater.checkForUpdates() }
                } else {
                    Button("Check Releases…") {
                        NSWorkspace.shared.open(TermoraLinks.releases)
                    }
                }
            } header: {
                Text("Updates")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if updater.isReady {
                        Text(UpdatesContent.privacyNote)
                        Text(UpdatesContent.signatureNote)
                    } else {
                        Text(UpdatesContent.notConfiguredNote)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}
