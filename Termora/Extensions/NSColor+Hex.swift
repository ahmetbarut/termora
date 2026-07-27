import AppKit

extension NSColor {
    /// Parses "#RRGGBB" or "#RRGGBBAA" (leading "#" optional). Returns nil for anything else.
    convenience init?(hexString: String) {
        var text = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") {
            text.removeFirst()
        }
        guard text.count == 6 || text.count == 8,
              text.allSatisfy(\.isHexDigit),
              let value = UInt64(text, radix: 16) else {
            return nil
        }
        let rgb: UInt64
        let alpha: CGFloat
        if text.count == 8 {
            rgb = value >> 8
            alpha = CGFloat(value & 0xFF) / 255.0
        } else {
            rgb = value
            alpha = 1.0
        }
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: alpha)
    }
}
