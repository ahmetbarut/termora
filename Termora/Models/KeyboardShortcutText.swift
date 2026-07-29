import AppKit
import SwiftUI

/// Klavye kısayollarının okunabilir ve duyulabilir karşılıkları.
///
/// Ayrı ve saf bir tip: `⌘⇧K` gibi bir dize ekranda doğru görünse bile VoiceOver'da
/// "command shift K" diye duyulmalı — sembol dizisini sesli okutmak kullanıcıya
/// anlamsız bir tıkırtı dizisi dinletirdi.
enum KeyboardShortcutText {

    /// Ekranda görünen biçim: macOS'un menülerde kullandığı sembol sırası.
    static func display(_ shortcut: AppShortcut) -> String {
        symbols(shortcut.modifiers) + displayCharacter(shortcut.key.character)
    }

    /// VoiceOver'ın okuyacağı biçim.
    static func spoken(_ shortcut: AppShortcut) -> String {
        var parts: [String] = []
        if shortcut.modifiers.contains(.control) { parts.append("Control") }
        if shortcut.modifiers.contains(.option) { parts.append("Option") }
        if shortcut.modifiers.contains(.shift) { parts.append("Shift") }
        if shortcut.modifiers.contains(.command) { parts.append("Command") }
        parts.append(spokenCharacter(shortcut.key.character))
        return parts.joined(separator: " ")
    }

    /// macOS'un menü sırası: ⌃ ⌥ ⇧ ⌘. Başka bir sıra, sistemin her yerinde aynı görünen
    /// bir gösterimi Termora'da farklı kılardı.
    private static func symbols(_ modifiers: EventModifiers) -> String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text
    }

    /// Ok tuşları ve boşluk gibi görünmez tuşlar sembolleriyle yazılır; harfler büyür.
    private static func displayCharacter(_ character: Character) -> String {
        switch character {
        case KeyEquivalent.leftArrow.character: "←"
        case KeyEquivalent.rightArrow.character: "→"
        case KeyEquivalent.upArrow.character: "↑"
        case KeyEquivalent.downArrow.character: "↓"
        case KeyEquivalent.space.character: "Space"
        case KeyEquivalent.return.character: "↩"
        case KeyEquivalent.tab.character: "⇥"
        case KeyEquivalent.delete.character: "⌫"
        default: String(character).uppercased()
        }
    }

    private static func spokenCharacter(_ character: Character) -> String {
        switch character {
        case KeyEquivalent.leftArrow.character: "Left Arrow"
        case KeyEquivalent.rightArrow.character: "Right Arrow"
        case KeyEquivalent.upArrow.character: "Up Arrow"
        case KeyEquivalent.downArrow.character: "Down Arrow"
        case KeyEquivalent.space.character: "Space"
        case KeyEquivalent.return.character: "Return"
        case KeyEquivalent.tab.character: "Tab"
        case KeyEquivalent.delete.character: "Delete"
        default: String(character).uppercased()
        }
    }

    /// Bir tuş olayını `AppShortcut.stroke` biçimine çevirir.
    ///
    /// Değiştirici İSTENİR: değiştiricisiz bir kısayol (`a`) terminalde harf yazmayı
    /// imkânsız kılardı. Değiştiricisiz olay `nil` döner ve kayıt sessizce iptal olur.
    static func stroke(from event: NSEvent) -> String? {
        var modifiers: EventModifiers = []
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        guard !modifiers.isEmpty else { return nil }

        // `charactersIgnoringModifiers` shift'siz temel karakteri verir: ⌘⇧K'nin
        // karakteri "k" olmalı, "K" değil — katalog da küçük harf tutuyor.
        guard let raw = event.charactersIgnoringModifiers?.lowercased(),
              let character = raw.first, raw.count == 1
        else { return nil }

        return AppShortcut(id: "", title: "",
                           key: KeyEquivalent(character), modifiers: modifiers).stroke
    }
}
