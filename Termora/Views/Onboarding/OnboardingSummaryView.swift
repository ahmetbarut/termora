import AppKit
import SwiftUI

/// Ekran 3.
///
/// Brief bu ekranda üç isteğe bağlı özellik listeler (Open in Finder, Shell Integration,
/// Restore Previous Sessions). Üçü de bugün uygulamada YOK; hiçbir şey yapmayan anahtar
/// koymak kullanıcıyı yanıltır. Bu yüzden ekran, yapılan seçimleri özetleyip gerçekten
/// çalışan kısayolları gösterir ve "Open Termora" ile kapanır.
struct OnboardingSummaryView: View {
    let state: OnboardingState
    let themes: ThemeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("You're set")
                .font(.system(size: 17, weight: .semibold))

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                summaryRow("Shell", value: shellSummary)
                summaryRow("Font", value: fontSummary)
                summaryRow("Theme", value: themes.theme(id: state.selections.themeID).name)
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
