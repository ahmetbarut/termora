import SwiftUI

/// Lisans sayfasının metinleri. Görünümden ayrı tutulur ki sınanabilsin — sayfanın
/// vaadi (abonelik yok, çevrimdışı çalışır) bir testin konusu olabilsin diye.
@MainActor
enum LicenseContent {
    static let freeFeatures = ProFeature.allCases.filter(\.isFreeTier)
    static let proFeatures = ProFeature.allCases.filter { !$0.isFreeTier }

    static let summary = """
        Termora is free to use as a terminal. Pro is a one-time purchase that unlocks \
        the workspace, SSH, AI and Docker tools.
        """

    static let offlineNote = """
        Your license is verified offline and stored in the macOS Keychain. Termora never \
        contacts a server to check it, so Pro keeps working without a network.
        """

    /// Lisanslama kurulmamış yapıda sayfanın söylediği şey.
    ///
    /// Bu ekranın değeri DÜRÜSTLÜĞÜNDE (aynı kural gizlilik sayfasında da geçerli):
    /// hiçbir şeyin kilitli olmadığı bir yapıda "Free" deyip yanına kilitler çizmek,
    /// kullanıcıya olmayan bir sınırı varmış gibi gösterirdi.
    static let unlicensedBuildNote = """
        This build does not carry a license key, so nothing is locked — every feature \
        listed below is available.
        """
}

/// briefs/2 "Lisanslama ve Planlar".
///
/// Sayfanın kuralı: kilitli özellik GİZLENMEZ, anlatılır. Kullanıcı neyi kaçırdığını
/// göremezse satın alma kararını veremez — ve gizlenen özellik, olmayan özellikten
/// ayırt edilemez.
struct LicenseSettingsView: View {
    let license: LicenseStore

    @State private var keyText = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                statusRow
            } footer: {
                Text(license.isLicensingConfigured
                     ? LicenseContent.summary
                     : LicenseContent.unlicensedBuildNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !license.isLicensingConfigured {
                // Etkinleştirme alanı çizilmez: doğrulanamayacak bir anahtarı istemek,
                // kullanıcıyı çalışmayacak bir işe davet etmek olurdu.
                EmptyView()
            } else if license.state == .pro {
                Section {
                    Button("Remove License", role: .destructive) {
                        errorMessage = nil
                        do { try license.deactivate() } catch {
                            errorMessage = "The license could not be removed from the Keychain."
                        }
                    }
                } footer: {
                    Text(LicenseContent.offlineNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    // `TextField` bilerek: lisans anahtarı bir parola değil, kullanıcı
                    // yapıştırdığını görebilmeli — gizlenen alan yanlış yapıştırmayı
                    // görünmez bir hataya çevirir.
                    TextField("TERMORA-…", text: $keyText, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit(activate)

                    HStack {
                        Button("Activate", action: activate)
                            .disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.warning.color)
                        }
                    }
                } header: {
                    Text("Activate")
                } footer: {
                    Text(LicenseContent.offlineNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Free") {
                ForEach(LicenseContent.freeFeatures) { feature in
                    Label(feature.title, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(DesignTokens.success.color)
                }
            }

            Section("Pro") {
                ForEach(LicenseContent.proFeatures) { feature in
                    FeatureRow(feature: feature,
                               isUnlocked: !license.isLicensingConfigured || license.allows(feature))
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var statusRow: some View {
        if let installed = license.license {
            LabeledContent("Plan") {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Pro").fontWeight(.medium)
                    Text(installed.licensee)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let expiresAt = installed.expiresAt {
                        Text("Updates until \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityLabel("Plan: Pro, licensed to \(installed.licensee)")
        } else if license.isLicensingConfigured {
            LabeledContent("Plan", value: "Free")
                .accessibilityLabel("Plan: Free")
        } else {
            LabeledContent("Plan", value: "All features")
                .accessibilityLabel("Plan: all features available")
        }
    }

    private func activate() {
        errorMessage = nil
        do {
            try license.activate(keyText)
            keyText = ""
        } catch LicenseStore.Failure.invalidKey {
            errorMessage = "That key is not valid for this version."
        } catch {
            errorMessage = "The license could not be saved to the Keychain."
        }
    }
}

/// Tek bir Pro özelliği. Kilitliyken satır SOLMAZ — okunabilir kalır ve altında ne işe
/// yaradığı yazar; sadece başındaki simge kilide döner.
private struct FeatureRow: View {
    let feature: ProFeature
    let isUnlocked: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: isUnlocked ? "checkmark.circle.fill" : "lock.fill")
                .foregroundStyle(isUnlocked ? DesignTokens.success.color : Color.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                Text(feature.lockedExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Durum ÜÇ kanaldan: simge, renk ve sesli okunan kelime.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(feature.title), \(isUnlocked ? "included" : "locked"). \(feature.lockedExplanation)")
    }
}
