import AppKit
import SwiftUI

/// Ekran 2'nin terminal önizlemesi: seçilen tema ve fontla boyanmış temsili çıktı.
/// Gerçek bir shell başlatılmaz (bkz. `OnboardingPreview`).
struct OnboardingTerminalPreview: View {
    let theme: Theme
    let fontName: String?
    let fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(OnboardingPreview.lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    text(for: line)
                    if line.id == OnboardingPreview.lines.last?.id {
                        cursorBlock
                    }
                }
            }
        }
        .font(previewFont)
        .textSelection(.disabled)
        .padding(12)
        // Kalan dikey alanı doldurur: önizleme gerçek bir terminal paneli gibi durur,
        // kontrollerin altında boşluk kalmaz.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: theme.backgroundNSColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
        // Süslü çıktı VoiceOver'da satır satır okunmamalı; tek bir açıklama yeter.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Terminal preview using the selected theme and font")
    }

    private var rowSpacing: CGFloat {
        CGFloat(SettingsLimits.clampFontSize(fontSize)) * 0.35
    }

    private var previewFont: Font {
        Font(FontCatalog.resolvedFont(name: fontName, size: fontSize) as CTFont)
    }

    private func text(for line: OnboardingPreview.Line) -> Text {
        line.segments.reduce(Text(verbatim: "")) { partial, segment in
            partial + Text(verbatim: segment.text).foregroundColor(color(for: segment.ink))
        }
    }

    /// Yanıp sönmez: brief 3 "Animasyonlar" terminal cursor'ına dekoratif hareket yasaklar.
    private var cursorBlock: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color(nsColor: theme.cursorNSColor))
            .frame(width: CGFloat(SettingsLimits.clampFontSize(fontSize)) * 0.55,
                   height: CGFloat(SettingsLimits.clampFontSize(fontSize)) * 1.1)
    }

    private func color(for ink: OnboardingPreview.Ink) -> Color {
        switch ink {
        case .foreground:
            return Color(nsColor: theme.foregroundNSColor)
        case .ansi(let index):
            guard theme.ansi.indices.contains(index),
                  let nsColor = NSColor(hexString: theme.ansi[index]) else {
                return Color(nsColor: theme.foregroundNSColor)
            }
            return Color(nsColor: nsColor)
        }
    }
}
