import AppKit
import SwiftUI

/// Ekran 3 — "İsteğe Bağlı Özellikler" (briefs/2).
///
/// Brief burada üç şey sayıyor: Shell integration kurulumu, Finder entegrasyonu ve AI
/// sağlayıcısı bağlantısı. Bugünkü gerçek:
/// - **AI sağlayıcısı:** VAR. Aşağıda bir durum satırı olarak gösteriliyor; kurulum
///   ZORUNLU değildir (briefs/3), bu yüzden ekran hiçbir cevabı beklemez.
/// - **Finder entegrasyonu:** VAR ama bir anahtarı yok — `termora://` şeması ve Finder ▸
///   Services girdisi uygulama paketinin parçası, kullanıcı açıp kapatamaz. Kapatılamayan
///   bir şey için anahtar koymak yalan olurdu.
/// - **Shell integration:** VAR. Kurulum kullanıcının rc dosyasına yazdığı için burada
///   yalnız NE OLDUĞU anlatılır ve Ayarlar'a yönlendirilir; onboarding hiçbir dotfile'a
///   dokunmaz. İlk açılışta "Open Termora"ya basmak isteyen kullanıcıya yazma onayı
///   sordurmak, brief'in "kullanıcı onboarding'i atlayabilmelidir" kuralına aykırıdır.
///
/// Geri kalanı yapılan seçimleri özetler, gerçekten çalışan kısayolları gösterir ve
/// "Open Termora" ile kapanır.
struct OnboardingSummaryView: View {
    let state: OnboardingState
    let themes: ThemeStore
    /// AI durumu. Nil ise satır hiç çizilmez — AI'ı hiç kurmamış bir bağlamda (testler,
    /// önizleme) "bulunamadı" demek yanlış olurdu; bilinmiyor demek doğrusu.
    var aiCatalog: AIModelCatalog? = AIModelCatalog.current

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("You're set")
                .font(.system(size: 17, weight: .semibold))

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                summaryRow("Shell", value: shellSummary)
                summaryRow("Font", value: fontSummary)
                summaryRow("Theme", value: themes.theme(id: state.selections.themeID).name)
            }

            if let family = ShellFamily(shellPath: state.selections.shellPath) {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text(ShellIntegrationContent.title)
                        .font(.system(size: 13, weight: .medium))
                    Text(ShellIntegrationContent.explanation(for: family))
                        .font(.system(size: 12))
                    Text("Turn it on in Settings ▸ General whenever you want.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }

            if let aiCatalog {
                Divider()
                aiRow(aiCatalog)
            }

            Divider()

            Text("Shortcuts to start with")
                .font(.system(size: 13, weight: .medium))

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                shortcutRow("⌘T", action: "New tab")
                shortcutRow("⌘D", action: "Split vertically")
                shortcutRow("⌘F", action: "Find in terminal")
                shortcutRow("⌘,", action: "Settings")
            }

            Spacer(minLength: 0)

            Text("Every choice here can be changed later in Settings.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
    }

    /// Durum satırı. Sunucuya sorulur ama CEVABI BEKLENMEZ: `.task` arka planda çalışır,
    /// "Open Termora" düğmesi hiçbir an devre dışı kalmaz (briefs/3: AI kurulumu ilk açılış
    /// için zorunlu değildir).
    private func aiRow(_ catalog: AIModelCatalog) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(OnboardingAIContent.title)
                .font(.system(size: 13, weight: .medium))
            Text(OnboardingAIContent.summary(for: catalog.availability,
                                             providerName: catalog.providerName))
                .font(.system(size: 12))
            Text(OnboardingAIContent.optionalNote)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .task {
            // Yalnız hiç sorulmadıysa sorulur; ekrana her dönüşte yeni bir istek açmaz.
            if catalog.availability == .idle { await catalog.refresh() }
        }
    }

    private var shellSummary: String {
        let path = state.selections.shellPath
        let name = (path as NSString).lastPathComponent
        return "\(name) — \(path)"
    }

    private var fontSummary: String {
        let family = state.selections.fontName ?? "System Monospace"
        return "\(family), \(Int(state.selections.fontSize)) pt"
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .gridColumnAlignment(.trailing)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
    }

    private func shortcutRow(_ keys: String, action: String) -> some View {
        GridRow {
            Text(keys)
                .gridColumnAlignment(.trailing)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(action)
                .font(.system(size: 12))
        }
        .accessibilityElement(children: .combine)
    }
}
