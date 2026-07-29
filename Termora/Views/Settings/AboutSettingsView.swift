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

/// briefs/2 "Ayarlar Ekranı" ▸ Updates.
///
/// İmzalı otomatik güncelleme (Sparkle) ayrı bir iştir. Bu sayfa o gelene kadar
/// DÜRÜST davranır: ne yaptığını ve ne YAPMADIĞINI söyler, sürümü gösterir ve
/// yayınlar sayfasına götürür. Boş ya da yalan bir sayfa göstermek — "güncel"
/// yazan ama hiçbir şey kontrol etmeyen bir satır — daha kötü olurdu.
struct UpdatesSettingsView: View {

    var body: some View {
        Form {
            Section {
                LabeledContent("Installed version") {
                    Text("\(AppIdentity.version) (\(AppIdentity.build))")
                        .monospacedDigit()
                }
                Button("Check Releases…") {
                    NSWorkspace.shared.open(TermoraLinks.releases)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Termora does not check for updates on its own yet, and it sends nothing "
                     + "anywhere to find out. The button opens the releases page in your browser.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}
