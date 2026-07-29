import SwiftUI

/// briefs/3 "Durum Tasarımları" ▸ Empty State.
///
/// Tek cümle, en fazla bir eylem, illüstrasyon yok. Ortak bir görünüm olmasının sebebi
/// tutarlılık değil dayanıklılık: her ekran kendi boş durumunu yazdığında biri er geç
/// eylemi unutur ya da iki cümle yazar.
struct EmptyStateView: View {
    let content: EmptyStateContent
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Text(content.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let title = content.actionTitle, let action {
                Button(title, action: action)
                if let shortcut = content.shortcut {
                    Text(shortcut)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// briefs/3 "Durum Tasarımları" ▸ Error State: dört soru, dört satır.
///
/// Renk TEK gösterge değil — simge, başlık ve gövde metinleri de var.
struct ErrorStateView: View {
    let content: ErrorStateContent
    var actionTitle: String?
    var action: (() -> Void)?

    @State private var showsDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(content.title, systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(DesignTokens.warning.color)

            Text(content.reason)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)

            Text(content.recovery)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.caption)
            }

            // Teknik detay KAPALI gelir: kullanıcının ilk gördüğü şey çözüm olmalı,
            // içeriği anlamadığı bir yığın değil.
            if let detail = content.technicalDetail {
                DisclosureGroup("Details", isExpanded: $showsDetail) {
                    Text(detail)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(content.title). \(content.reason) \(content.recovery)")
    }
}

/// briefs/3 "Durum Tasarımları" ▸ Loading State.
///
/// Gösterge GECİKMELİ çıkar: hızlı işlemde hiç görünmez ve ekran titremez. Uzun
/// skeleton animasyonu yok — brief bunu açıkça istemiyor.
struct DelayedLoadingView: View {
    let message: String

    @State private var isVisible = false

    var body: some View {
        Group {
            if isVisible {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            try? await Task.sleep(for: LoadingStateContent.delay)
            isVisible = true
        }
    }
}
