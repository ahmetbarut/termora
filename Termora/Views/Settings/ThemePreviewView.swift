import AppKit
import SwiftUI

/// Seçili temanın arka plan/metin renklerini, 16 ANSI rengini ve ÖLÇÜLEN kontrastını gösterir.
struct ThemePreviewView: View {
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            preview
            contrastLine
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("user@termora ~ % ls -la")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(nsColor: theme.foregroundNSColor))

            HStack(spacing: 4) {
                ForEach(0..<8) { index in
                    swatch(at: index)
                }
            }
            HStack(spacing: 4) {
                ForEach(8..<16) { index in
                    swatch(at: index)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: theme.backgroundNSColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
        // 16 renk kutusu tek tek gezilecek bir şey değil; önizleme tek bir öğe olarak
        // duyurulur, yoksa VoiceOver kullanıcısı 17 anlamsız durakta takılır.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the \(theme.name) theme")
    }

    /// brief 3 "Erişilebilirlik → Kontrast oranı korunmalı" ve "Sadece renkle durum
    /// anlatılmamalı". Rapor kasten önizleme KUTUSUNUN DIŞINDA, pencerenin kendi
    /// renkleriyle çizilir: düşük kontrastlı bir temanın üstüne yazılsaydı okunabilirlik
    /// uyarısının kendisi okunmazdı.
    private var contrastLine: some View {
        let report = theme.contrastReport
        let passes = report.meetsNormalText && report.everyAnsiColorMeetsNormalText
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: passes ? "checkmark.circle" : "exclamationmark.triangle.fill")
                .foregroundStyle(passes ? Color.secondary : DesignTokens.warning.color)
            Text(report.summary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        // İkon ve metin tek cümle olarak duyurulur; seviye ("AAA", "Below AA") metnin
        // içinde geçtiği için durum yalnız renkten okunmuyor.
        .accessibilityElement(children: .combine)
    }

    private func swatch(at index: Int) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color(at: index))
            .frame(width: 18, height: 18)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color(nsColor: theme.foregroundNSColor).opacity(0.15))
            )
    }

    private func color(at index: Int) -> Color {
        guard theme.ansi.indices.contains(index),
              let nsColor = NSColor(hexString: theme.ansi[index]) else {
            return Color(nsColor: .systemGray)
        }
        return Color(nsColor: nsColor)
    }
}
