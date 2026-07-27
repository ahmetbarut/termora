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

/// brief 3 "Tema Sistemi" tema başına 8 temel ANSI rengi tanımlar, terminal modeli ise
/// 16 renk ister (0-7 normal, 8-15 parlak). Parlak renkler bu tek kuralla türetilir:
///
///     bright = round(base + (255 - base) * lift)     // sRGB kanalları, lift = 0.25
///
/// Yani her kanal beyaza doğru %25 çekilir. Ton (hue) korunur, renk yalnızca açılır;
/// aynı renk ailesi içinde kalındığı için parlak/normal çiftleri terminalde ayırt edilir
/// ama tema karakteri bozulmaz. Kural `Resources/Themes/termora-dark.json`'daki 8-15
/// değerlerine uygulanmıştır ve `ThemeTests` tarafından doğrulanır.
enum ThemeColorDerivation {

    /// Parlak renkler için varsayılan aydınlatma oranı.
    static let brightLift: Double = 0.25

    /// "#RRGGBB" veya "#RRGGBBAA" (alfa yok sayılır) girdisini aydınlatıp "#RRGGBB" döndürür.
    /// Ayrıştırılamayan girdi için `nil`.
    static func brightened(_ hex: String, lift: Double = brightLift) -> String? {
        guard let channels = rgbChannels(hex) else { return nil }
        let clampedLift = min(max(lift, 0), 1)
        let lifted = channels.map { channel -> Int in
            let value = Double(channel) + (255.0 - Double(channel)) * clampedLift
            return min(255, max(0, Int(value.rounded())))
        }
        return String(format: "#%02X%02X%02X", lifted[0], lifted[1], lifted[2])
    }

    private static func rgbChannels(_ hex: String) -> [Int]? {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") {
            text.removeFirst()
        }
        guard text.count == 6 || text.count == 8,
              text.allSatisfy(\.isHexDigit),
              let value = UInt64(text, radix: 16) else {
            return nil
        }
        let rgb = text.count == 8 ? value >> 8 : value
        return [Int((rgb >> 16) & 0xFF), Int((rgb >> 8) & 0xFF), Int(rgb & 0xFF)]
    }
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
