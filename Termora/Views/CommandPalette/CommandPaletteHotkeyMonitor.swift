import AppKit

/// ⌘⇧P kısayolunu pencere düzeyinde yakalar.
///
/// Palet iki kısayolla açılır (brief 3): ⌘K menü öğesinden gelir, ama bir menü öğesine
/// İKİNCİ bir kısayol bağlanamaz. Menüye ikinci kez "Command Palette" yazmak yerine
/// alternatif kısayol yerel bir olay dinleyicisiyle karşılanır. Dinleyici yalnız KENDİ
/// penceresine giden olaylara bakar; birden çok pencere açıkken paletler karışmaz.
@MainActor
final class CommandPaletteHotkeyMonitor {
    private var monitor: Any?
    private weak var window: NSWindow?
    private var onTrigger: (@MainActor () -> Void)?

    /// Pencere her yerleşimde yeniden bildirilebilir; dinleyici yalnız bir kez kurulur.
    func attach(window: NSWindow, onTrigger: @escaping @MainActor () -> Void) {
        self.window = window
        self.onTrigger = onTrigger
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.handles(event) else { return event }
            self.onTrigger?()
            return nil
        }
    }

    func detach() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        onTrigger = nil
        window = nil
    }

    private func handles(_ event: NSEvent) -> Bool {
        guard let window, event.window === window else { return false }
        return CommandPaletteHotkey.isAlternateShortcut(
            characters: event.charactersIgnoringModifiers,
            modifiers: event.modifierFlags)
    }
}
