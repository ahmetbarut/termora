import AppKit
import SwiftUI

/// SwiftUI hiyerarşisinden barındıran `NSWindow`'u yakalar.
/// macOS 14'te `containerBackground(.window)` yok; pencere saydamlığı bu yolla ayarlanır.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> CatchingView {
        let view = CatchingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: CatchingView, context: Context) {
        nsView.onWindow = onWindow
        if let window = nsView.window {
            onWindow(window)
        }
    }

    final class CatchingView: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window = self.window {
                onWindow?(window)
            }
        }
    }
}

/// Pencere arkasını bulanıklaştıran `NSVisualEffectView` sarmalayıcısı.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

private struct WindowChromeModifier: ViewModifier {
    let opacity: Double
    let backgroundColor: NSColor

    private var isTranslucent: Bool { opacity < 0.999 }

    func body(content: Content) -> some View {
        content
            .background {
                if isTranslucent {
                    VisualEffectBackground().ignoresSafeArea()
                } else {
                    Color(nsColor: backgroundColor).ignoresSafeArea()
                }
            }
            .background(
                WindowAccessor { window in
                    window.isOpaque = !isTranslucent
                    window.backgroundColor = isTranslucent ? .clear : backgroundColor
                }
            )
    }
}

private struct TerminalAppearanceSyncModifier: ViewModifier {
    let settings: SettingsStore
    let sessionManager: SessionManager

    func body(content: Content) -> some View {
        content.onChange(of: settings.settings) { _, _ in
            sessionManager.applyAppearanceToAllSessions()
        }
    }
}

extension View {
    /// Pencere saydamlığını ve arka planını `AppSettings.windowOpacity` + tema rengine göre kurar.
    func termoraWindowChrome(opacity: Double, backgroundColor: NSColor) -> some View {
        modifier(WindowChromeModifier(opacity: opacity, backgroundColor: backgroundColor))
    }

    /// Ayarlar değiştiğinde açık tüm terminallere görünümü yeniden uygular (tek yönlü akış).
    func syncingTerminalAppearance(settings: SettingsStore, sessionManager: SessionManager) -> some View {
        modifier(TerminalAppearanceSyncModifier(settings: settings, sessionManager: sessionManager))
    }
}
