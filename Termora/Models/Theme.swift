import AppKit
import Foundation
import SwiftTerm

struct Theme: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var background: String
    var foreground: String
    var cursor: String
    var selection: String
    var ansi: [String] // exactly 16 hex strings, ANSI colors 0-15
}

extension Theme {
    func swiftTermAnsiColors() -> [SwiftTerm.Color] {
        ansi.map { Self.swiftTermColor(fromHex: $0) }
    }

    var backgroundNSColor: NSColor { NSColor(hexString: background) ?? .black }
    var foregroundNSColor: NSColor { NSColor(hexString: foreground) ?? .white }
    var cursorNSColor: NSColor { NSColor(hexString: cursor) ?? .white }
    /// Applied to the terminal in Task 19's `applyAppearance(to:sessionID:)`.
    var selectionNSColor: NSColor { NSColor(hexString: selection) ?? .selectedTextBackgroundColor }

    /// Scales 8-bit hex channels to SwiftTerm's 16-bit channels (0xFF -> 65535, since 255 * 257 == 65535).
    private static func swiftTermColor(fromHex hex: String) -> SwiftTerm.Color {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") {
            text.removeFirst()
        }
        guard text.count == 6 || text.count == 8,
              text.allSatisfy(\.isHexDigit),
              let value = UInt64(text, radix: 16) else {
            return SwiftTerm.Color(red: 0, green: 0, blue: 0)
        }
        let rgb = text.count == 8 ? value >> 8 : value
        return SwiftTerm.Color(
            red: UInt16((rgb >> 16) & 0xFF) * 257,
            green: UInt16((rgb >> 8) & 0xFF) * 257,
            blue: UInt16(rgb & 0xFF) * 257)
    }
}
